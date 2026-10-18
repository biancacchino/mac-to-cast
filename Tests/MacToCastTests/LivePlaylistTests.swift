import Foundation
import Testing
@testable import MacToCast

@Test func firstSegmentMakesAPlayablePlaylist() {
    var playlist = LivePlaylist()
    #expect(playlist.append(duration: 1.0) == 0)
    #expect(playlist.text == """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:1
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:1.000,
        seg-0.m4s

        """)
}

@Test func windowSlidesAndMediaSequenceFollows() {
    var playlist = LivePlaylist()
    for _ in 0..<(LivePlaylist.windowSize + 2) { _ = playlist.append(duration: 1.0) }
    #expect(playlist.text.contains("#EXT-X-MEDIA-SEQUENCE:2\n"))
    #expect(!playlist.text.contains("seg-1.m4s"))
    #expect(playlist.text.contains("seg-2.m4s"))
    #expect(playlist.text.contains("seg-\(LivePlaylist.windowSize + 1).m4s"))
    #expect(playlist.text.components(separatedBy: "#EXTINF").count - 1 == LivePlaylist.windowSize)
}

@Test func targetDurationCoversEverySegmentAndNeverShrinks() {
    var playlist = LivePlaylist()
    _ = playlist.append(duration: 2.6)
    #expect(playlist.text.contains("#EXT-X-TARGETDURATION:3\n"))
    for _ in 0..<LivePlaylist.windowSize { _ = playlist.append(duration: 1.0) }
    #expect(playlist.text.contains("#EXT-X-TARGETDURATION:3\n"))
}

@Test func storeDropsSegmentsLongGone() {
    var store = HLSStore(token: "tok")
    for n in 0..<(HLSStore.keptSegments + 1) { store.addSegment(Data([UInt8(n)]), duration: 1.0) }
    #expect(store.segments[0] == nil)
    #expect(store.segments[1] == Data([1]))
    #expect(store.segments.count == HLSStore.keptSegments)
    #expect(store.playlist?.contains("seg-\(HLSStore.keptSegments).m4s") == true)
}
