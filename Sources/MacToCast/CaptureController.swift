import AppKit
import os
import ScreenCaptureKit

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "capture")

/// Lets the user pick a window in the system picker, captures it, and serves it as live HLS.
/// The picker grants access to the picked window only, so the app needs no Screen Recording permission.
@MainActor @Observable
final class CaptureController: NSObject, SCContentSharingPickerObserver {
    /// The playlist on this Mac, for testing in a browser. `nil` while not capturing.
    private(set) var localURL: URL?
    private(set) var errorMessage: String?

    private var server: HLSServer?
    private var capture: WindowCapture?

    func pickWindow() {
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        picker.defaultConfiguration = configuration
        picker.remove(self)
        picker.add(self)
        picker.isActive = true
        picker.present(using: .window)
    }

    func stop() async {
        await capture?.stop()
        capture = nil
        localURL = nil
        // Drop the segments; they hold screen content.
        server?.store = HLSStore(token: HLSStore.randomToken())
    }

    private func start(_ filter: SCContentFilter) async {
        await stop()
        errorMessage = nil
        do {
            let server = try self.server ?? HLSServer()
            self.server = server
            let port: UInt16
            if let running = server.port { port = running } else { port = try await server.start() }
            // A fresh token per capture, so outputs still arriving from the previous one are ignored.
            let token = server.store.token
            let capture = WindowCapture(
                filter: filter,
                onOutput: { output in Task { @MainActor [weak self] in self?.receive(output, token: token) } },
                onStop: { error in Task { @MainActor [weak self] in self?.captureEnded(error) } }
            )
            try await capture.start()
            // A newer pick came in while this one was starting; it has already replaced the token.
            guard server.store.token == token else {
                await capture.stop()
                return
            }
            self.capture = capture
            localURL = URL(string: "http://localhost:\(port)/\(token)/live.m3u8")
        } catch {
            log.error("Capture failed to start: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func receive(_ output: HLSSegmenter.Output, token: String) {
        guard let server, server.store.token == token else { return }
        switch output {
        case .initialization(let data):
            server.store.initSegment = data
        case .segment(let data, let duration):
            server.store.addSegment(data, duration: duration)
        }
    }

    private func captureEnded(_ error: Error?) {
        errorMessage = error?.localizedDescription ?? "Encoding failed."
        Task { await stop() }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        nonisolated(unsafe) let filter = filter
        Task { @MainActor in await self.start(filter) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {}

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.errorMessage = message }
    }
}
