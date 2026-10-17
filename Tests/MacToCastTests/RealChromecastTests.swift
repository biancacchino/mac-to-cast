import Foundation
import Network
import Testing
@testable import MacToCast

/// Plays Apple's test stream on a real Chromecast. Runs only when `CAST_HOST` is set, so CI never touches a TV:
/// `CAST_HOST=192.168.0.104 CAST_SECONDS=330 swift test --filter RealChromecast`
/// The TV is muted while it plays and its previous mute state is restored at the end.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CAST_HOST"] != nil), .timeLimit(.minutes(10)))
struct RealChromecastTests {
    @Test func playsTestStreamAndKeepsPlaying() async throws {
        let env = ProcessInfo.processInfo.environment
        let host = try #require(env["CAST_HOST"])
        let seconds = Int(env["CAST_SECONDS"] ?? "") ?? 30
        let session = CastSession(endpoint: .hostPort(host: NWEndpoint.Host(host), port: 8009), mediaURL: CastSession.testStreamURL)
        session.start()

        guard let originalMute = await waitFor(10, { session.controller.volumeMuted }) else {
            Issue.record("No RECEIVER_STATUS from \(host): \(session.status)")
            return
        }
        session.setMuted(true)
        defer { session.setMuted(originalMute); session.stop() }

        _ = await waitFor(60) { session.status == .media("PLAYING") ? true : nil }
        #expect(session.status == .media("PLAYING"))

        for _ in 0..<seconds {
            try await Task.sleep(for: .seconds(1))
            if case .failed = session.status { break }
        }
        #expect(session.status == .media("PLAYING"))
    }

    private func waitFor<T>(_ seconds: Int, _ check: () -> T?) async -> T? {
        for _ in 0..<(seconds * 10) {
            if let value = check() { return value }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
