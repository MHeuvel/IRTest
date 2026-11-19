import SwiftUI

// Edit device: name, Hold Power, and which buttons are shown.
struct DeviceEditView: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss

    let deviceID: UUID
    @State private var name = ""
    @State private var loaded = false
    @State private var renameKey: RemoteKey?
    @State private var renameText = ""

    private var device: Device? { store.devices.first { $0.id == deviceID } }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if loaded, !trimmed.isEmpty, trimmed != device?.name {
            store.rename(deviceID, to: trimmed)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                if let d = device {
                    Section(header: Text("Name")) {
                        TextField("Name", text: $name)
                    }
                    if d.isLearnedRemote {
                        flipperPagesSection(d)
                    }
                    if d.hasStandardPages {
                        powerSection(d)
                        groupSection(d)
                        numbersSection(d)
                        blockSection(d)
                        extraSection(d)
                        mediaSection(d)
                        flipperKeysSection(d)
                        Section {
                            Button("Back to standard buttons") {
                                store.resetKeys(d.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                if !loaded, let d = device {
                    name = d.name
                    loaded = true
                }
            }
            .onDisappear { save() }
            .alert("Name for this button", isPresented: Binding(get: { renameKey != nil },
                                                                 set: { if !$0 { renameKey = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let k = renameKey { store.setKeyName(deviceID, slot: k.slot, name: renameText) }
                    renameKey = nil
                }
                Button("Use name from code") {
                    if let k = renameKey { store.setKeyName(deviceID, slot: k.slot, name: nil) }
                    renameKey = nil
                }
                Button("Cancel", role: .cancel) { renameKey = nil }
            } message: {
                Text("Your own name for this button on this device. Empty or \"Use name from code\" shows the name the code gives it.")
            }
        }
        .overlay { NoticeView() }
        .animation(.easeInOut(duration: 0.15), value: remote.notice)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private func powerSection(_ d: Device) -> some View {
        Section(header: Text("Power options"),
                footer: Text(d.isLearnedRemote ? "" : "Hold power: some devices only react when the Power key is held. Off sends Power once, as usual. Otherwise the Power key is transmitted for this long.")) {
            shownToggle(d, K.power, "Power")
            shownToggle(d, K.powerOn, "Power On")
            shownToggle(d, K.powerOff, "Power Off")
            if !d.isLearnedRemote {
                Stepper(value: Binding(get: { d.powerHoldMs },
                                       set: { store.setPowerHold(d.id, ms: $0) }),
                        in: 0...5000, step: 250) {
                    Text(d.powerHoldMs == 0 ? "Hold power: off" : "Hold power: \(d.powerHoldMs) ms")
                }
            }
        }
    }

    private func shownToggle(_ d: Device, _ key: RemoteKey, _ title: String) -> some View {
        Toggle(title, isOn: Binding(
            get: { d.keyConfig.shows(key) },
            set: { store.setKey(d.id, key: key, shown: $0, extra: false) }
        ))
    }

    private func numbersSection(_ d: Device) -> some View {
        Section(header: Text("Number keys")) {
            Toggle("Show page", isOn: Binding(
                get: { d.keyConfig.shows(.digits) },
                set: { store.setGroup(d.id, group: .digits, shown: $0) }
            ))
        }
    }

    private func blockSection(_ d: Device) -> some View {
        Section(header: Text("Buttons block"),
                footer: Text("The name shown is the name this code gives the key in the original database, or your own name (pencil). Use Test to see what a button does, and switch off the ones that do nothing. Hidden buttons disappear and the others move up. A page without buttons leaves the page bar.")) {
            ForEach(d.layout.defaultBlock, id: \.self) { key in
                keyRow(d, key, extra: false,
                       label: (d.currentCode?.base == 11 && key == K.input) ? "Home" : nil)
            }
        }
    }

    private func extraSection(_ d: Device) -> some View {
        Section(header: Text("More buttons"),
                footer: Text("Other keys the Gear4 knows. When switched on they are added to the buttons block.")) {
            ForEach(d.layout.extraKeys, id: \.self) { key in
                keyRow(d, key, extra: true)
            }
        }
    }

    private func groupSection(_ d: Device) -> some View {
        let layout = d.layout
        return Section(header: Text("Groups")) {
            ForEach(KeyGroup.groups(for: layout)) { group in
                Toggle(isOn: Binding(
                    get: { d.keyConfig.shows(group) },
                    set: { store.setGroup(d.id, group: group, shown: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title(layout))
                        Text(group.subtitle(layout))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func mediaSection(_ d: Device) -> some View {
        var seen = Set<RemoteKey>()
        var keys: [RemoteKey] = []
        for k in MediaPage.keys(d.layout) where !seen.contains(k) {
            seen.insert(k)
            keys.append(k)
        }
        return Section(header: Text("Media page")) {
            ForEach(keys, id: \.self) { key in
                keyRow(d, key, extra: false)
            }
        }
    }

    // MARK: - One key: name, whether the chip has it, Test and a switch

    private func flipperPagesSection(_ d: Device) -> some View {
        Section(header: Text("Standard pages"),
                footer: Text("Show the remote, numbers and media pages for this learned remote. Keys you import from Flipper with matching names are put on these buttons.")) {
            Picker("Pages", selection: Binding(get: { d.flipperLayout ?? "" },
                                               set: { store.setFlipperLayout(d.id, $0) })) {
                Text("Custom page only").tag("")
                Text("TV").tag("tv")
                Text("Audio").tag("audio")
                Text("Disc player").tag("disc")
            }
        }
    }

    @ViewBuilder private func flipperKeysSection(_ d: Device) -> some View {
        if !d.slotSignals.isEmpty {
            Section(header: Text("Flipper keys"),
                    footer: Text("\(d.slotSignals.count) standard buttons send an imported signal instead of the chip's own key. Touch and hold a button's row to remove just that one.")) {
                Button("Remove all Flipper keys", role: .destructive) {
                    store.clearSlotSignals(d.id)
                }
            }
        }
    }

    // MARK: - One key: name, whether the chip has it, Test and a switch

    private func keyRow(_ d: Device, _ key: RemoteKey, extra: Bool, label: String? = nil) -> some View {
        let cfg = d.keyConfig
        let on = extra ? (cfg.extras.contains(key.slot) && cfg.shows(key)) : cfg.shows(key)
        let own = d.slotSignals[String(key.slot)]
        let hasCode = d.currentCode != nil
        let onChip = remote.chip.keyNumber(key.slot) != 0
        let standard = label ?? key.title
        let custom = d.customName(key.slot)
        let db = d.databaseName(key, chip: remote.chip)
        let hasList = d.codeNames(chip: remote.chip) != nil
        var notes: [String] = []
        if let own = own {
            notes.append("Flipper key: \(own.name)")
        }
        if custom != nil {
            if let db = db { notes.append("Code: \(db)") }
        } else if own == nil, db == nil, hasList, onChip {
            notes.append("This code gives it no name")
        }
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(custom ?? (own == nil ? db : nil) ?? standard)
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                if own == nil && (hasCode ? !onChip : true) {
                    Text(hasCode ? "Not available" : "No signal assigned")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Button {
                renameText = custom ?? ""
                renameKey = key
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            Button {
                remote.send(key, device: d)
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 17))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(remote.status != .connected)
            .accessibilityLabel("Test")
            Toggle("", isOn: Binding(
                get: { on },
                set: { store.setKey(d.id, key: key, shown: $0, extra: extra) }
            ))
            .labelsHidden()
        }
        .contextMenu {
            if own != nil {
                Button(role: .destructive) {
                    store.clearSlotSignal(d.id, slot: key.slot)
                } label: {
                    Label("Remove Flipper key", systemImage: "trash")
                }
            }
        }
    }
}
