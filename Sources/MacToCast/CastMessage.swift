import Foundation

/// One CastV2 message: the protobuf `CastMessage` with a UTF-8 string payload.
/// Fields 1-6 are encoded by hand; see the protobuf wire format.
struct CastMessage: Equatable {
    var sourceID: String
    var destinationID: String
    var namespace: String
    var payload: String

    /// The 4-byte big-endian body length, then the protobuf body.
    func framed() -> Data {
        var body: [UInt8] = []
        body.appendVarintField(1, 0)  // protocol_version = CASTV2_1_0
        body.appendStringField(2, sourceID)
        body.appendStringField(3, destinationID)
        body.appendStringField(4, namespace)
        body.appendVarintField(5, 0)  // payload_type = STRING
        body.appendStringField(6, payload)
        return withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) } + body
    }
}

extension CastMessage {
    /// Parses a protobuf body (without the length prefix). The bytes come from the network, so every read is checked.
    init(body: ArraySlice<UInt8>) throws {
        var reader = ProtobufReader(remaining: body)
        var strings: [UInt64: String] = [:]
        while !reader.isAtEnd {
            let tag = try reader.varint()
            let field = tag >> 3
            switch tag & 0x7 {
            case 0:
                let value = try reader.varint()
                if field == 5, value != 0 { throw CastMessageError.binaryPayload }
            case 2:
                let bytes = try reader.take(reader.varint())
                guard let string = String(bytes: bytes, encoding: .utf8) else { throw CastMessageError.malformed }
                strings[field] = string
            // Unknown fixed-size fields are skipped so newer devices still work.
            case 1: _ = try reader.take(8)
            case 5: _ = try reader.take(4)
            default: throw CastMessageError.malformed
            }
        }
        guard let source = strings[2], let destination = strings[3],
              let namespace = strings[4], let payload = strings[6]
        else { throw CastMessageError.malformed }
        self.init(sourceID: source, destinationID: destination, namespace: namespace, payload: payload)
    }
}

enum CastMessageError: Error, Equatable {
    /// The length header is over `CastMessageDecoder.maxBodySize`.
    case tooLarge(Int)
    /// The body is not a valid `CastMessage`.
    case malformed
    /// `payload_type` is BINARY; we only handle string (JSON) payloads.
    case binaryPayload
}

/// Splits a byte stream into messages: buffer chunks until a full 4-byte length plus body has arrived.
struct CastMessageDecoder {
    /// Real Cast messages are small JSON; this caps memory if the other side sends a bogus length.
    static let maxBodySize = 65536

    private var buffer: [UInt8] = []

    /// Adds a chunk and returns every message it completes.
    /// After a throw the stream is out of sync: close the connection instead of calling this again.
    mutating func append(_ chunk: Data) throws -> [CastMessage] {
        buffer += chunk
        var messages: [CastMessage] = []
        while buffer.count >= 4 {
            let length = buffer[0..<4].reduce(0) { $0 << 8 | Int($1) }
            guard length <= Self.maxBodySize else { throw CastMessageError.tooLarge(length) }
            guard buffer.count >= 4 + length else { break }
            messages.append(try CastMessage(body: buffer[4..<4 + length]))
            // ponytail: O(n) shift per message, fine while the buffer is capped at 64 KiB.
            buffer.removeFirst(4 + length)
        }
        return messages
    }
}

private struct ProtobufReader {
    var remaining: ArraySlice<UInt8>

    var isAtEnd: Bool { remaining.isEmpty }

    /// Reads a base-128 varint: 7 bits per byte, low bits first, top bit set means "more bytes follow".
    mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        for shift in stride(from: 0, to: 64, by: 7) {
            guard let byte = remaining.popFirst() else { throw CastMessageError.malformed }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
        }
        throw CastMessageError.malformed
    }

    mutating func take(_ count: UInt64) throws -> ArraySlice<UInt8> {
        guard count <= remaining.count else { throw CastMessageError.malformed }
        let bytes = remaining.prefix(Int(count))
        remaining = remaining.dropFirst(Int(count))
        return bytes
    }
}

private extension Array where Element == UInt8 {
    mutating func appendVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        append(UInt8(value))
    }

    mutating func appendVarintField(_ field: UInt64, _ value: UInt64) {
        appendVarint(field << 3 | 0)
        appendVarint(value)
    }

    mutating func appendStringField(_ field: UInt64, _ string: String) {
        let bytes = Array(string.utf8)
        appendVarint(field << 3 | 2)
        appendVarint(UInt64(bytes.count))
        append(contentsOf: bytes)
    }
}
