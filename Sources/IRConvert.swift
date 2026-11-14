import Foundation

// Conversion of public IR code lists (Flipper-IRDB .ir files) to the signal format of the
// UnityRemote chip, and recognition of what a signal contains.
//
// Chip signal = 00 00 LL + body (LL = number of bytes in body). Two body forms:
//
//   Table form:   00 | carrier | nPairs | nPairs x (mark_hi mark_lo space_hi space_lo) | nSymbols | symbols
//     carrier = round(8 MHz / frequency); mark and space in units of 2 microseconds;
//     nSymbols = number of 4-bit symbols (high nibble first), each symbol is an index into the pair table.
//
//   Compact form: 00 | carrier | 80 | 32 or A2 | symbols
//     fixed table: 1 = leader (4.5 ms / 4.5 ms), 2 = bit 1 (560 / 1690 us), 3 = bit 0 (560 / 560 us), 0 = end.
//     A2 = one frame, 32 = two frames. Only Samsung32/NEC-like timing.

struct IRTiming {
    var frequency: Int      // Hz
    var durations: [Int]    // microseconds: mark, space, mark, space, ... (starts with a mark)
}

enum IRConvertError: LocalizedError {
    case unsupported(String)
    case invalid(String)
    case tooLong(Int)
    case tooManyPairs

    var errorDescription: String? {
        switch self {
        case .unsupported(let p): return "Protocol \(p) is not supported"
        case .invalid(let s): return s
        case .tooLong(let n): return "Signal too long (\(n) bytes, maximum 244)"
        case .tooManyPairs: return "Too many different pulse lengths"
        }
    }
}

// MARK: - Encoding to the chip format

enum ChipEncoder {
    static func pack(_ symbols: [Int]) -> [UInt8] {
        var s = symbols
        if s.count % 2 == 1 { s.append(0) }
        var out: [UInt8] = []
        var i = 0
        while i + 1 < s.count {
            out.append(UInt8((s[i] << 4) | s[i + 1]))
            i += 2
        }
        return out
    }

    private static func cluster(_ values: [Int], rel: Double, absTol: Int) -> [Int: Int] {
        var centers: [(first: Int, members: [Int])] = []
        for v in Set(values).sorted() {
            let limit = { (c: Int) -> Int in max(Int(rel * Double(c)), absTol) }
            if let i = centers.firstIndex(where: { abs(v - $0.first) <= limit($0.first) }) {
                centers[i].members.append(v)
            } else {
                centers.append((first: v, members: [v]))
            }
        }
        var map: [Int: Int] = [:]
        for c in centers {
            let mean = c.members.reduce(0, +) / c.members.count
            for m in c.members { map[m] = mean }
        }
        return map
    }

    private static func units(_ microseconds: Int) -> Int {
        min(65535, max(1, microseconds / 2))
    }

