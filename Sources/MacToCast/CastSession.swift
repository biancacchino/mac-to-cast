import Foundation
import Network
import Observation
import os

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "cast")

/// One TLS connection to a Chromecast on port 8009, driving a `CastController`.
@MainActor @Observable
final class CastSession {
    static let testStreamURL = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8"

    private(set) var status = CastController.Status.connecting
    private(set) var controller: CastController
    private var decoder = CastMessageDecoder()
    private let connection: NWConnection
    private var heartbeat: Task<Void, Never>?
    private var stopped = false

    init(endpoint: NWEndpoint, mediaURL: String) {
        controller = CastController(mediaURL: mediaURL)
        connection = NWConnection(to: endpoint, using: Self.parameters())
    }

    func start() {
        log.info("Connecting to \(String(describing: self.connection.endpoint), privacy: .public)")
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { self?.connectionChanged(state) }
        }
        connection.start(queue: .main)
    }

    /// Stops the receiver app, then closes the connection once STOP is sent.
    func stop() {
        stopped = true
        heartbeat?.cancel()
        let messages = controller.stop()
        let connection = connection
        connection.send(content: messages.reduce(Data()) { $0 + $1.framed() }, completion: .contentProcessed { _ in connection.cancel() })
    }

    func setMuted(_ muted: Bool) {
        send([controller.setMuted(muted)])
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
                    do {
                        for message in try self.decoder.append(data) {
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
                self?.send([CastController.ping()])
            }
        }
    }

    private func fail(_ reason: String) {
        if case .failed = status { return }
        log.error("\(reason, privacy: .public)")
        status = .failed(reason)
        heartbeat?.cancel()
        connection.cancel()
    }

    private static func parameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        // Chromecasts use a self-signed certificate, so the TLS chain cannot be verified.
        // ponytail: accepts any certificate; Cast device authentication (signed challenge) is the upgrade path.
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, .main)
        return NWParameters(tls: tls)
    }
}
