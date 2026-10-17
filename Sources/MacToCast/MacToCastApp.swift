import AppKit
import Network
import SwiftUI

@main
struct MacToCastApp: App {
    init() {
        if let host = Self.argument(after: "--play-test-stream") {
            let seconds = Self.argument(after: "--seconds").flatMap(Int.init) ?? 60
            Task { await TestStream.play(host: host, seconds: seconds, mute: CommandLine.arguments.contains("--mute")) }
        }
    }

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            Text(AppInfo.name)
                .frame(minWidth: 400, minHeight: 300)
        }
    }

    static func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
}

/// ponytail: `--play-test-stream <host> [--seconds N] [--mute]` is the #5 proof that casting works; #8 replaces it with real UI.
/// Plays Apple's test stream for N seconds, restores the TV's mute state, stops the receiver, and quits.
/// Progress is in the app log (`category: cast`).
@MainActor
enum TestStream {
    static func play(host: String, seconds: Int, mute: Bool) async {
        let session = CastSession(endpoint: .hostPort(host: NWEndpoint.Host(host), port: 8009), mediaURL: CastSession.testStreamURL)
        session.start()
        var restoreMute: Bool?
        if mute {
            for _ in 0..<100 where session.controller.volumeMuted == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if let original = session.controller.volumeMuted {
                session.setMuted(true)
                restoreMute = original
            }
        }
        for _ in 0..<seconds {
            try? await Task.sleep(for: .seconds(1))
            if case .failed = session.status { break }
        }
        if let restoreMute { session.setMuted(restoreMute) }
        session.stop()
        try? await Task.sleep(for: .seconds(1))
        NSApplication.shared.terminate(nil)
    }
}