    // Table form. tolerance (microseconds) lets nearly equal lengths share one table entry
    // (used for raw signals; generated protocol timings use 0).
    static func encode(_ timing: IRTiming, tolerance: Int = 0) throws -> [UInt8] {
        var durs = timing.durations
        guard durs.count >= 2 else { throw IRConvertError.invalid("Signal is too short") }
        guard !durs.contains(where: { $0 <= 0 }) else { throw IRConvertError.invalid("Signal has a zero length pulse") }
        if durs.count % 2 == 1 {
            // Ends with a mark: add a trailing space like the chip's own recordings
            // (the longest space that is not a leader or gap)
            var best = 1000
            var k = 1
            var found = false
            while k < durs.count {
                if durs[k] <= 3000 && (!found || durs[k] > best) { best = durs[k]; found = true }
                k += 2
            }
            durs.append(best)
        }
        var items: [(Int, Int)] = []
        var i = 0
        while i + 1 < durs.count {
            items.append((durs[i], durs[i + 1]))
            i += 2
        }

        func build(_ rel: Double) -> (pairs: [(Int, Int)], symbols: [Int]) {
            let mm = cluster(items.map { $0.0 }, rel: rel, absTol: tolerance)
            let ss = cluster(items.map { $0.1 }, rel: rel, absTol: tolerance)
            var pairs: [(Int, Int)] = []
            var symbols: [Int] = []
            for it in items {
                let m = ((mm[it.0] ?? it.0) / 2) * 2
                let s = ((ss[it.1] ?? it.1) / 2) * 2
                if let idx = pairs.firstIndex(where: { $0.0 == m && $0.1 == s }) {
                    symbols.append(idx)
                } else {
                    pairs.append((m, s))
                    symbols.append(pairs.count - 1)
                }
            }
            return (pairs, symbols)
        }

        var built = build(0.0)
        var rel = 0.05
        while built.pairs.count > 16 && rel <= 0.6 {
            built = build(rel)
            rel += 0.05
        }
        guard built.pairs.count <= 16 else { throw IRConvertError.tooManyPairs }
        guard built.symbols.count <= 255 else { throw IRConvertError.tooLong(built.symbols.count) }

        let freq = Double(max(timing.frequency, 1))
        let carrier = max(1, min(255, Int((8_000_000.0 / freq).rounded())))
        var body: [UInt8] = [0, UInt8(carrier), UInt8(built.pairs.count)]
        for p in built.pairs {
            let m = units(p.0)
            let s = units(p.1)
            body += [UInt8(m >> 8), UInt8(m & 255), UInt8(s >> 8), UInt8(s & 255)]
        }
        body.append(UInt8(built.symbols.count))
        body += pack(built.symbols)
        guard body.count + 3 <= 244 else { throw IRConvertError.tooLong(body.count + 3) }
        return [0, 0, UInt8(body.count)] + body
    }

    // Compact form, one frame (verified against recordings made by the chip itself)
    static func samsungCompact(address: Int, command: Int, carrier: UInt8 = 212) -> [UInt8] {
        let a0 = address & 0xFF
        let a1 = ((address >> 8) & 0xFF) != 0 ? ((address >> 8) & 0xFF) : a0
        let c = command & 0xFF
        let bits = ProtocolTiming.lsb(a0, 8) + ProtocolTiming.lsb(a1, 8)
            + ProtocolTiming.lsb(c, 8) + ProtocolTiming.lsb((~c) & 0xFF, 8)
        let symbols = [1] + bits.map { $0 == 1 ? 2 : 3 } + [0]
        let body: [UInt8] = [0, carrier, 0x80, 0xA2] + pack(symbols)
        return [0, 0, UInt8(body.count)] + body
    }
}

// MARK: - Protocol timings

enum ProtocolTiming {
    static func lsb(_ v: Int, _ n: Int) -> [Int] { (0..<n).map { (v >> $0) & 1 } }
    static func msb(_ v: Int, _ n: Int) -> [Int] { (0..<n).reversed().map { (v >> $0) & 1 } }

    static func le(_ bytes: [UInt8]) -> Int {
        var v = 0
        for (i, b) in bytes.enumerated() where i < 4 { v |= Int(b) << (8 * i) }
        return v
    }

    private static func necLike(lead: [Int], bits: [Int]) -> [Int] {
        var d = lead
        for b in bits { d += [560, b == 1 ? 1690 : 560] }
        d.append(560)   // stop mark
        return d
    }

    // levels: (1 = mark, 0 = space, microseconds). Merges equal levels, drops a leading space.
    private static func durations(fromLevels levels: [(Int, Int)]) -> [Int] {
        var runs: [(Int, Int)] = []
        for l in levels {
            if let last = runs.last, last.0 == l.0 {
                runs[runs.count - 1].1 += l.1
            } else {
                runs.append(l)
            }
        }
        if let first = runs.first, first.0 == 0 { runs.removeFirst() }
        return runs.map { $0.1 }
    }

