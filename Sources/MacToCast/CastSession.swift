import Foundation
import Network
import Observation
import os

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "cast")

/// One TLS connection to a Chromecast on port 8009, driving a `CastController`.
@MainActor @Observable
final class CastSession {
    /// Given this Mac's and the Chromecast's address on the connection, returns the stream URL to load.
    typealias MediaURL = @MainActor (_ local: IPv4Address, _ remote: IPv4Address) -> String?

    private(set) var status = CastController.Status.connecting
    /// Called once, when the session fails (not after `stop`).
    var onFailure: ((String) -> Void)?
    private var controller = CastController(mediaURL: "")
    private let mediaURL: MediaURL
    private var decoder = CastMessageDecoder()
    private let connection: NWConnection
    private var heartbeat: Task<Void, Never>?
    private var stopped = false
    private var lastReceived = ContinuousClock.now
    /// The receiver answers our PING every 5 s, so this much silence means the link is gone.
    static let silenceLimit = Duration.seconds(15)

    init(endpoint: NWEndpoint, mediaURL: @escaping MediaURL) {
        self.mediaURL = mediaURL
        connection = NWConnection(to: endpoint, using: Self.parameters())
    }

    func start() {
        log.info("Connecting to \(String(describing: self.connection.endpoint), privacy: .public)")
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.connectionChanged(state) }
        }
        connection.start(queue: .main)
    }

    /// Stops the receiver app so the TV goes back to idle, and returns once STOP is sent.
    func stop() async {
        guard !stopped else { return }
        stopped = true
        heartbeat?.cancel()
        let messages = controller.stop()
        // No receiver session yet, or the connection is already gone: nothing to tell the TV.
        guard !messages.isEmpty, connection.state == .ready else {
            connection.cancel()
            return
        }
        let connection = connection
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            connection.send(content: messages.reduce(Data()) { $0 + $1.framed() }, completion: .contentProcessed { _ in
                connection.cancel()
                done.resume()
            })
        }
    }

    func send(_ messages: [CastMessage]) {
        for message in messages {
            connection.send(content: message.framed(), completion: .contentProcessed { error in
                if let error { log.error("Send failed: \(error, privacy: .public)") }
            })
        }
    }

    private func connectionChanged(_ state: NWConnection.State) {
        log.debug("Connection state: \(String(describing: state), privacy: .public)")
        switch state {
        case .ready:
            log.info("Connected")
            guard let local = Self.ipv4(connection.currentPath?.localEndpoint),
                  let remote = Self.ipv4(connection.currentPath?.remoteEndpoint),
                  let url = mediaURL(local, remote)
            else {
                fail("Can't find this Mac's address on the network")
                return
            }
            controller.mediaURL = url
            lastReceived = .now  // the silence limit counts from a working connection, not from init
            send(controller.start())
            status = controller.status
            receive()
            startHeartbeat()
        case .waiting(let error), .failed(let error):
            fail("Can't reach the Chromecast: \(error.localizedDescription)")
        default:
            break
        }
    }

    private func receive() {
        // The 64 KiB read size keeps one read in line with the decoder's body cap.
        connection.receive(minimumIncompleteLength: 1, maximumLength: CastMessageDecoder.maxBodySize) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                // After our own stop(), the connection closing is expected, not a failure.
                guard let self, !self.stopped else { return }
                if let data, !data.isEmpty {
                    self.lastReceived = .now
                    do {
                        for message in try self.decoder.append(data) {
                            if message.namespace == CastNamespace.media {
                                log.debug("Media: \(message.payload.prefix(500), privacy: .public)")
                            }
                            self.send(self.controller.handle(message))
                        }
                    } catch {
                        // The stream is out of sync after a framing error, so the connection cannot be reused.
                        self.fail("The Chromecast sent an invalid message")
                        return
                    }
                    if self.status != self.controller.status {
                        self.status = self.controller.status
                        log.info("Status: \(String(describing: self.status), privacy: .public)")
                    }
                }
                if isComplete || error != nil {
                    self.fail("The Chromecast closed the connection")
                    return
                }
                self.receive()
            }
        }
    }

    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self else { return }
                // A TV that loses power or Wi-Fi often sends no TCP reset, so silence is the only signal.
                if ContinuousClock.now - self.lastReceived > Self.silenceLimit {
                    self.fail("The Chromecast stopped responding")
                    return
                }
                self.send([CastController.ping()])
            }
        }
    }

    private func fail(_ reason: String) {
        // After stop(), a late failure must not end the cast that replaced this one.
        if stopped { return }
        if case .failed = status { return }
        log.error("\(reason, privacy: .public)")
        status = .failed(reason)
        heartbeat?.cancel()
        connection.cancel()
        onFailure?(reason)
    }

    /// The IPv4 address of an endpoint, also when it is IPv4-mapped IPv6.
    nonisolated static func ipv4(_ endpoint: NWEndpoint?) -> IPv4Address? {
        guard case .hostPort(let host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let address): return address
        case .ipv6(let address): return address.asIPv4
        default: return nil
        }
    }

    private static func parameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        // Chromecasts use a self-signed certificate, so the TLS chain cannot be verified.
        // ponytail: accepts any certificate; Cast device authentication (signed challenge) is the upgrade path.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, .main)
        let parameters = NWParameters(tls: tls)
        // The HTTP server allows the Chromecast by IPv4 address, and the TV fetches the stream from this Mac's IPv4 address.
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        return parameters
    }
}

extension IPv4Address {
    /// `192.168.0.7`, without the interface suffix the debug description can carry.
    var dotted: String { rawValue.map(String.init).joined(separator: ".") }
}
