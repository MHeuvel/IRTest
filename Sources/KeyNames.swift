import SwiftUI

// Names that an IR code gives to the keys of the Gear4 (original database, KeyNames.txt), names the user
// gives to a button, and the environment value the buttons read to show them.
//
// KeyNames.txt: one line per code: "profile|base|code|chipKey=name;chipKey=name;..."
// profile 2 = Gondar II numbering, 1 = Axum II (app slot numbers), 0 = Gondar I numbering (assumed).

final class KeyNamesDB {
    static let shared = KeyNamesDB()

    private var index: [String: Substring] = [:]
    private var cache: [String: [Int: String]] = [:]
    private var text = ""
    private var loaded = false

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "KeyNames", withExtension: "txt"),
              let data = try? Data(contentsOf: url),
              let t = String(data: data, encoding: .utf8) else { return }
        text = t
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
            if p.count == 4 {
                index[String(p[0]) + "|" + String(p[1]) + "|" + String(p[2])] = p[3]
            }
        }
    }

    // Chip key number -> name; nil when the database has no list for this code
    func names(profile: Int, base: Int, code: Int) -> [Int: String]? {
        load()
        let key = "\(profile)|\(base)|\(code)"
        if let c = cache[key] { return c }
        guard let rest = index[key] else { return nil }
        var dict: [Int: String] = [:]
        for pair in rest.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if kv.count == 2, let k = Int(kv[0]) {
                let name = String(kv[1])
                if name != "-" { dict[k] = name }
            }
        }
        cache[key] = dict
        return dict
    }
}

extension Chip {
    // Which numbering of the key names belongs to this chip
    var keyNameProfile: Int {
        switch self {
        case .axumII: return 1
        case .gondarII: return 2
        case .gondarI: return 0
        }
    }
}

extension Device {
    func customName(_ slot: Int) -> String? {
        guard let n = keyNames[String(slot)]?.trimmingCharacters(in: .whitespaces), !n.isEmpty else { return nil }
        return n
    }

    // The key names of the current code; nil if the database has no list for it
    func codeNames(chip: Chip) -> [Int: String]? {
        guard let e = currentCode else { return nil }
        return KeyNamesDB.shared.names(profile: chip.keyNameProfile, base: e.base, code: e.code)
    }

    func databaseName(_ key: RemoteKey, chip: Chip) -> String? {
        guard let names = codeNames(chip: chip) else { return nil }
        let n = chip.keyNumber(key.slot)
        return n == 0 ? nil : names[n]
    }

    // Name on a button: the user's own name, else the name this code gives the key; nil = standard title or icon
    func shownName(_ key: RemoteKey, chip: Chip) -> String? {
        customName(key.slot) ?? databaseName(key, chip: chip)
    }
}

// Whether a name still means the same as the standard title (then the icon stays)
enum KeyWords {
    static func matches(_ name: String, title: String) -> Bool {
        let n = name.lowercased()
        let t = title.lowercased()
        let words: [String]
        switch t {
        case "reverse": words = ["rev", "rew", "backward"]
        case "forward": words = ["forward", "ff", "fast"]
        case "play": words = ["play"]
        case "pause": words = ["pause"]
        case "stop": words = ["stop"]
        case "record": words = ["rec"]
        case "next": words = ["next", "skip", "forward", "chapter", "track"]
        case "previous": words = ["prev", "skip", "back", "chapter", "track"]
        case "eject": words = ["eject", "open"]
        case "last": words = ["last", "prev", "recall"]
        case "input": words = ["input", "source", "aux", "function", "av"]
        default: words = [t]
        }
        return words.contains { n.contains($0) }
    }
}

struct KeyLabeler {
    var label: (RemoteKey) -> String? = { _ in nil }
}

private struct KeyLabelerKey: EnvironmentKey {
    static let defaultValue = KeyLabeler()
}

extension EnvironmentValues {
    var keyLabeler: KeyLabeler {
        get { self[KeyLabelerKey.self] }
        set { self[KeyLabelerKey.self] = newValue }
    }
}