    static func timing(protocolName: String, address: [UInt8], command: [UInt8]) throws -> IRTiming {
        let a = le(address)
        let c = le(command)
        switch protocolName {
        case "NEC":
            let bits = lsb(a & 0xFF, 8) + lsb((~a) & 0xFF, 8) + lsb(c & 0xFF, 8) + lsb((~c) & 0xFF, 8)
            return IRTiming(frequency: 38000, durations: necLike(lead: [9000, 4500], bits: bits))
        case "NECext":
            // Address 16 bits. The command is either stored as 8 bits (complement is added)
            // or as two bytes that already contain the complement.
            let cmdBits: [Int]
            if command.count >= 2 && command[1] != 0 {
                cmdBits = lsb(Int(command[0]), 8) + lsb(Int(command[1]), 8)
            } else {
                cmdBits = lsb(c & 0xFF, 8) + lsb((~c) & 0xFF, 8)
            }
            let bits = lsb(a & 0xFFFF, 16) + cmdBits
            return IRTiming(frequency: 38000, durations: necLike(lead: [9000, 4500], bits: bits))
        case "NEC42":
            let a13 = a & 0x1FFF
            let bits = lsb(a13, 13) + lsb((~a13) & 0x1FFF, 13) + lsb(c & 0xFF, 8) + lsb((~c) & 0xFF, 8)
            return IRTiming(frequency: 38000, durations: necLike(lead: [9000, 4500], bits: bits))
        case "NEC42ext":
            let bits = lsb(a & 0x3FFFFFF, 26) + lsb(c & 0xFFFF, 16)
            return IRTiming(frequency: 38000, durations: necLike(lead: [9000, 4500], bits: bits))
        case "Samsung32":
            let a0 = a & 0xFF
            let a1 = ((a >> 8) & 0xFF) != 0 ? ((a >> 8) & 0xFF) : a0
            let bits = lsb(a0, 8) + lsb(a1, 8) + lsb(c & 0xFF, 8) + lsb((~c) & 0xFF, 8)
            return IRTiming(frequency: 38000, durations: necLike(lead: [4500, 4500], bits: bits))
        case "SIRC", "SIRC15", "SIRC20":
            let addrBits = protocolName == "SIRC" ? 5 : (protocolName == "SIRC15" ? 8 : 13)
            let bits = lsb(c & 0x7F, 7) + lsb(a, addrBits)
            var frame: [Int] = [2400, 600]
            for b in bits { frame += [b == 1 ? 1200 : 600, 600] }
            let frameLength = frame.reduce(0, +)
            var d: [Int] = []
            for r in 0..<3 {            // Sony devices expect the frame at least 3 times, 45 ms apart
                var f = frame
                if r < 2 { f[f.count - 1] = max(600, 45000 - frameLength + 600) }
                d += f
            }
            return IRTiming(frequency: 40000, durations: d)
        case "RC5", "RC5X":
            let x = protocolName == "RC5X"
            let cmd = x ? (c & 0x7F) : (c & 0x3F)
            let s2 = x ? (((cmd >> 6) & 1) == 1 ? 0 : 1) : 1
            let bits = [1, s2, 0] + msb(a & 0x1F, 5) + msb(cmd & 0x3F, 6)
            var lv: [(Int, Int)] = []
            for b in bits { lv += b == 1 ? [(0, 889), (1, 889)] : [(1, 889), (0, 889)] }
            return IRTiming(frequency: 36000, durations: durations(fromLevels: lv))
        case "RC6":
            func bit(_ b: Int, _ n: Int = 1) -> [(Int, Int)] {
                b == 1 ? [(1, 444 * n), (0, 444 * n)] : [(0, 444 * n), (1, 444 * n)]
            }
            var lv: [(Int, Int)] = [(1, 2666), (0, 889)]
            lv += bit(1)                              // start bit
            for _ in 0..<3 { lv += bit(0) }           // mode 0
            lv += bit(0, 2)                           // trailer (toggle) bit, double length
            for b in msb(a & 0xFF, 8) { lv += bit(b) }
            for b in msb(c & 0xFF, 8) { lv += bit(b) }
            return IRTiming(frequency: 36000, durations: durations(fromLevels: lv))
        case "Kaseikyo":
            // Flipper packs the 48-bit frame as: address = id << 24 | vendor << 8 | genre1 << 4 | genre2,
            // command = 10 bits. Bytes: vendor lo, vendor hi, parity | genre1 << 4, genre2 | data lo << 4,
            // data hi | id << 6, xor of the previous three.
            let vendor = (a >> 8) & 0xFFFF
            let genre1 = (a >> 4) & 0xF
            let genre2 = a & 0xF
            let id = (a >> 24) & 0x3
            let data = c & 0x3FF
            let parity = ((vendor >> 12) ^ (vendor >> 8) ^ (vendor >> 4) ^ vendor) & 0xF
            let d2 = parity | (genre1 << 4)
            let d3 = genre2 | ((data & 0xF) << 4)
            let d4 = (data >> 4) | (id << 6)
            let frame: [Int] = [vendor & 0xFF, (vendor >> 8) & 0xFF, d2, d3, d4, d2 ^ d3 ^ d4]
            var d: [Int] = [3456, 1728]
            for byte in frame {
                for b in lsb(byte, 8) { d += [432, b == 1 ? 1296 : 432] }
            }
            d.append(432)
            return IRTiming(frequency: 37000, durations: d)
        case "RCA":
            // 4-bit address, 8-bit command, then both inverted; most significant bit first
            let addr = a & 0xF
            let cmd = c & 0xFF
            let bits = msb(addr, 4) + msb(cmd, 8) + msb((~addr) & 0xF, 4) + msb((~cmd) & 0xFF, 8)
            var d: [Int] = [4000, 4000]
            for b in bits { d += [500, b == 1 ? 2000 : 1000] }
            d.append(500)
            return IRTiming(frequency: 56000, durations: d)
        case "Pioneer":
            let bits = lsb(a & 0xFF, 8) + lsb((~a) & 0xFF, 8) + lsb(c & 0xFF, 8) + lsb((~c) & 0xFF, 8)
            var d: [Int] = [8500, 4225]
            for b in bits { d += [500, b == 1 ? 1500 : 500] }
            d.append(500)
            return IRTiming(frequency: 40000, durations: d)
        default:
            throw IRConvertError.unsupported(protocolName)
        }
    }
}

