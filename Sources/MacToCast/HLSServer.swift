import Foundation
import Network
import os

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "http")

/// Serves `HLSStore` over HTTP on a free port, reachable on the LAN. One request per connection.
@MainActor
final class HLSServer {
    static let maxConnections = 32
    /// Each connection serves one request; anything still open after this is closed.
    static let requestTimeout = Duration.seconds(10)

    var store: HLSStore
    /// Addresses allowed to connect besides loopback. Empty means loopback only; #8 adds the Chromecast.
    var allowedAddresses: Set<IPv4Address> = []
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

    /// Loopback, or an allowed IPv4 address (also when it arrives IPv4-mapped on the IPv6 socket).
    nonisolated static func isAllowed(_ endpoint: NWEndpoint, allowed: Set<IPv4Address>) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        let address: IPv4Address
        switch host {
        case .ipv4(let v4):
            address = v4
        case .ipv6(let v6):
            if v6.isLoopback { return true }
            guard let mapped = v6.asIPv4 else { return false }
            address = mapped
        default:
            return false
        }
        // Compare bytes: IPv4Address equality also compares the interface, and only one side has it (192.168.0.104%en0).
        return address.isLoopback || allowed.contains { $0.rawValue == address.rawValue }
    }

    private func accept(_ connection: NWConnection) {
        // Only the Chromecast (and loopback) may connect, so other LAN devices can neither read the stream
        // nor use up the connection slots.
        guard Self.isAllowed(connection.endpoint, allowed: allowedAddresses), openConnections < Self.maxConnections else {
            log.debug("Refused \(String(describing: connection.endpoint), privacy: .public)")
            connection.cancel()
            return
        }
        openConnections += 1
        // A client that never finishes its request would otherwise hold a slot forever.
        let timeout = Task {
            try? await Task.sleep(for: Self.requestTimeout)
            if !Task.isCancelled { connection.cancel() }
        }
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .failed: connection.cancel()
                case .cancelled:
                    timeout.cancel()
                    self?.openConnections -= 1
                default: break
                }
            }
        }
        connection.start(queue: .main)
        read(connection, buffered: Data())
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
                    let response = HTTPResponse.make(method: method, path: path, store: self.store)
                    // The path holds the token, so it stays private in the log.
                    log.debug("\(method, privacy: .public) \(path) -> \(response.status) from \(String(describing: connection.endpoint), privacy: .public)")
                    self.respond(connection, response)
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, _ response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in connection.cancel() })
    }
}
