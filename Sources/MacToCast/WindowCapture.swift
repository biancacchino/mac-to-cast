import os
import ScreenCaptureKit

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "capture")

/// Captures one window's video and its app's audio with ScreenCaptureKit and feeds them to an `HLSSegmenter`.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    static let maxWidth: CGFloat = 1920
    /// ScreenCaptureKit sends no frame while the window does not change; the last one is repeated this often.
    static let repeatInterval = 0.1

    private let filter: SCContentFilter
    private let configuration = SCStreamConfiguration()
    private let segmenter: HLSSegmenter
    private let onStop: @Sendable (Error?) -> Void
    /// Sample callbacks and the repeat timer run here, so the state below is only touched on this queue.
    private let queue = DispatchQueue(label: "com.biancacchino.MacToCast.capture")
    private var stream: SCStream?
    private var lastFrame: CMSampleBuffer?
    private var stopped = false
    private var repeater: DispatchSourceTimer?

    /// `onOutput` gets the init segment, then each media segment. `onStop` is called once, when capture ends on its own.
    init(filter: SCContentFilter, onOutput: @escaping @Sendable (HLSSegmenter.Output) -> Void, onStop: @escaping @Sendable (Error?) -> Void) {
        let size = Self.pixelSize(points: filter.contentRect.size, scale: CGFloat(filter.pointPixelScale))
        configuration.width = Int(size.width)
        configuration.height = Int(size.height)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        self.filter = filter
        self.onStop = onStop
        segmenter = HLSSegmenter(width: Int(size.width), height: Int(size.height), onOutput: onOutput)
    }

    /// The window's size in pixels, scaled down to `maxWidth`, rounded down to even numbers as H.264 needs.
    static func pixelSize(points: CGSize, scale: CGFloat) -> CGSize {
        var size = CGSize(width: points.width * scale, height: points.height * scale)
        if size.width > maxWidth {
            size = CGSize(width: maxWidth, height: size.height * maxWidth / size.width)
        }
        func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded(.down) * 2) }
        return CGSize(width: even(size.width), height: even(size.height))
    }

    func start() async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await stream.startCapture()
        queue.sync {
            self.stream = stream
            let repeater = DispatchSource.makeTimerSource(queue: queue)
            repeater.schedule(deadline: .now() + Self.repeatInterval, repeating: Self.repeatInterval)
            repeater.setEventHandler { [weak self] in self?.repeatLastFrame() }
            repeater.resume()
            self.repeater = repeater
        }
        log.info("Capturing \(Int(self.configuration.width))x\(Int(self.configuration.height))")
    }

    func stop() async {
        let stream = queue.sync {
            stopped = true
            repeater?.cancel()
            return self.stream
        }
        try? await stream?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sample) else { return }
            appendVideo(sample)
        case .audio:
            segmenter.appendAudio(sample)
        default:
            break
        }
        if segmenter.failed { finish(with: nil) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.finish(with: error) }
    }

    private func appendVideo(_ sample: CMSampleBuffer) {
        // A repeated frame may carry a later time than a real frame still on its way; times must only go up.
        if let last = lastFrame, sample.presentationTimeStamp <= last.presentationTimeStamp { return }
        lastFrame = sample
        segmenter.appendVideo(sample)
    }

    private func repeatLastFrame() {
        guard let last = lastFrame else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard (now - last.presentationTimeStamp).seconds >= Self.repeatInterval else { return }
        let timing = CMSampleTimingInfo(duration: last.duration, presentationTimeStamp: now, decodeTimeStamp: .invalid)
        guard let copy = try? CMSampleBuffer(copying: last, withNewTiming: [timing]) else { return }
        appendVideo(copy)
    }

    private func finish(with error: Error?) {
        guard !stopped else { return }
        stopped = true
        repeater?.cancel()
        log.error("Capture stopped: \(error?.localizedDescription ?? "the encoder failed", privacy: .public)")
        onStop(error)
    }

    /// ScreenCaptureKit also sends status-only buffers (idle, blank); only complete frames carry an image.
    private static func isCompleteFrame(_ sample: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int
        else { return false }
        return SCFrameStatus(rawValue: raw) == .complete
    }
}
