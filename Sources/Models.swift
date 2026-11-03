import SwiftUI

struct Device: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: Int
    var brand: String
    var codeIndex: Int = 0

    var codes: [CodeEntry] { Catalog.codes(type: type, brand: brand) }
    var typeInfo: DeviceType { Catalog.type(type) }

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
}

// Chiptype per UnityRemote-apparaat (op serienummer of naam)
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
