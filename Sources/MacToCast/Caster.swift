import AppKit
import Network
import os
import ScreenCaptureKit

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "capture")

/// Casts one window to one Chromecast: the user picks a TV, then a window in the system picker.
/// The picker grants access to the picked window only, so the app needs no Screen Recording permission.
@MainActor @Observable
final class Caster: NSObject, SCContentSharingPickerObserver {
    let browser = DeviceBrowser()
    /// The TV being cast to, from the moment the user picks it. `nil` when idle.
    private(set) var device: CastDevice?
    private(set) var session: CastSession?
    /// Why the last cast ended, shown until the next one starts.
    private(set) var errorMessage: String?
    /// The cast window plays protected video, which blocks screen capture, so the TV shows black.
    private(set) var blocked = false

    private var server: HLSServer?
    private var capture: WindowCapture?

    override init() {
        super.init()
        browser.start()
    }

    var statusText: String? {
        if device != nil, blocked { return "This window blocks screen capture, so the TV shows black" }
        if let device, let session { return Self.statusText(session.status, device: device.name) }
        if let device { return "Choose a window to cast to \(device.name)" }
        return errorMessage
    }

    nonisolated static func statusText(_ status: CastController.Status, device: String) -> String {
        switch status {
        case .connecting: "Connecting to \(device)…"
        case .launching, .loading, .media("IDLE"): "Starting on \(device)…"
        case .media("BUFFERING"): "Buffering on \(device)…"
        case .media: "Casting to \(device)"
        case .failed(let reason): reason
        }
    }

    func cast(to device: CastDevice) {
        log.info("Chose \(device.name, privacy: .public); opening the window picker")
        Task {
            await stop()
            self.device = device
            let picker = SCContentSharingPicker.shared
            var configuration = SCContentSharingPickerConfiguration()
            configuration.allowedPickerModes = .singleWindow
            picker.defaultConfiguration = configuration
            picker.remove(self)
            picker.add(self)
            picker.isActive = true
            // A menu bar app is not active by itself, and the picker needs it to be.
            NSApp.activate()
            picker.present(using: .window)
        }
    }

    func stop() async {
        device = nil
        errorMessage = nil
        await stopStreaming()
        // While active, macOS shows a sharing indicator in the menu bar.
        SCContentSharingPicker.shared.isActive = false
    }

    private func end(_ reason: String) async {
        log.error("Cast ended: \(reason, privacy: .public)")
        await stop()
        errorMessage = reason
    }

    private func stopStreaming() async {
        blocked = false
        await session?.stop()
        session = nil
        await capture?.stop()
        capture = nil
        server?.allowedAddresses = []
        // Drop the segments; they hold screen content. The new token also makes old URLs and late outputs dead.
        server?.store = HLSStore(token: HLSStore.randomToken())
    }

    private func start(_ filter: SCContentFilter) async {
        guard let device else { return }
        // A new pick (also from the system's sharing indicator) means a new stream URL, so restart both sides.
        await stopStreaming()
        do {
            let server = try self.server ?? HLSServer()
            self.server = server
            if server.port == nil { _ = try await server.start() }
            let token = server.store.token
            let capture = WindowCapture(
                filter: filter,
                onOutput: { output in Task { @MainActor [weak self] in self?.receive(output, token: token) } },
                onStop: { error in Task { @MainActor [weak self] in await self?.captureEnded(error, token: token) } },
                onBlocked: { blocked in Task { @MainActor [weak self] in self?.windowBlocked(blocked, token: token) } }
            )
            try await capture.start()
            // Another pick or a stop came in while this one was starting; it has already replaced the token.
            guard server.store.token == token, self.device?.id == device.id else {
                await capture.stop()
                return
            }
            self.capture = capture
            // The session starts in `receive` once the first segment exists, so the TV never gets a 404 playlist.
        } catch {
            await end(error.localizedDescription)
        }
    }

    private func receive(_ output: HLSSegmenter.Output, token: String) {
        guard let server, server.store.token == token else { return }
        switch output {
        case .initialization(let data):
            server.store.initSegment = data
        case .segment(let data, let duration):
            server.store.addSegment(data, duration: duration)
            if session == nil { startSession(token: token) }
        }
    }

    private func startSession(token: String) {
        guard let device, let port = server?.port else { return }
        let session = CastSession(endpoint: device.endpoint) { [weak self] local, remote in
            guard let server = self?.server, server.store.token == token else { return nil }
            server.allowedAddresses = [remote]
            return "http://\(local.dotted):\(port)/\(token)/live.m3u8"
        }
        session.onFailure = { [weak self] reason in Task { await self?.end(reason) } }
        self.session = session
        session.start()
    }

    private func windowBlocked(_ blocked: Bool, token: String) {
        guard server?.store.token == token else { return }
        log.info("Window blocks capture: \(blocked)")
        self.blocked = blocked
    }

    private func captureEnded(_ error: Error?, token: String) async {
        guard server?.store.token == token else { return }
        // The encoder also fails on protected video if `ProtectedFrame` ever stops spotting it.
        await end(error == nil ? "Can't encode this window. If it plays protected video, it blocks screen capture" : "The window was closed or can't be captured")
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        log.info("Window picked")
        nonisolated(unsafe) let filter = filter
        Task { @MainActor in await self.start(filter) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        log.info("Window picker cancelled")
        Task { @MainActor in
            // Cancelled before anything started: drop the chosen TV.
            if self.session == nil { await self.stop() }
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        log.error("Window picker failed: \(error.localizedDescription, privacy: .public)")
        let message = error.localizedDescription
        Task { @MainActor in await self.end(message) }
    }
}
