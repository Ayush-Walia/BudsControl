import Foundation

/// OnePlus/OPPO "Melody" vendor protocol, as decoded from the HeyMelody app and verified live.
///
/// Outer frame:  AA | varint len | frameType | 00 | [fsn] | chunk
///   frameType 0 = single, 1 = first, 2 = middle, 3 = last; len covers everything after itself.
/// Inner packet: cmd u16 LE | seq u8 | payloadLen u16 LE | payload. Responses set bit 15 of cmd.
enum BudsCommand {
    static let getBattery: UInt16 = 0x0106
    static let getEarbudsStatus: UInt16 = 0x0109
    static let getNoiseReduction: UInt16 = 0x010C
    static let setNoiseReduction: UInt16 = 0x0404
    static let notification: UInt16 = 0x0204
    static let getNotificationCapability: UInt16 = 0x0200
    static let registerNotification: UInt16 = 0x0201
    static let registerNotificationMulti: UInt16 = 0x0205
    static let responseFlag: UInt16 = 0x8000
}

struct BudsPacket {
    var cmd: UInt16
    var seq: UInt8
    var payload: [UInt8]
}

struct BudsFrameCodec {
    private var buffer: [UInt8] = []
    private var multiFrame: [UInt8] = []

    static func encode(_ packet: BudsPacket) -> [UInt8] {
        let len = UInt16(packet.payload.count)
        var inner: [UInt8] = [UInt8(packet.cmd & 0xFF), UInt8(packet.cmd >> 8), packet.seq,
                              UInt8(len & 0xFF), UInt8(len >> 8)]
        inner += packet.payload
        var n = inner.count + 2
        var lenBytes: [UInt8] = []
        repeat {
            var b = UInt8(n & 0x7F)
            n >>= 7
            if n > 0 { b |= 0x80 }
            lenBytes.append(b)
        } while n > 0
        return [0xAA] + lenBytes + [0x00, 0x00] + inner
    }

    mutating func feed(_ bytes: [UInt8]) -> [BudsPacket] {
        buffer += bytes
        var packets: [BudsPacket] = []
        while let frame = nextFrame() {
            guard frame.count >= 2 else { continue }
            let type = frame[0]
            switch type {
            case 0:
                if let p = Self.parseInner(Array(frame[2...])) { packets.append(p) }
            case 1:
                multiFrame = frame.count > 3 ? Array(frame[3...]) : []
            case 2:
                if frame.count > 3 { multiFrame += frame[3...] }
            case 3:
                if frame.count > 3 { multiFrame += frame[3...] }
                if let p = Self.parseInner(multiFrame) { packets.append(p) }
                multiFrame = []
            default:
                break
            }
        }
        return packets
    }

    /// Pops one outer frame body (from frameType onwards) off the buffer.
    private mutating func nextFrame() -> [UInt8]? {
        while let first = buffer.first, first != 0xAA {
            buffer.removeFirst()
        }
        guard buffer.count >= 2 else { return nil }
        var length = 0
        var shift = 0
        var idx = 1
        while true {
            guard idx < buffer.count else { return nil }
            let b = buffer[idx]
            length |= Int(b & 0x7F) << shift
            shift += 7
            idx += 1
            if b & 0x80 == 0 { break }
            if shift > 21 {
                buffer.removeFirst()
                return nil
            }
        }
        guard buffer.count >= idx + length else { return nil }
        let body = Array(buffer[idx..<(idx + length)])
        buffer.removeFirst(idx + length)
        return body
    }

    private static func parseInner(_ data: [UInt8]) -> BudsPacket? {
        guard data.count >= 5 else { return nil }
        let cmd = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let len = Int(UInt16(data[3]) | (UInt16(data[4]) << 8))
        let end = min(data.count, 5 + len)
        return BudsPacket(cmd: cmd, seq: data[2], payload: Array(data[5..<end]))
    }
}

enum BudsPart: UInt8 {
    case left = 1, right = 2, chargingCase = 3
}

enum BudsParser {
    /// `[count, (part, value) * count]`, value bit 7 = charging, bits 0-6 = level.
    static func batteries(_ bytes: ArraySlice<UInt8>) -> [BudsPart: BatteryLevel]? {
        guard let count = bytes.first, bytes.count >= 1 + Int(count) * 2 else { return nil }
        var result: [BudsPart: BatteryLevel] = [:]
        var i = bytes.startIndex + 1
        for _ in 0..<count {
            if let part = BudsPart(rawValue: bytes[i]) {
                let v = bytes[i + 1]
                result[part] = BatteryLevel(level: Int(v & 0x7F), charging: v & 0x80 != 0)
            }
            i += 2
        }
        return result
    }

    /// `[count, (part, state) * count]`. Observed: 00 in closed case, 04 in open case, 05 out, 07 in ear.
    static func statuses(_ bytes: ArraySlice<UInt8>) -> [BudsPart: UInt8]? {
        guard let count = bytes.first, bytes.count >= 1 + Int(count) * 2 else { return nil }
        var result: [BudsPart: UInt8] = [:]
        var i = bytes.startIndex + 1
        for _ in 0..<count {
            if let part = BudsPart(rawValue: bytes[i]) { result[part] = bytes[i + 1] }
            i += 2
        }
        return result
    }

    /// `[action=1, type=1, bitmap LE...]` -> reported mode bitmap.
    static func modeBitmap(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard bytes.count >= 3, bytes[bytes.startIndex] == 1, bytes[bytes.startIndex + 1] == 1 else { return nil }
        var value = 0
        for (i, b) in bytes.dropFirst(2).prefix(4).enumerated() {
            value |= Int(b) << (8 * i)
        }
        return value
    }
}
