import Foundation

/// The live stream held in memory, served by `HLSServer` under a secret path prefix.
struct HLSStore {
    /// Random path prefix. The server answers anyone on the LAN with CORS open to all origins
    /// (the Cast receiver is a web page), so only someone who knows the token can read the stream.
    let token: String
    var playlist: String?
    var initSegment: Data?
    var segments: [Int: Data] = [:]

    static func randomToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }
}

/// Reads the request line from an HTTP/1.x request head. The bytes come from the network.
enum HTTPRequest: Equatable {
    static let maxHeadSize = 8192

    case request(method: String, path: String)
    case incomplete
    case malformed
    case tooLarge

    static func parse(_ data: Data) -> HTTPRequest {
        guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeadSize ? .tooLarge : .incomplete
        }
        guard end.lowerBound - data.startIndex <= maxHeadSize else { return .tooLarge }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8),
              let line = head.split(separator: "\r\n", omittingEmptySubsequences: false).first
        else { return .malformed }
        let parts = line.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/1."), parts[1].hasPrefix("/"),
              !parts[0].isEmpty, parts[0].allSatisfy({ $0.isASCII && $0.isUppercase })
        else { return .malformed }
        let path = parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        return .request(method: String(parts[0]), path: String(path))
    }
}

struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    init(status: Int, contentType: String = "text/plain; charset=utf-8", body: Data = Data()) {
        self.status = status
        self.body = body
        headers = [
            "Content-Type": contentType,
            "Content-Length": String(body.count),
            "Access-Control-Allow-Origin": "*",
            "Connection": "close",
        ]
    }

    /// Routes `/<token>/live.m3u8`, `/<token>/init.mp4`, and `/<token>/seg-<n>.m4s`. Everything else is 404.
    static func make(method: String, path: String, store: HLSStore) -> HTTPResponse {
        guard method == "GET" || method == "HEAD" else { return HTTPResponse(status: 405) }
        let parts = path.split(separator: "/")
        // ponytail: plain == on the token; a timing attack over LAN HTTP is not the likely threat here.
        guard parts.count == 2, parts[0] == store.token else { return HTTPResponse(status: 404) }

        var response: HTTPResponse
        switch parts[1] {
        case "live.m3u8":
            guard let playlist = store.playlist else { return HTTPResponse(status: 404) }
            response = HTTPResponse(status: 200, contentType: "application/vnd.apple.mpegurl", body: Data(playlist.utf8))
            response.headers["Cache-Control"] = "no-cache"
        case "init.mp4":
            guard let data = store.initSegment else { return HTTPResponse(status: 404) }
            response = HTTPResponse(status: 200, contentType: "video/mp4", body: data)
        case let name where name.hasPrefix("seg-") && name.hasSuffix(".m4s"):
            guard let number = Int(name.dropFirst(4).dropLast(4)), let data = store.segments[number] else {
                return HTTPResponse(status: 404)
            }
            response = HTTPResponse(status: 200, contentType: "video/iso.segment", body: data)
        default:
            return HTTPResponse(status: 404)
        }
        if method == "HEAD" { response.body = Data() }
        return response
    }

    func serialized() -> Data {
        let reasons = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed", 431: "Request Header Fields Too Large"]
        var text = "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            text += "\(name): \(value)\r\n"
        }
        return Data((text + "\r\n").utf8) + body
    }
}
