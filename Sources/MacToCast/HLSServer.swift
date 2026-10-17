import Foundation
import Network
import os

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "http")

/// Serves `HLSStore` over HTTP on a free port, reachable on the LAN. One request per connection.
@MainActor
final class HLSServer {
    static let maxConnections = 32
    static let idleTimeout = Duration.seconds(10)

    var store: HLSStore
    private(set) var port: UInt16?
    private let listener: NWListener
    private var openConnections = 0

    init() throws {
        store = HLSStore(token: HLSStore.randomToken())
        listener = try NWListener(using: .tcp, on: .any)
    }

    /// Starts listening and returns the port once the listener is ready.
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed(let error) = state { log.error("Listener failed: \(error, privacy: .public)") }
                if case .ready = state { self?.port = self?.listener.port?.rawValue }
            }
        }
        listener.start(queue: .main)
        while port == nil {
            if case .failed(let error) = listener.state { throw error }
            try await Task.sleep(for: .milliseconds(20))
        }
        log.info("Serving on port \(self.port ?? 0)")
        return port!
    }

    func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        guard openConnections < Self.maxConnections else {
            connection.cancel()
            return
        }
        openConnections += 1
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .cancelled = state { self?.openConnections -= 1 }
            }
        }
        connection.start(queue: .main)
        read(connection, buffered: Data())
        Task {
            // A client that never finishes its request would otherwise hold a slot forever.
            try? await Task.sleep(for: Self.idleTimeout)
            connection.cancel()
        }
    }

    private func read(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: HTTPRequest.maxHeadSize) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                let buffered = buffered + (data ?? Data())
                switch HTTPRequest.parse(buffered) {
                case .incomplete:
                    if isComplete || error != nil { connection.cancel() } else { self.read(connection, buffered: buffered) }
                case .malformed:
                    self.respond(connection, HTTPResponse(status: 400))
                case .tooLarge:
                    self.respond(connection, HTTPResponse(status: 431))
                case .request(let method, let path):
                    self.respond(connection, HTTPResponse.make(method: method, path: path, store: self.store))
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, _ response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }
}
