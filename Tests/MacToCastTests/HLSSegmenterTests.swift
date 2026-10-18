import AVFoundation
import os
import Testing
@testable import MacToCast

/// A solid-color 320x240 frame at `seconds`.
func videoSample(at seconds: Double, gray: UInt8) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 320, 240, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
    let buffer = try #require(pixelBuffer)
    CVPixelBufferLockBaseAddress(buffer, [])
    memset(CVPixelBufferGetBaseAddress(buffer), Int32(gray), CVPixelBufferGetDataSize(buffer))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
        decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
        allocator: nil, imageBuffer: buffer, formatDescription: try #require(format),
        sampleTiming: &timing, sampleBufferOut: &sample
    )
    return try #require(sample)
}

/// 1024 frames of 48 kHz stereo float silence starting at `frame`.
func audioSample(atFrame frame: Int, count: Int = 1024) throws -> CMSampleBuffer {
    var description = AudioStreamBasicDescription(
        mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
    )
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
        allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
    )
    let size = count * 8
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(
        allocator: nil, memoryBlock: nil, blockLength: size, blockAllocator: nil, customBlockSource: nil,
        offsetToData: 0, dataLength: size, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
    )
    CMBlockBufferFillDataBytes(with: 0, blockBuffer: try #require(block), offsetIntoDestination: 0, dataLength: size)
    var sample: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: nil, dataBuffer: try #require(block), formatDescription: try #require(format), sampleCount: count,
        presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: 48000),
        packetDescriptions: nil, sampleBufferOut: &sample
    )
    return try #require(sample)
}

/// Runs `seconds` of generated video and silent audio through a segmenter and returns what it produced.
func encode(seconds: Int) async throws -> [HLSSegmenter.Output] {
    let outputs = OSAllocatedUnfairLock(initialState: [HLSSegmenter.Output]())
    let segmenter = HLSSegmenter(width: 320, height: 240) { output in outputs.withLock { $0.append(output) } }

    // Like ScreenCaptureKit, timestamps start far from zero (host clock).
    let start = 1000.0
    var audioFrame = Int(start * 48000)
    for i in 0..<(seconds * 30) {
        let time = start + Double(i) / 30
        segmenter.appendVideo(try videoSample(at: time, gray: UInt8(i % 128 * 2)))
        while Double(audioFrame) / 48000 < time + 1.0 / 30 {
            segmenter.appendAudio(try audioSample(atFrame: audioFrame))
            audioFrame += 1024
        }
        // The writer expects real-time input and drops what it cannot take, so don't outrun it.
        try await Task.sleep(for: .milliseconds(5))
    }
    await segmenter.finish()
    return outputs.withLock { $0 }
}

@Test func segmenterCutsSegmentsAVFoundationCanRead() async throws {
    let results = try await encode(seconds: 4)
    guard case .initialization(let initSegment) = results.first else {
        Issue.record("first output is not the init segment: \(results)")
        return
    }
    let segments = results.dropFirst().compactMap { output -> (Data, Double)? in
        if case .segment(let data, let duration) = output { return (data, duration) }
        return nil
    }
    #expect(segments.count == results.count - 1)
    #expect(segments.count >= 3)
    for (_, duration) in segments.dropLast() {
        #expect(abs(duration - 1) < 0.1, "segment duration \(duration)")
    }

    // Init segment plus media segments in order is a fragmented MP4 file.
    let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
    defer { try? FileManager.default.removeItem(at: file) }
    try segments.reduce(initSegment) { $0 + $1.0 }.write(to: file)
    let asset = AVURLAsset(url: file)
    let tracks = try await asset.load(.tracks)
    #expect(Set(tracks.map(\.mediaType)) == [.video, .audio])
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 4) < 0.2, "movie duration \(duration)")
}

@Test func captureSizeIsEvenAndFitsIn1080p() {
    #expect(WindowCapture.pixelSize(points: CGSize(width: 800, height: 500), scale: 2) == CGSize(width: 1600, height: 1000))
    // Tall: height limits. 1600x1202 * (1080 / 1202) = 1437.6x1080.
    #expect(WindowCapture.pixelSize(points: CGSize(width: 800, height: 601), scale: 2) == CGSize(width: 1436, height: 1080))
    // Wide: width limits. 3840x1600 * 0.5 = 1920x800.
    #expect(WindowCapture.pixelSize(points: CGSize(width: 1920, height: 800), scale: 2) == CGSize(width: 1920, height: 800))
    #expect(WindowCapture.pixelSize(points: CGSize(width: 333, height: 201), scale: 1) == CGSize(width: 332, height: 200))
    #expect(WindowCapture.pixelSize(points: .zero, scale: 1) == CGSize(width: 2, height: 2))
}

@MainActor
@Test func servedLiveStreamPlaysInAVPlayer() async throws {
    let server = try HLSServer()
    for output in try await encode(seconds: 8) {
        switch output {
        case .initialization(let data): server.store.initSegment = data
        case .segment(let data, let duration): server.store.addSegment(data, duration: duration)
        }
    }
    let port = try await server.start()
    defer { server.stop() }

    let item = AVPlayerItem(url: URL(string: "http://127.0.0.1:\(port)/\(server.store.token)/live.m3u8")!)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    player.play()
    for _ in 0..<100 where item.status == .unknown {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(item.status == .readyToPlay, "\(String(describing: item.error))")
    player.pause()
}
