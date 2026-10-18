import CoreVideo
import IOSurface

/// Windows playing protected video (Netflix and friends) come out of ScreenCaptureKit as protected surfaces.
/// The H.264 encoder fails on them, so they are swapped for a black frame and the menu says why.
enum ProtectedFrame {
    /// ponytail: reads an undocumented creation property; if a future macOS drops it, the encoder fails instead
    /// and `Caster` still shows the notice (see `captureEnded`).
    static func isProtected(_ frame: CVPixelBuffer) -> Bool {
        guard let surface = CVPixelBufferGetIOSurface(frame)?.takeUnretainedValue(),
              let values = IOSurfaceCopyAllValues(surface) as? [String: Any],
              let creation = values["CreationProperties"] as? [String: Any],
              let options = creation["IOSurfaceProtectionOptions"] as? Int
        else { return false }
        return options != 0
    }

    /// A video-range black 420v frame: luma 16, chroma 128.
    static func black(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        for (plane, value) in [(0, 16), (1, 128)] {
            memset(CVPixelBufferGetBaseAddressOfPlane(buffer, plane), Int32(value),
                   CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}
