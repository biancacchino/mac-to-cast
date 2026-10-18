import Foundation

enum CastNamespace {
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiver = "urn:x-cast:com.google.cast.receiver"
    static let media = "urn:x-cast:com.google.cast.media"
}

/// The CastV2 conversation for playing one HLS URL on the Default Media Receiver.
/// Pure logic: messages in, messages out. `CastSession` does the network I/O.
/// Incoming payloads come from the device, so anything unexpected is ignored rather than trusted.
struct CastController {
    enum Status: Equatable {
        case connecting, launching, loading
        /// The receiver's `playerState`, for example `BUFFERING` or `PLAYING`.
        case media(String)
        case failed(String)
    }

    static let defaultMediaReceiver = "CC1AD845"
    static let sender = "sender-0"
    static let platform = "receiver-0"

    /// Set before the receiver app is ready; `CastSession` knows it only once connected.
    var mediaURL: String
    private(set) var status = Status.connecting
    private var transportID: String?
    private var sessionID: String?
    private var nextRequestID = 1

    init(mediaURL: String) {
        self.mediaURL = mediaURL
    }

    mutating func start() -> [CastMessage] {
        status = .launching
        return [
            Self.message(CastNamespace.connection, to: Self.platform, ["type": "CONNECT"]),
            Self.message(CastNamespace.receiver, to: Self.platform, ["type": "LAUNCH", "appId": Self.defaultMediaReceiver, "requestId": requestID()]),
        ]
    }

    /// Ends the receiver app so the TV goes back to idle.
    mutating func stop() -> [CastMessage] {
        guard let sessionID else { return [] }
        return [Self.message(CastNamespace.receiver, to: Self.platform, ["type": "STOP", "sessionId": sessionID, "requestId": requestID()])]
    }

    static func ping() -> CastMessage {
        message(CastNamespace.heartbeat, to: platform, ["type": "PING"])
    }

    mutating func handle(_ incoming: CastMessage) -> [CastMessage] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(incoming.payload.utf8)) as? [String: Any],
              let type = json["type"] as? String
        else { return [] }

        switch (incoming.namespace, type) {
        case (CastNamespace.heartbeat, "PING"):
            return [Self.message(CastNamespace.heartbeat, to: incoming.sourceID, ["type": "PONG"])]
        case (CastNamespace.receiver, "RECEIVER_STATUS"):
            return receiverStatus(json)
        case (CastNamespace.receiver, "LAUNCH_ERROR"):
            status = .failed("Launch failed: \(json["reason"] as? String ?? "unknown reason")")
        case (CastNamespace.media, "MEDIA_STATUS"):
            let media = (json["status"] as? [[String: Any]])?.first
            if media?["idleReason"] as? String == "ERROR" {
                status = .failed("The Chromecast could not play the stream")
            } else if let state = media?["playerState"] as? String {
                status = .media(state)
            }
        case (CastNamespace.media, "LOAD_FAILED"), (CastNamespace.media, "LOAD_CANCELLED"):
            status = .failed("The Chromecast could not load the stream")
        case (CastNamespace.connection, "CLOSE") where incoming.sourceID == transportID:
            status = .failed("The Chromecast closed the stream")
        default:
            break
        }
        return []
    }

    private mutating func receiverStatus(_ json: [String: Any]) -> [CastMessage] {
        // Load once: later RECEIVER_STATUS messages (for example volume changes) must not restart playback.
        guard transportID == nil,
              let apps = (json["status"] as? [String: Any])?["applications"] as? [[String: Any]],
              let app = apps.first(where: { $0["appId"] as? String == Self.defaultMediaReceiver }),
              let transport = app["transportId"] as? String
        else { return [] }
        transportID = transport
        sessionID = app["sessionId"] as? String
        status = .loading
        // The receiver assumes MPEG-TS segments unless told otherwise; ours are fMP4.
        let media: [String: Any] = [
            "contentId": mediaURL, "contentType": "application/x-mpegURL", "streamType": "LIVE",
            "hlsSegmentFormat": "fmp4", "hlsVideoSegmentFormat": "fmp4",
        ]
        return [
            Self.message(CastNamespace.connection, to: transport, ["type": "CONNECT"]),
            Self.message(CastNamespace.media, to: transport, ["type": "LOAD", "media": media, "autoplay": true, "requestId": requestID()]),
        ]
    }

    private mutating func requestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private static func message(_ namespace: String, to destination: String, _ json: [String: Any]) -> CastMessage {
        // Only our own dictionaries of strings, ints, and bools reach here, so serialization cannot fail.
        let data = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return CastMessage(sourceID: sender, destinationID: destination, namespace: namespace, payload: String(decoding: data, as: UTF8.self))
    }
}
