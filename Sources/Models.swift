import SwiftUI

// A learned key: the signal in the form that is sent to the chip (00 00 LL + body),
// plus the raw response and the skip value it was derived with (so it can be re-derived).
struct LearnedKey: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var signal: [UInt8]
    var raw: [UInt8]
    var skip: Int
}

struct Device: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: Int          // 0 = learned remote (no code), otherwise UnityRemote device type
    var brand: String
    var codeIndex: Int = 0
    var learnedKeys: [LearnedKey] = []

    init(name: String, type: Int, brand: String) {
        self.name = name
        self.type = type
        self.brand = brand
    }

    // Older saved data has no learnedKeys: decode it with a default
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(Int.self, forKey: .type)
        brand = try c.decode(String.self, forKey: .brand)
        codeIndex = try c.decodeIfPresent(Int.self, forKey: .codeIndex) ?? 0
        learnedKeys = try c.decodeIfPresent([LearnedKey].self, forKey: .learnedKeys) ?? []
    }

    var codes: [CodeEntry] { Catalog.codes(type: type, brand: brand) }
    var typeInfo: DeviceType { Catalog.type(type) }
    var isLearnedRemote: Bool { type == 0 }

    var subtitle: String {
        isLearnedRemote ? "Learned remote" : "\(brand) · \(typeInfo.name)"
    }

    var currentCode: CodeEntry? {
        let list = codes
        guard !list.isEmpty else { return nil }
        return list[min(max(codeIndex, 0), list.count - 1)]
    }
}

final class DeviceStore: ObservableObject {
    @Published var devices: [Device] {
        didSet { save() }
    }
    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedDevice.v4") }
    }

    init() {
        var loaded: [Device] = []
        if let data = UserDefaults.standard.data(forKey: "devices.v4"),
           let list = try? JSONDecoder().decode([Device].self, from: data) {
            loaded = list
        }
        devices = loaded
        var sel: UUID? = nil
        if let s = UserDefaults.standard.string(forKey: "selectedDevice.v4"),
           let id = UUID(uuidString: s), loaded.contains(where: { $0.id == id }) {
            sel = id
        }
        selectedID = sel ?? loaded.first?.id
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: "devices.v4")
        }
    }

    var selected: Device? { devices.first { $0.id == selectedID } }

    func add(_ device: Device) {
        devices.append(device)
        selectedID = device.id
    }

    func remove(_ id: UUID) {
        devices.removeAll { $0.id == id }
        if selectedID == id { selectedID = devices.first?.id }
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { devices[i].name = trimmed }
    }

    func setCode(_ id: UUID, index: Int) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        let count = devices[i].codes.count
        guard count > 0 else { return }
        devices[i].codeIndex = min(max(index, 0), count - 1)
    }

    func stepCode(_ id: UUID, by delta: Int) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        let count = devices[i].codes.count
        guard count > 0 else { return }
        devices[i].codeIndex = ((devices[i].codeIndex + delta) % count + count) % count
    }

    // MARK: Learned keys

    func saveKey(device deviceID: UUID, replacing keyID: UUID?, name: String,
                 signal: [UInt8], raw: [UInt8], skip: Int) {
        guard let i = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let kid = keyID, let j = devices[i].learnedKeys.firstIndex(where: { $0.id == kid }) {
            devices[i].learnedKeys[j].name = trimmed
            devices[i].learnedKeys[j].signal = signal
            devices[i].learnedKeys[j].raw = raw
            devices[i].learnedKeys[j].skip = skip
        } else {
            devices[i].learnedKeys.append(LearnedKey(name: trimmed, signal: signal, raw: raw, skip: skip))
        }
    }

    func renameKey(device deviceID: UUID, key keyID: UUID, to name: String) {
        guard let i = devices.firstIndex(where: { $0.id == deviceID }),
              let j = devices[i].learnedKeys.firstIndex(where: { $0.id == keyID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { devices[i].learnedKeys[j].name = trimmed }
    }

    func deleteKey(device deviceID: UUID, key keyID: UUID) {
        guard let i = devices.firstIndex(where: { $0.id == deviceID }) else { return }
        devices[i].learnedKeys.removeAll { $0.id == keyID }
    }
}

// Chip type per UnityRemote unit (by serial number or name)
final class HardwareSettings: ObservableObject {
    @Published private(set) var chips: [String: String]

    init() {
        chips = (UserDefaults.standard.dictionary(forKey: "chips.v4") as? [String: String]) ?? [:]
    }

    func chip(for key: String) -> Chip {
        Chip(rawValue: chips[key] ?? "") ?? .gondarII
    }

    func setChip(_ chip: Chip, for key: String) {
        chips[key] = chip.rawValue
        UserDefaults.standard.set(chips, forKey: "chips.v4")
    }
}
