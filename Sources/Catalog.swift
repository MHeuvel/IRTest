import Foundation

struct CodeEntry: Hashable {
    let code: Int
    let base: Int      // base type (1...11) that goes into the IR command
}

enum LayoutKind {
    case tv, disc, audio, learned

    var pages: [PageKind] {
        switch self {
        case .tv: return [.remote, .numbers, .media, .custom]
        case .disc: return [.media, .remote, .numbers, .custom]
        case .audio: return [.remote, .numbers, .media, .custom]
        case .learned: return [.custom]
        }
    }
}

struct DeviceType: Identifiable, Hashable {
    let id: Int        // device type from UnityRemote (1...39)
    let name: String
    let layout: LayoutKind

    // Types that have been tested on a real device: learned remote and TV-like types
    var isBeta: Bool { ![0, 12, 36, 37, 38].contains(id) }
}

enum Catalog {
    static let types: [DeviceType] = {
        let raw: [(Int, String, LayoutKind)] = [
            (0, "Learned remote", .learned),
            (1, "Amplifier", .audio), (2, "Cable", .tv), (3, "Cable + recorder", .tv),
            (4, "CD player", .disc), (5, "Home automation", .audio), (6, "Laserdisc", .disc),
            (7, "Audio accessory", .audio), (8, "Video accessory", .tv), (9, "Receiver", .audio),
            (10, "Satellite", .tv), (11, "Satellite + recorder", .tv), (12, "TV", .tv),
            (13, "TV + DVD", .tv), (14, "TV + VCR", .tv), (15, "TV + DVD + VCR", .tv),
            (16, "VCR", .disc), (17, "DVD", .disc), (18, "DVD recorder", .disc),
            (19, "PVR / hard disk recorder", .tv), (20, "Projector", .tv), (21, "Digital media player", .tv),
            (22, "Digital terminal adapter", .tv), (23, "IPTV", .tv), (24, "Media center", .tv),
            (25, "DVD/Blu-ray/HD", .disc), (26, "DVD + recorder", .disc), (27, "DVD + VCR", .disc),
            (28, "Docking station", .audio), (29, "HD Radio", .audio), (30, "Home theater in a box", .audio),
            (31, "Satellite radio", .audio), (32, "Digital audio player", .audio),
            (33, "Docking station (audio)", .audio), (34, "Game console", .tv), (35, "IPTV + recorder", .tv),
            (36, "HDTV", .tv), (37, "Portable TV", .tv), (38, "Rear projection TV", .tv),
            (39, "VCR + recorder", .disc)
        ]
        let all = raw.map { DeviceType(id: $0.0, name: $0.1, layout: $0.2) }
        let priority = [0, 12, 25, 17, 10, 1, 9, 30, 2, 4]
        let first = priority.compactMap { id in all.first { $0.id == id } }
        let rest = all.filter { !priority.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return first + rest
    }()

    static func type(_ id: Int) -> DeviceType {
        types.first { $0.id == id } ?? DeviceType(id: 12, name: "TV", layout: .tv)
    }

    private static let table: [Int: [String: [CodeEntry]]] = {
        var result: [Int: [String: [CodeEntry]]] = [:]
        for line in CatalogData.text.split(separator: "\n") {
            let p = line.split(separator: "|", omittingEmptySubsequences: false)
            guard p.count == 4, let t = Int(p[0]), let base = Int(p[1]) else { continue }
            let brand = String(p[2])
            var list = result[t]?[brand] ?? []
            for c in p[3].split(separator: ",") {
                if let code = Int(c) {
                    let entry = CodeEntry(code: code, base: base)
                    if !list.contains(entry) { list.append(entry) }
                }
            }
            result[t, default: [:]][brand] = list
        }
        return result
    }()

    private static let brandLists: [Int: [String]] = table.mapValues { brands in
        brands.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func brands(for type: Int) -> [String] { brandLists[type] ?? [] }
    static func codes(type: Int, brand: String) -> [CodeEntry] { table[type]?[brand] ?? [] }
}
