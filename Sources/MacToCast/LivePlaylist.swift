import Foundation

/// A sliding-window HLS media playlist for fMP4 segments named `seg-<n>.m4s`, numbered from 0.
struct LivePlaylist {
    /// Segments listed at once. Players start a few segments from the end, so this sets the slack, not the latency.
    static let windowSize = 6

    private var durations: [Double] = []
    private var firstNumber = 0
    /// Must cover every segment's rounded duration; only ever grows, as the spec says it must not change.
    private var targetDuration = 1

    /// Adds the next segment and returns its number.
    mutating func append(duration: Double) -> Int {
        durations.append(duration)
        if durations.count > Self.windowSize {
            durations.removeFirst()
            firstNumber += 1
        }
        targetDuration = max(targetDuration, Int(duration.rounded()))
        return firstNumber + durations.count - 1
    }

    var text: String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:7",
            "#EXT-X-TARGETDURATION:\(targetDuration)",
            "#EXT-X-MEDIA-SEQUENCE:\(firstNumber)",
            #"#EXT-X-MAP:URI="init.mp4""#,
        ]
        for (offset, duration) in durations.enumerated() {
            lines.append("#EXTINF:\(String(format: "%.3f", duration)),")
            lines.append("seg-\(firstNumber + offset).m4s")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension HLSStore {
    /// Segments kept in memory: twice the window, so a client a little behind can still fetch one that just left the list.
    static let keptSegments = 2 * LivePlaylist.windowSize

    mutating func addSegment(_ data: Data, duration: Double) {
        let number = live.append(duration: duration)
        segments[number] = data
        segments[number - Self.keptSegments] = nil
        playlist = live.text
    }
}
