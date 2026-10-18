import AVFoundation
import os
import UniformTypeIdentifiers

private let log = Logger(subsystem: "com.biancacchino.MacToCast", category: "capture")

/// Encodes video and audio to H.264 and AAC, and cuts them into 1 s fMP4 HLS segments.
/// `AVAssetWriter` with the `.mpeg4AppleHLS` profile does the muxing, so there is no muxer here.
/// Not thread-safe: call `appendVideo`, `appendAudio`, and `finish` from one serial queue.
final class HLSSegmenter: NSObject, AVAssetWriterDelegate, @unchecked Sendable {
    enum Output: Sendable {
        case initialization(Data)
        case segment(Data, duration: Double)
    }

    private let writer = AVAssetWriter(contentType: .mpeg4Movie)
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput
    private let onOutput: @Sendable (Output) -> Void
    private var started = false

    /// `onOutput` is called on a queue owned by AVFoundation.
    init(width: Int, height: Int, onOutput: @escaping @Sendable (Output) -> Void) {
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 6_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                // A segment can only start on a keyframe.
                AVVideoMaxKeyFrameIntervalDurationKey: 1,
                // No B-frames: the encoder does not hold frames back, which cuts latency.
                AVVideoAllowFrameReorderingKey: false,
            ],
        ])
        audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ])
        video.expectsMediaDataInRealTime = true
        audio.expectsMediaDataInRealTime = true
        self.onOutput = onOutput
        super.init()
        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = CMTime(value: 1, timescale: 1)
        writer.delegate = self
        writer.add(video)
        writer.add(audio)
    }

    var failed: Bool { writer.status == .failed }

    /// The first video frame starts the stream; audio before it is dropped.
    func appendVideo(_ sample: CMSampleBuffer) {
        if !started {
            // Starting a writer twice raises an exception, so a writer that failed to start stays failed.
            guard writer.status == .unknown else { return }
            writer.initialSegmentStartTime = sample.presentationTimeStamp
            guard writer.startWriting() else {
                log.error("Writer did not start: \(self.writer.error?.localizedDescription ?? "unknown", privacy: .public)")
                return
            }
            writer.startSession(atSourceTime: sample.presentationTimeStamp)
            started = true
        }
        append(sample, to: video)
    }

    func appendAudio(_ sample: CMSampleBuffer) {
        guard started else { return }
        append(sample, to: audio)
    }

    /// Flushes the last segment.
    func finish() async {
        guard started, writer.status == .writing else { return }
        video.markAsFinished()
        audio.markAsFinished()
        await writer.finishWriting()
    }

    private func append(_ sample: CMSampleBuffer, to input: AVAssetWriterInput) {
        // ponytail: a sample the encoder has no room for is dropped; live video should catch up, not queue.
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        if !input.append(sample) {
            log.error("Append to \(input.mediaType.rawValue, privacy: .public) failed: \(String(describing: self.writer.error), privacy: .public)")
        }
    }

    func assetWriter(
        _ writer: AVAssetWriter, didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType, segmentReport: AVAssetSegmentReport?
    ) {
        switch segmentType {
        case .initialization:
            onOutput(.initialization(segmentData))
        case .separable:
            let durations = segmentReport?.trackReports.map(\.duration.seconds) ?? []
            onOutput(.segment(segmentData, duration: durations.max() ?? 1))
        @unknown default:
            break
        }
    }
}