// MARK: - Flipper .ir files

struct FlipperKey: Identifiable {
    let id = UUID()
    var name: String
    var fields: [String: String] = [:]

    var isParsed: Bool { (fields["type"] ?? "").lowercased() == "parsed" }
    // A recording that is already converted to the chip signal (built-in database): hex in fields["hex"]
    var isChipSignal: Bool { fields["type"] == "chip" }
    var protocolName: String { fields["protocol"] ?? "" }

    var summary: String {
        if isChipSignal {
            return "recording · \((fields["hex"] ?? "").count / 2) bytes"
        }
        if isParsed {
            let a = (fields["address"] ?? "").trimmingCharacters(in: .whitespaces)
            let c = (fields["command"] ?? "").trimmingCharacters(in: .whitespaces)
            return "\(protocolName) · address \(a) · command \(c)"
        }
        let n = (fields["data"] ?? "").split(separator: " ").count
        return "raw · \(n) pulses · \(fields["frequency"] ?? "?") Hz"
    }
}

enum FlipperIR {
    static func parse(_ text: String) -> [FlipperKey] {
        var keys: [FlipperKey] = []
        var current: FlipperKey? = nil
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if key == "name" {
                if let c = current { keys.append(c) }
                current = FlipperKey(name: value)
            } else if current != nil {
                if key == "data", let old = current?.fields["data"] {
                    current?.fields["data"] = old + " " + value
                } else {
                    current?.fields[key] = value
                }
            }
        }
        if let c = current { keys.append(c) }
        return keys
    }

    private static func bytes(_ s: String?) -> [UInt8] {
        (s ?? "").split(separator: " ").compactMap { UInt8($0, radix: 16) }
    }

    static func convert(_ key: FlipperKey) throws -> [UInt8] {
        if key.isChipSignal {
            let hex = Array(key.fields["hex"] ?? "")
            var out: [UInt8] = []
            var i = 0
            while i + 1 < hex.count {
                guard let b = UInt8(String(hex[i]) + String(hex[i + 1]), radix: 16) else {
                    throw IRConvertError.invalid("Invalid recording")
                }
                out.append(b)
                i += 2
            }
            guard out.count >= 7, out[0] == 0, out[1] == 0, Int(out[2]) == out.count - 3 else {
                throw IRConvertError.invalid("Invalid recording")
            }
            return out
        }
        if key.isParsed {
            let address = bytes(key.fields["address"])
            let command = bytes(key.fields["command"])
            guard !address.isEmpty, !command.isEmpty else { throw IRConvertError.invalid("Address or command missing") }
            if key.protocolName == "Samsung32" {
                return ChipEncoder.samsungCompact(address: ProtocolTiming.le(address),
                                                  command: ProtocolTiming.le(command))
            }
            let t = try ProtocolTiming.timing(protocolName: key.protocolName, address: address, command: command)
            return try ChipEncoder.encode(t)
        }
        let freq = Int(key.fields["frequency"] ?? "") ?? 38000
        let data = (key.fields["data"] ?? "").split(separator: " ").compactMap { Int($0) }
        guard data.count >= 2 else { throw IRConvertError.invalid("No raw data") }
        return try ChipEncoder.encode(IRTiming(frequency: freq, durations: data), tolerance: 100)
    }
}

