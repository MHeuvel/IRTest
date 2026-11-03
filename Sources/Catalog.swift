import Foundation

struct CodeEntry: Hashable {
    let code: Int
    let base: Int      // basistype (1...11) dat in het IR-commando meegaat
}

enum LayoutKind {
    case tv, disc, audio

    var pages: [PageKind] {
        switch self {
        case .tv: return [.remote, .numbers, .media]
        case .disc: return [.media, .remote, .numbers]
        case .audio: return [.remote, .numbers, .media]
        }
    }
}

struct DeviceType: Identifiable, Hashable {
    let id: Int        // apparaattype uit UnityRemote (1...39)
    let name: String
    let layout: LayoutKind
}

enum Catalog {
    static let types: [DeviceType] = {
        let raw: [(Int, String, LayoutKind)] = [
            (1, "Versterker", .audio), (2, "Kabel", .tv), (3, "Kabel + opname", .tv),
            (4, "CD-speler", .disc), (5, "Domotica", .audio), (6, "Laserdisc", .disc),
            (7, "Audio-accessoire", .audio), (8, "Video-accessoire", .tv), (9, "Receiver", .audio),
            (10, "Satelliet", .tv), (11, "Satelliet + opname", .tv), (12, "TV", .tv),
            (13, "TV + DVD", .tv), (14, "TV + video", .tv), (15, "TV + DVD + video", .tv),
            (16, "Videorecorder", .disc), (17, "DVD", .disc), (18, "DVD-recorder", .disc),
            (19, "Harddiskrecorder (PVR)", .tv), (20, "Beamer", .tv), (21, "Digitale mediaspeler", .tv),
            (22, "Digitale decoder", .tv), (23, "IPTV", .tv), (24, "Mediacenter", .tv),
            (25, "DVD/BluRay/HD", .disc), (26, "DVD + opname", .disc), (27, "DVD + video", .disc),
            (28, "Dockingstation", .audio), (29, "HD Radio", .audio), (30, "Home cinema set", .audio),
            (31, "Satellietradio", .audio), (32, "Digitale audiospeler", .audio),
            (33, "Dockingstation (audio)", .audio), (34, "Spelcomputer", .tv), (35, "IPTV + opname", .tv),
            (36, "HDTV", .tv), (37, "Draagbare tv", .tv), (38, "Projectie-tv", .tv),
            (39, "Video + opname", .disc)
        ]
        let all = raw.map { DeviceType(id: $0.0, name: $0.1, layout: $0.2) }
        let priority = [12, 25, 17, 10, 1, 9, 30, 2, 4]
        let first = priority.compactMap { id in all.first { $0.id == id } }
        let rest = all.filter { !priority.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return first + rest
    }()

    static func type(_ id: Int) -> DeviceType {
        types.first { $0.id == id } ?? types[0]
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
