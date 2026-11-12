import SwiftUI

// Edit device: name, Hold Power, and which buttons are shown.
struct DeviceEditView: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss

    let deviceID: UUID
    @State private var name = ""
    @State private var loaded = false

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
                    if !d.isLearnedRemote {
                        powerSection(d)
                        powerButtonsSection(d)
                        blockSection(d)
                        extraSection(d)
                        groupSection(d)
                        mediaSection(d)
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
        }
        .overlay { NoticeView() }
        .animation(.easeInOut(duration: 0.15), value: remote.notice)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private func powerSection(_ d: Device) -> some View {
        Section(header: Text("Power key"),
                footer: Text("Some devices only react when the Power key is held. Off sends Power once, as usual. Otherwise the Power key is transmitted for this long.")) {
            Stepper(value: Binding(get: { d.powerHoldMs },
                                   set: { store.setPowerHold(d.id, ms: $0) }),
                    in: 0...5000, step: 250) {
                Text(d.powerHoldMs == 0 ? "Hold Power: off" : "Hold Power: \(d.powerHoldMs) ms")
            }
        }
    }

    private func powerButtonsSection(_ d: Device) -> some View {
        Section(header: Text("Power buttons")) {
            keyRow(d, K.power, extra: false)
            keyRow(d, K.powerOn, extra: false)
            keyRow(d, K.powerOff, extra: false)
        }
    }

    private func blockSection(_ d: Device) -> some View {
        Section(header: Text("Buttons block"),
                footer: Text("Use Test to see which buttons this device reacts to, and switch off the ones that do nothing. Hidden buttons disappear and the others move up. A page without buttons leaves the page bar.")) {
            ForEach(d.typeInfo.layout.defaultBlock, id: \.self) { key in
                keyRow(d, key, extra: false,
                       label: (d.currentCode?.base == 11 && key == K.input) ? "Home" : nil)
            }
        }
    }

    private func extraSection(_ d: Device) -> some View {
        Section(header: Text("More buttons"),
                footer: Text("Other keys the Gear4 knows. When switched on they are added to the buttons block.")) {
            ForEach(d.typeInfo.layout.extraKeys, id: \.self) { key in
                keyRow(d, key, extra: true)
            }
        }
    }

    private func groupSection(_ d: Device) -> some View {
        let layout = d.typeInfo.layout
        return Section(header: Text("Groups")) {
            ForEach(KeyGroup.groups(for: layout)) { group in
                Toggle(group.title(layout), isOn: Binding(
                    get: { d.keyConfig.shows(group) },
                    set: { store.setGroup(d.id, group: group, shown: $0) }
                ))
            }
        }
    }

    private func mediaSection(_ d: Device) -> some View {
        var seen = Set<RemoteKey>()
        var keys: [RemoteKey] = []
        for k in MediaPage.keys(d.typeInfo.layout) where !seen.contains(k) {
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

    private func keyRow(_ d: Device, _ key: RemoteKey, extra: Bool, label: String? = nil) -> some View {
        let cfg = d.keyConfig
        let on = extra ? (cfg.extras.contains(key.slot) && cfg.shows(key)) : cfg.shows(key)
        let onChip = remote.chip.keyNumber(key.slot) != 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label ?? key.title)
                if !onChip {
                    Text("Not available on \(remote.chip.title)")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Button("Test") {
                remote.send(key, device: d)
            }
            .buttonStyle(.borderless)
            .disabled(remote.status != .connected)
            Toggle("", isOn: Binding(
                get: { on },
                set: { store.setKey(d.id, key: key, shown: $0, extra: extra) }
            ))
            .labelsHidden()
        }
    }
}