// MARK: - Recognizing what a signal contains

struct IRAnalysis {
    var text: String        // one line: what it is
    var good: Bool          // recognized and checksum OK
    var notes: [String]     // warnings
}

enum IRAnalyzer {
    private struct Decoded {
        var carrier: Int
        var elements: [(mark: Int, space: Int, end: Bool)]   // end: frame boundary after this element
    }

    private static func nibbles(_ b: [UInt8]) -> [Int] {
        var r: [Int] = []
        for x in b { r.append(Int(x >> 4)); r.append(Int(x & 15)) }
        return r
    }

    private static func decode(_ s: [UInt8]) -> Decoded? {
        guard s.count >= 7, s[0] == 0, s[1] == 0, Int(s[2]) == s.count - 3 else { return nil }
        let body = Array(s[3...])
        guard body.count >= 4 else { return nil }
        let carrier = Int(body[1])
        var elements: [(mark: Int, space: Int, end: Bool)] = []
        if body[2] == 0x80 {
            let table: [(Int, Int)] = [(0, 0), (4500, 4500), (560, 1690), (560, 560)]
            for sym in nibbles(Array(body[4...])) {
                if sym == 0 {
                    if !elements.isEmpty { elements[elements.count - 1].end = true }
                } else if sym < table.count {
                    elements.append((mark: table[sym].0, space: table[sym].1, end: false))
                }
            }
            return Decoded(carrier: carrier, elements: elements)
        }
        let n = Int(body[2])
        var p = 3
        guard n >= 1, n <= 16, body.count >= p + 4 * n + 1 else { return nil }
        var pairs: [(Int, Int)] = []
        for _ in 0..<n {
            let m = (Int(body[p]) << 8) | Int(body[p + 1])
            let sp = (Int(body[p + 2]) << 8) | Int(body[p + 3])
            pairs.append((m * 2, sp * 2))
            p += 4
        }
        let count = Int(body[p])
        p += 1
        var syms = nibbles(Array(body[p...]))
        if syms.count > count { syms = Array(syms.prefix(count)) }
        for sym in syms where sym < pairs.count {
            let pr = pairs[sym]
            elements.append((mark: pr.0, space: pr.1, end: pr.1 >= 20000))
        }
        return Decoded(carrier: carrier, elements: elements)
    }

    private static func hex2(_ v: Int) -> String { String(format: "%02X", v & 0xFF) }

