import CoreVideo
import IOSurface
import Testing
@testable import MacToCast

func pixelBuffer(protected: Bool) throws -> CVPixelBuffer {
    var surface: [String: Any] = [:]
    if protected { surface["IOSurfaceProtectionOptions"] = 1 }
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 32, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                        [kCVPixelBufferIOSurfacePropertiesKey: surface] as CFDictionary, &buffer)
    return try #require(buffer)
}

@Test func spotsProtectedFrames() throws {
    #expect(ProtectedFrame.isProtected(try pixelBuffer(protected: false)) == false)
    #expect(ProtectedFrame.isProtected(try pixelBuffer(protected: true)) == true)
}

@Test func blackFrameIsVideoRangeBlack() throws {
    let black = try #require(ProtectedFrame.black(width: 64, height: 32))
    #expect(CVPixelBufferGetWidth(black) == 64)
    #expect(CVPixelBufferGetPixelFormatType(black) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    CVPixelBufferLockBaseAddress(black, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(black, .readOnly) }
    let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(black, 0)).assumingMemoryBound(to: UInt8.self)
    let chroma = try #require(CVPixelBufferGetBaseAddressOfPlane(black, 1)).assumingMemoryBound(to: UInt8.self)
    #expect(luma[0] == 16 && luma[63] == 16)
    #expect(chroma[0] == 128 && chroma[1] == 128)
}
