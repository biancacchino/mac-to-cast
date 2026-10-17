import Foundation
import Testing
@testable import MacToCast

@MainActor
@Test func servesThePlaylistOverLoopback() async throws {
    let server = try HLSServer()
    server.store.playlist = "#EXTM3U\n"
    let port = try await server.start()
    defer { server.stop() }

    let base = "http://127.0.0.1:\(port)/\(server.store.token)"
    let (body, response) = try await URLSession.shared.data(from: URL(string: "\(base)/live.m3u8")!)
    let http = try #require(response as? HTTPURLResponse)
    #expect(http.statusCode == 200)
    #expect(http.value(forHTTPHeaderField: "Content-Type") == "application/vnd.apple.mpegurl")
    #expect(body == Data("#EXTM3U\n".utf8))

    let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/wrong/live.m3u8")!)
    #expect((missing as? HTTPURLResponse)?.statusCode == 404)
}