    static func analyze(_ signal: [UInt8]) -> IRAnalysis {
        guard let d = decode(signal) else {
            return IRAnalysis(text: "Signal structure not recognized", good: false,
                              notes: ["Expected 00 00 LL followed by a body of LL bytes."])
        }
        // Split into frames
        var frames: [[(mark: Int, space: Int, end: Bool)]] = []
        var cur: [(mark: Int, space: Int, end: Bool)] = []
        for e in d.elements {
            cur.append(e)
            if e.end { frames.append(cur); cur = [] }
        }
        if !cur.isEmpty { frames.append(cur) }

        var notes: [String] = []
        let khz = d.carrier > 0 ? 8000.0 / Double(d.carrier) : 0
        let carrierText = String(format: "%.1f kHz", khz)

        // First frame that contains a leader
        var frameIndex: Int? = nil
        var leaderAt = 0
        for (fi, f) in frames.enumerated() {
            if let li = f.firstIndex(where: { $0.mark >= 2000 && $0.mark <= 10000 }) {
                frameIndex = fi
                leaderAt = li
                break
            }
        }
        guard let fi = frameIndex else {
            return IRAnalysis(text: "No frame found (\(d.elements.count) pulses, \(carrierText))", good: false,
                              notes: ["The recording contains no start pulse. It may be noise."])
        }
        let frame = frames[fi]
        let leader = frame[leaderAt]
        if leaderAt > 0 {
            notes.append("\(leaderAt) stray pulse(s) before the frame (usually harmless).")
        }
        var bits: [Int] = []
        var k = leaderAt + 1
        while k < frame.count {
            let e = frame[k]
            guard e.mark >= 300 && e.mark <= 1400 else { break }
            if e.space < 1100 { bits.append(0) } else if e.space <= 2400 { bits.append(1) } else { break }
            k += 1
        }
        let rest = frame.count - k
        if rest > 0 {
            notes.append("\(rest) unexpected pulse(s) after the data bits.")
        }
        let extraFrames = frames.count - 1
        var tail = " · \(carrierText)"
        if extraFrames > 0 { tail += " · \(frames.count) frames" }

        func byte(_ i: Int) -> Int {
            var v = 0
            for j in 0..<8 where i * 8 + j < bits.count { v |= bits[i * 8 + j] << j }
            return v
        }

        let lm = leader.mark
        let ls = leader.space
        if lm >= 3800 && lm <= 5200 && ls >= 3800 && ls <= 5200 {            // 4.5 / 4.5 ms
            if bits.count >= 32 {
                let b0 = byte(0), b1 = byte(1), b2 = byte(2), b3 = byte(3)
                if (b2 ^ b3) == 0xFF {
                    if b0 == b1 {
                        return IRAnalysis(text: "Samsung32 · address \(hex2(b0)) · command \(hex2(b2)) · check OK" + tail,
                                          good: true, notes: notes)
                    }
                    return IRAnalysis(text: "Samsung-type · address \(hex2(b1))\(hex2(b0)) · command \(hex2(b2)) · check OK" + tail,
                                      good: true, notes: notes)
                }
                notes.append("The command byte and its complement do not match: the recording is probably damaged.")
                return IRAnalysis(text: "Samsung-type frame, check failed" + tail, good: false, notes: notes)
            }
        } else if lm >= 8000 && lm <= 10000 && ls >= 3800 && ls <= 5200 {   // 9 / 4.5 ms
            if bits.count >= 32 {
                let b0 = byte(0), b1 = byte(1), b2 = byte(2), b3 = byte(3)
                if (b2 ^ b3) == 0xFF {
                    if (b0 ^ b1) == 0xFF {
                        return IRAnalysis(text: "NEC · address \(hex2(b0)) · command \(hex2(b2)) · check OK" + tail,
                                          good: true, notes: notes)
                    }
                    return IRAnalysis(text: "NEC extended · address \(hex2(b1))\(hex2(b0)) · command \(hex2(b2)) · check OK" + tail,
                                      good: true, notes: notes)
                }
                notes.append("The command byte and its complement do not match: the recording is probably damaged.")
                return IRAnalysis(text: "NEC-type frame, check failed" + tail, good: false, notes: notes)
            }
        } else if lm >= 2000 && lm <= 2800 && ls >= 400 && ls <= 800 {      // 2.4 / 0.6 ms
            // Sony: mark length 600 = 0, 1200 = 1
            var sb: [Int] = []
            var j = leaderAt + 1
            while j < frame.count {
                let e = frame[j]
                if e.mark >= 400 && e.mark <= 800 { sb.append(0) } else if e.mark >= 1000 && e.mark <= 1400 { sb.append(1) } else { break }
                j += 1
            }
            if sb.count == 12 || sb.count == 15 || sb.count == 20 {
                var cmd = 0
                for i in 0..<7 { cmd |= sb[i] << i }
                var addr = 0
                for i in 7..<sb.count { addr |= sb[i] << (i - 7) }
                return IRAnalysis(text: "Sony SIRC\(sb.count) · address \(String(format: "%02X", addr)) · command \(hex2(cmd))" + tail,
                                  good: true, notes: notes)
            }
        }
        notes.append("Start pulse \(lm)/\(ls) µs, \(bits.count) bits read.")
        return IRAnalysis(text: "Frame found, protocol not recognized" + tail, good: false, notes: notes)
    }
}
