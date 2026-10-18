import Foundation
import Testing
@testable import MacToCast

let mediaURL = "https://example.com/live.m3u8"

func payload(_ message: CastMessage) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(message.payload.utf8))) as? [String: Any] ?? [:]
}

func incoming(_ namespace: String, from source: String = "receiver-0", _ json: String) -> CastMessage {
    CastMessage(sourceID: source, destinationID: "sender-0", namespace: namespace, payload: json)
}

let receiverStatus = #"""
{"type":"RECEIVER_STATUS","requestId":1,"status":{"applications":[
  {"appId":"CC1AD845","sessionId":"session-1","transportId":"transport-1"}
],"volume":{"level":0.5,"muted":false}}}
"""#

@Test func startConnectsAndLaunchesTheDefaultReceiver() {
    var controller = CastController(mediaURL: mediaURL)
    let sent = controller.start()
    #expect(sent.map(\.namespace) == [CastNamespace.connection, CastNamespace.receiver])
    #expect(sent.allSatisfy { $0.destinationID == "receiver-0" })
    #expect(payload(sent[0])["type"] as? String == "CONNECT")
    #expect(payload(sent[1])["type"] as? String == "LAUNCH")
    #expect(payload(sent[1])["appId"] as? String == "CC1AD845")
    #expect(controller.status == .launching)
}

@Test func answersPingWithPong() {
    var controller = CastController(mediaURL: mediaURL)
    let sent = controller.handle(incoming(CastNamespace.heartbeat, #"{"type":"PING"}"#))
    #expect(sent.count == 1)
    #expect(sent[0].namespace == CastNamespace.heartbeat)
    #expect(payload(sent[0])["type"] as? String == "PONG")
}

@Test func connectsToTheAppAndLoadsTheStreamOnce() {
    var controller = CastController(mediaURL: mediaURL)
    _ = controller.start()
    let sent = controller.handle(incoming(CastNamespace.receiver, receiverStatus))
    #expect(sent.map(\.namespace) == [CastNamespace.connection, CastNamespace.media])
    #expect(sent.allSatisfy { $0.destinationID == "transport-1" })
    let media = payload(sent[1])["media"] as? [String: Any]
    #expect(payload(sent[1])["type"] as? String == "LOAD")
    #expect(media?["contentId"] as? String == mediaURL)
    #expect(media?["streamType"] as? String == "LIVE")
    // Without these the receiver expects MPEG-TS segments and never plays our fMP4 ones.
    #expect(media?["hlsSegmentFormat"] as? String == "fmp4")
    #expect(media?["hlsVideoSegmentFormat"] as? String == "fmp4")
    #expect(controller.status == .loading)

    // Later RECEIVER_STATUS messages (volume changes) must not reload.
    #expect(controller.handle(incoming(CastNamespace.receiver, receiverStatus)).isEmpty)
}

@Test func mediaStatusReportsPlayerState() {
    var controller = CastController(mediaURL: mediaURL)
    _ = controller.start()
    _ = controller.handle(incoming(CastNamespace.receiver, receiverStatus))
    let status = #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":1,"playerState":"PLAYING"}]}"#
    _ = controller.handle(incoming(CastNamespace.media, from: "transport-1", status))
    #expect(controller.status == .media("PLAYING"))
}

@Test func playbackErrorAfterLoadFails() {
    var controller = CastController(mediaURL: mediaURL)
    let status = #"{"type":"MEDIA_STATUS","status":[{"playerState":"IDLE","idleReason":"ERROR"}]}"#
    _ = controller.handle(incoming(CastNamespace.media, from: "transport-1", status))
    #expect(controller.status == .failed("The Chromecast could not play the stream"))
}

@Test func launchAndLoadErrorsFail() {
    var launch = CastController(mediaURL: mediaURL)
    _ = launch.handle(incoming(CastNamespace.receiver, #"{"type":"LAUNCH_ERROR","reason":"NOT_FOUND"}"#))
    #expect(launch.status == .failed("Launch failed: NOT_FOUND"))

    var load = CastController(mediaURL: mediaURL)
    _ = load.handle(incoming(CastNamespace.media, from: "transport-1", #"{"type":"LOAD_FAILED"}"#))
    #expect(load.status == .failed("The Chromecast could not load the stream"))
}

@Test func ignoresGarbageAndUnknownMessages() {
    var controller = CastController(mediaURL: mediaURL)
    #expect(controller.handle(incoming(CastNamespace.receiver, "not json")).isEmpty)
    #expect(controller.handle(incoming(CastNamespace.receiver, #"{"type":"RECEIVER_STATUS","status":7}"#)).isEmpty)
    #expect(controller.handle(incoming("urn:x-cast:com.example", #"{"type":"PING"}"#)).isEmpty)
    #expect(controller.status == .connecting)
}

@Test func stopEndsTheReceiverSession() {
    var controller = CastController(mediaURL: mediaURL)
    #expect(controller.stop().isEmpty)  // nothing launched yet
    _ = controller.start()
    _ = controller.handle(incoming(CastNamespace.receiver, receiverStatus))
    let sent = controller.stop()
    #expect(sent.count == 1)
    #expect(payload(sent[0])["type"] as? String == "STOP")
    #expect(payload(sent[0])["sessionId"] as? String == "session-1")
}
