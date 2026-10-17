import Foundation
import Testing
@testable import MacToCast

func head(_ text: String) -> Data { Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8) }

@Test func parsesGetAndHead() {
    #expect(HTTPRequest.parse(head("GET /abc/live.m3u8 HTTP/1.1\nHost: x\n\n")) == .request(method: "GET", path: "/abc/live.m3u8"))
    #expect(HTTPRequest.parse(head("HEAD /abc/seg-3.m4s?x=1 HTTP/1.1\n\n")) == .request(method: "HEAD", path: "/abc/seg-3.m4s"))
}

@Test func waitsForTheEndOfTheHead() {
    #expect(HTTPRequest.parse(head("GET /abc/live.m3u8 HTTP/1.1\nHost: x\n")) == .incomplete)
}

@Test func rejectsMalformedAndOversizedHeads() {
    #expect(HTTPRequest.parse(head("garbage\n\n")) == .malformed)
    #expect(HTTPRequest.parse(head("GET live.m3u8 HTTP/1.1\n\n")) == .malformed)
    #expect(HTTPRequest.parse(Data([0xFF, 0xFE, 0x0D, 0x0A, 0x0D, 0x0A])) == .malformed)
    let huge = Data(repeating: UInt8(ascii: "a"), count: HTTPRequest.maxHeadSize + 1)
    #expect(HTTPRequest.parse(huge) == .tooLarge)
}

func store() -> HLSStore {
    var store = HLSStore(token: "tok")
    store.playlist = "#EXTM3U\n"
    store.initSegment = Data([1, 2, 3])
    store.segments[7] = Data([4, 5])
    return store
}

@Test func servesEachPathWithItsType() {
    let playlist = HTTPResponse.make(method: "GET", path: "/tok/live.m3u8", store: store())
    #expect(playlist.status == 200)
    #expect(playlist.headers["Content-Type"] == "application/vnd.apple.mpegurl")
    #expect(playlist.headers["Cache-Control"] == "no-cache")
    #expect(playlist.headers["Access-Control-Allow-Origin"] == "*")
    #expect(playlist.body == Data("#EXTM3U\n".utf8))

    let initSegment = HTTPResponse.make(method: "GET", path: "/tok/init.mp4", store: store())
    #expect(initSegment.headers["Content-Type"] == "video/mp4")
    #expect(initSegment.body == Data([1, 2, 3]))

    let segment = HTTPResponse.make(method: "GET", path: "/tok/seg-7.m4s", store: store())
    #expect(segment.headers["Content-Type"] == "video/iso.segment")
    #expect(segment.body == Data([4, 5]))
}

@Test func unknownPathsAndWrongTokensAre404() {
    for path in ["/other/live.m3u8", "/live.m3u8", "/tok/seg-8.m4s", "/tok/seg-x.m4s", "/tok/../tok/live.m3u8", "/tok/"] {
        #expect(HTTPResponse.make(method: "GET", path: path, store: store()).status == 404, "\(path)")
    }
}

@Test func headHasNoBodyAndOtherMethodsAre405() {
    let head = HTTPResponse.make(method: "HEAD", path: "/tok/live.m3u8", store: store())
    #expect(head.status == 200)
    #expect(head.body.isEmpty)
    #expect(head.headers["Content-Length"] == "8")
    #expect(HTTPResponse.make(method: "POST", path: "/tok/live.m3u8", store: store()).status == 405)
}

@Test func serializesStatusLineAndHeaders() {
    let text = String(decoding: HTTPResponse.make(method: "GET", path: "/nope", store: store()).serialized(), as: UTF8.self)
    #expect(text.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
    #expect(text.contains("Connection: close\r\n"))
    #expect(text.contains("\r\n\r\n"))
}
