import Foundation
import Testing
@testable import MacToCast

let ping = CastMessage(
    sourceID: "sender-0",
    destinationID: "receiver-0",
    namespace: "urn:x-cast:com.google.cast.tp.heartbeat",
    payload: #"{"type":"PING"}"#
)

// Built by hand from the protobuf wire format: tag byte (field << 3 | wire type), then value.
let pingBytes: Data = {
    var d = Data([0x00, 0x00, 0x00, 0x54])     // body length 84
    d += [0x08, 0x00]                          // 1 protocol_version = 0
    d += [0x12, 0x08]; d += Data("sender-0".utf8)
    d += [0x1A, 0x0A]; d += Data("receiver-0".utf8)
    d += [0x22, 0x27]; d += Data("urn:x-cast:com.google.cast.tp.heartbeat".utf8)
    d += [0x28, 0x00]                          // 5 payload_type = STRING
    d += [0x32, 0x0F]; d += Data(#"{"type":"PING"}"#.utf8)
    return d
}()

@Test func encodesPingToKnownBytes() {
    #expect(ping.framed() == pingBytes)
}

@Test func decodesKnownBytesToPing() throws {
    var decoder = CastMessageDecoder()
    #expect(try decoder.append(pingBytes) == [ping])
}

@Test func longPayloadUsesTwoByteVarintLength() throws {
    var message = ping
    message.payload = String(repeating: "a", count: 200)
    let bytes = message.framed()

    // 200 = 0b1_1001000 -> low 7 bits with the "more" bit (0xC8), then 1 (0x01).
    let payloadTag = bytes.lastIndex(of: 0x32)!
    #expect(Array(bytes[payloadTag + 1 ... payloadTag + 2]) == [0xC8, 0x01])

    var decoder = CastMessageDecoder()
    #expect(try decoder.append(bytes) == [message])
}

@Test func waitsForMessagesSplitAcrossChunks() throws {
    var decoder = CastMessageDecoder()
    var decoded: [CastMessage] = []
    for byte in pingBytes {
        decoded += try decoder.append(Data([byte]))
    }
    #expect(decoded == [ping])
}

@Test func returnsEveryMessageInOneChunk() throws {
    var pong = ping
    pong.payload = #"{"type":"PONG"}"#
    var decoder = CastMessageDecoder()
    #expect(try decoder.append(pingBytes + pong.framed()) == [ping, pong])
}

@Test func skipsUnknownFields() throws {
    var bytes = pingBytes
    bytes += [0x48, 0x01]              // unknown field 9, varint 1
    bytes += [0x42, 0x02, 0xFF, 0xFE]  // unknown field 8, 2 bytes that are not UTF-8
    bytes[3] = 0x5A                    // body length 84 + 6 = 90
    var decoder = CastMessageDecoder()
    #expect(try decoder.append(bytes) == [ping])
}

@Test func rejectsLengthOverTheCap() {
    var decoder = CastMessageDecoder()
    #expect(throws: CastMessageError.tooLarge(0x0010_0000)) {
        try decoder.append(Data([0x00, 0x10, 0x00, 0x00]))
    }
}

@Test func rejectsStringRunningPastTheBody() {
    // Body is 2 bytes: field 2, length 5, but no string bytes follow.
    var decoder = CastMessageDecoder()
    #expect(throws: CastMessageError.malformed) {
        try decoder.append(Data([0x00, 0x00, 0x00, 0x02, 0x12, 0x05]))
    }
}

@Test func rejectsCutOffVarint() {
    // Body is 1 byte: a tag with the "more" bit set and nothing after it.
    var decoder = CastMessageDecoder()
    #expect(throws: CastMessageError.malformed) {
        try decoder.append(Data([0x00, 0x00, 0x00, 0x01, 0x80]))
    }
}

@Test func rejectsBinaryPayload() {
    var bytes = pingBytes
    let payloadType = bytes.firstIndex(of: 0x28)!
    bytes[payloadType + 1] = 0x01  // payload_type = BINARY
    var decoder = CastMessageDecoder()
    #expect(throws: CastMessageError.binaryPayload) {
        try decoder.append(bytes)
    }
}
