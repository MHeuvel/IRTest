import Foundation

// Protocol derived from UnityRemote 1.7.1.
//
// Frame:  AA 55 | LEN | CMD | payload... | CHK
//   LEN = number of bytes after LEN (CMD + payload + CHK)
//   CHK = bitwise NOT of the XOR of all preceding bytes (measured on the device)
//
// IR-passthrough (CMD 0x01), payload (10 bytes):
//   chipID[4] | 05 | 01 | V_hi | V_lo | keyNumber | trailer
//   V = ((deviceType - 1) << 12) | irCode
//   trailer = 80 for a single key (CMD 01), 00 for continuous (CMD 02), as the original app builds them.

enum Chip: String, CaseIterable, Identifiable {
    case axumII, gondarII, gondarI
    var id: String { rawValue }

    var title: String {
        switch self {
        case .axumII: return "Axum II"
        case .gondarII: return "Gondar II"
        case .gondarI: return "Gondar I"
        }
    }

    var idBytes: [UInt8] {
        switch self {
        case .axumII: return [0x55, 0x49, 0x42, 0x31]
        case .gondarI, .gondarII: return [0xBC, 0xAC, 0x0D, 0x00]
        }
    }

    // keyCode (1...80) -> key number on the wire; 0 = not supported
    func keyNumber(_ keyCode: Int) -> Int {
        guard (1...80).contains(keyCode) else { return 0 }
        switch self {
        case .axumII: return keyCode
        case .gondarII: return Chip.gondarIIKeys[keyCode - 1]
        case .gondarI: return Chip.gondarIKeys[keyCode - 1]
        }
    }

    static let gondarIKeys: [Int] = [16, 0, 0, 14, 15, 11, 12, 13, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 17, 0, 18, 19, 0, 20, 21, 24, 0, 0, 25, 22, 23, 0, 0, 26, 34, 32, 0, 27, 28, 30, 29, 31, 0, 0, 0, 33, 0, 0, 0, 0, 0, 0, 35, 36, 0, 37, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    static let gondarIIKeys: [Int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 0, 20, 21, 0, 22, 23, 24, 25, 26, 27, 0, 0, 28, 29, 30, 31, 32, 0, 33, 34, 35, 36, 37, 0, 0, 0, 38, 39, 0, 0, 0, 40, 0, 41, 42, 0, 43, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 44, 45, 46, 47]
}

enum Packet {
    static func build(cmd: UInt8, payload: [UInt8] = []) -> [UInt8] {
        var b: [UInt8] = [0xAA, 0x55, UInt8(payload.count + 2), cmd] + payload
        b.append(~b.reduce(0, ^))
        return b
    }

    // CMD 03: the key is transmitted for `milliseconds`, then the chip stops by itself (how the original app
    // sends a Power key with a duration). Payload: ms_hi ms_lo | chipID(4) | 05 | 01 | V_hi V_lo | key | 00
    static func irPassthroughStopAfter(chip: Chip, deviceType: Int, irCode: Int, keyCode: Int, milliseconds: Int) -> [UInt8]? {
        guard (1...11).contains(deviceType), (0...0x0FFF).contains(irCode), (1...65535).contains(milliseconds) else { return nil }
        let key = chip.keyNumber(keyCode)
        guard key != 0 else { return nil }
        let v = UInt16(((deviceType - 1) << 12) | irCode)
        let payload: [UInt8] = [UInt8(milliseconds >> 8), UInt8(milliseconds & 0xFF)]
            + chip.idBytes + [0x05, 0x01, UInt8(v >> 8), UInt8(v & 0xFF), UInt8(key), 0x00]
        return build(cmd: 0x03, payload: payload)
    }

    static func irPassthrough(chip: Chip, deviceType: Int, irCode: Int, keyCode: Int, cmd: UInt8 = 0x01) -> [UInt8]? {
        guard (1...11).contains(deviceType), (0...0x0FFF).contains(irCode) else { return nil }
        let key = chip.keyNumber(keyCode)
        guard key != 0 else { return nil }
        let v = UInt16(((deviceType - 1) << 12) | irCode)
        let trailer: UInt8 = cmd == 0x01 ? 0x80 : 0x00
        let payload: [UInt8] = chip.idBytes + [0x05, 0x01, UInt8(v >> 8), UInt8(v & 0xFF), UInt8(key), trailer]
        return build(cmd: cmd, payload: payload)
    }

    static func extract(from buffer: inout [UInt8]) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        while buffer.count >= 5 {
            guard let i = (0..<(buffer.count - 1)).first(where: { buffer[$0] == 0xAA && buffer[$0 + 1] == 0x55 }) else {
                buffer.removeAll(); break
            }
            if i > 0 { buffer.removeFirst(i) }
            guard buffer.count >= 3 else { break }
            let total = Int(buffer[2]) + 3
            guard buffer.count >= total else { break }
            frames.append(Array(buffer.prefix(total)))
            buffer.removeFirst(total)
        }
        return frames
    }

    static func checksumOK(_ f: [UInt8]) -> Bool {
        guard f.count >= 5 else { return false }
        return ~f.dropLast().reduce(0, ^) == f.last!
    }
}

extension Packet {
    // Translates known frames into readable text
    static func describe(_ f: [UInt8]) -> String {
        guard f.count >= 5 else { return "Frame too short" }
        let data = Array(f[4..<(f.count - 1)])
        switch f[3] {
        case 0xA0 where data.count >= 6:
            let fw = "\(data[0]).\(data[1]).\(data[2])"
            let hw = "\(data[3]).\(data[4]).\(data[5])"
            let rest = String(bytes: data.dropFirst(6), encoding: .ascii) ?? ""
            return "Version: firmware \(fw), hardware \(hw), rest \"\(rest)\""
        case 0x20 where data.count >= 2:
            let names: [Int: String] = [1: "invalid command", 2: "invalid parameter", 3: "invalid length",
                                        4: "invalid framing", 5: "checksum error", 6: "chip timeout",
                                        7: "invalid resources"]
            let st = Int(data[1])
            let text: String
            if st == 0 {
                text = "status 00 (OK?)"
            } else if data[0] == 0x01 && st == 6 {
                text = "status 06 (intermediate step, occurs on every IR key)"
            } else if data[0] == 0x01 && st == 7 {
                text = "status 07 (chip busy, key possibly not sent)"
            } else if data[0] == 0x01 && st == 8 {
                text = "status 08 (learning timed out: no usable signal received)"
            } else {
                text = "status \(String(format: "%02X", st)) = \(names[st] ?? "unknown")"
            }
            return "Response to CMD \(String(format: "%02X", data[0])): \(text)"
        default:
            return "Unknown frame type \(String(format: "%02X", f[3]))"
        }
    }
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}
