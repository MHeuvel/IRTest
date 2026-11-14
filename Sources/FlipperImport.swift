import SwiftUI
import UniformTypeIdentifiers

// Import keys from a Flipper-IRDB .ir file into a device's Custom page.
struct FlipperImportView: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss

    let deviceID: UUID

    struct Row: Identifiable {
        let id = UUID()
        let key: FlipperKey
        let signal: [UInt8]?
        let error: String?
        var selected: Bool
    }

    @State private var rows: [Row] = []
    @State private var fileName = ""
    @State private var showPicker = false
    @State private var showBrowser = false
    @State private var problem: String?
    @State private var mapToStandard = true

    private var device: Device? { store.devices.first { $0.id == deviceID } }
    private var layout: LayoutKind { device?.layout ?? .learned }

    // Standard button per selected key (by row id), from the key names
    private var mapping: [UUID: Int] {
        guard mapToStandard, layout != .learned else { return [:] }
        let chosen = rows.filter { $0.selected && $0.signal != nil }
        let slots = FlipperSlots.assign(names: chosen.map { $0.key.name }, layout: layout)
        var result: [UUID: Int] = [:]
        for (i, row) in chosen.enumerated() {
            if let s = slots[i] { result[row.id] = s }
        }
        return result
    }

    // Make a standard button visible again when an imported key is put on it
    private func reveal(_ slot: Int) {
        let all = layout.defaultBlock + layout.extraKeys + MediaPage.keys(layout)
        if let k = all.first(where: { $0.slot == slot }) {
            let isExtra = layout.extraKeys.contains(where: { $0.slot == slot })
            store.setKey(deviceID, key: k, shown: true, extra: isExtra)
        }
    }

    private var convertible: Int { rows.filter { $0.signal != nil }.count }
    private var selectedCount: Int { rows.filter { $0.selected && $0.signal != nil }.count }

    private func load(_ result: Result<URL, Error>) {
        problem = nil
        switch result {
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                problem = "Could not read the file."
                return
            }
            let keys = FlipperIR.parse(text)
            if keys.isEmpty {
                problem = "No keys found. This does not look like a Flipper .ir file."
                rows = []
                return
            }
            setRows(name: url.lastPathComponent, keys: keys)
        case .failure:
            problem = "Could not open the file."
        }
    }

    private func setRows(name: String, keys: [FlipperKey]) {
        fileName = name
        rows = keys.map { (key: FlipperKey) -> Row in
            do {
                let signal = try FlipperIR.convert(key)
                return Row(key: key, signal: signal, error: nil, selected: true)
            } catch {
                return Row(key: key, signal: nil,
                           error: (error as? LocalizedError)?.errorDescription ?? "Conversion failed",
                           selected: false)
            }
        }
    }

    private func setAll(_ on: Bool) {
        for i in rows.indices where rows[i].signal != nil { rows[i].selected = on }
    }

    private func importSelected() {
        guard let device = store.devices.first(where: { $0.id == deviceID }) else { return }
        let chosen = rows.filter { $0.selected && $0.signal != nil }
        let slotFor = mapping
        var added = 0
        var replaced = 0
        var onStandard = 0
        for row in chosen {
            guard let signal = row.signal else { continue }
            let name = row.key.name
            if let slot = slotFor[row.id] {
                store.setSlotSignal(deviceID, slot: slot, name: name, signal: signal)
                reveal(slot)
                onStandard += 1
                continue
            }
            let existing = device.learnedKeys.first { $0.name.lowercased() == name.lowercased() }
            // Same layout as a learn response: [N][00] + signal, N = number of bytes after N
            let raw: [UInt8] = [UInt8(min(255, signal.count + 1)), 0] + signal
            store.saveKey(device: deviceID, replacing: existing?.id, name: name, signal: signal, raw: raw, skip: 2)
            if existing == nil { added += 1 } else { replaced += 1 }
        }
        var parts: [String] = []
        if onStandard > 0 { parts.append("\(onStandard) on standard buttons") }
        if added > 0 { parts.append("\(added) on Custom") }
        if replaced > 0 { parts.append("\(replaced) replaced") }
        remote.showNotice(parts.isEmpty ? "Nothing imported" : parts.joined(separator: ", "))
        dismiss()
    }

    var body: some View {
        NavigationView {
            Form {
                if device?.isLearnedRemote == true {
                    Section(footer: Text("Show the remote, numbers and media pages for this learned remote. Imported keys with matching names (Power, Vol_up, Menu, 1, ...) are put on those buttons; the others go to the Custom page.")) {
                        Picker("Standard pages", selection: Binding(get: { device?.flipperLayout ?? "" },
                                                                    set: { store.setFlipperLayout(deviceID, $0) })) {
                            Text("Custom page only").tag("")
                            Text("TV").tag("tv")
                            Text("Audio").tag("audio")
                            Text("Disc player").tag("disc")
                        }
                    }
                }
                Section(footer: Text("Search the built-in Flipper-IRDB (CC0), or choose a .ir file yourself. Keys are converted to the chip's format; use Test to check a key before importing. Recordings of unusual signals may not work on every device.")) {
                    NavigationLink(isActive: $showBrowser) {
                        FlipperBrowserView(onPick: { title, keys in
                            setRows(name: title, keys: keys)
                            showBrowser = false
                        })
                    } label: {
                        Text("Search Flipper database")
                    }
                    Button(rows.isEmpty ? "Choose Flipper .ir file" : "Choose another file") {
                        showPicker = true
                    }
                    if let p = problem {
                        Text(p).font(.footnote).foregroundColor(.orange)
                    }
                }

                if !rows.isEmpty && layout != .learned {
                    Section(footer: Text("Keys whose name matches a standard button replace what that button sent, so the standard pages also work for a Flipper remote. The others go to the Custom page.")) {
                        Toggle("Put matching keys on the standard buttons", isOn: $mapToStandard)
                    }
                }

                if !rows.isEmpty {
                    Section(header: Text("\(fileName): \(convertible) of \(rows.count) keys can be converted").textCase(nil)) {
                        HStack {
                            Button("Select all") { setAll(true) }
                                .buttonStyle(.borderless)
                            Spacer()
                            Button("Select none") { setAll(false) }
                                .buttonStyle(.borderless)
                        }
                        ForEach($rows) { $row in
                            HStack(spacing: 10) {
                                Button {
                                    if row.signal != nil { row.selected.toggle() }
                                } label: {
                                    Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundColor(row.signal == nil ? .gray : .blue)
                                }
                                .buttonStyle(.borderless)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.key.name)
                                    Text(row.error ?? row.key.summary)
                                        .font(.system(size: 12))
                                        .foregroundColor(row.error == nil ? .secondary : .orange)
                                    if let slot = mapping[row.id] {
                                        Text("Standard button: \(FlipperSlots.title(slot, layout: layout))")
                                            .font(.system(size: 12))
                                            .foregroundColor(.blue)
                                    }
                                }
                                Spacer()
                                if let signal = row.signal {
                                    Button("Test") {
                                        remote.sendLearned(signal, label: "Flipper \(row.key.name)")
                                    }
                                    .buttonStyle(.borderless)
                                    .disabled(remote.status != .connected)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Flipper file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import \(selectedCount)") { importSelected() }
                        .disabled(selectedCount == 0)
                }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.item],
                          onCompletion: load)
        }
        .overlay { NoticeView() }
        .animation(.easeInOut(duration: 0.15), value: remote.notice)
        .preferredColorScheme(.dark)
    }
}
