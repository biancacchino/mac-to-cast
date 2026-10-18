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
            VStack(spacing: 0) {
                DeviceListView()
                Divider()
                CaptureBar()
            }
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
        let session = CastSession(endpoint: .hostPort(host: NWEndpoint.Host(host), port: 8009), mediaURL: CastSession.testStreamURL, streamType: "BUFFERED")
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

struct DeviceListView: View {
    @State private var browser = DeviceBrowser()

    var body: some View {
        Group {
            if let message = browser.errorMessage {
                ContentUnavailableView("Can't search the network", systemImage: "wifi.exclamationmark", description: Text(message))
            } else if browser.devices.isEmpty {
                ProgressView("Looking for Chromecasts…")
            } else {
                List(browser.devices) { Label($0.name, systemImage: "tv") }
            }
        }
        .task { browser.start() }
    }
}

/// ponytail: a bare row to test capture in a browser; #8 and #10 replace it with the real flow.
struct CaptureBar: View {
    @State private var capture = CaptureController()

    var body: some View {
        HStack {
            if let url = capture.localURL {
                Text(url.absoluteString)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
                Button("Stop") { Task { await capture.stop() } }
            } else {
                Text(capture.errorMessage ?? "No window chosen")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose Window…") { capture.pickWindow() }
            }
        }
        .padding()
    }
}
