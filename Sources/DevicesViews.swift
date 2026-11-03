import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var renameTarget: Device?
    @State private var newName = ""

    var body: some View {
        NavigationView {
            List {
                Section("Apparaten") {
                    if store.devices.isEmpty {
                        Text("Nog geen apparaten").foregroundColor(.secondary)
                    }
                    ForEach(store.devices) { d in
                        Button {
                            store.selectedID = d.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).foregroundColor(.white)
                                    Text("\(d.brand) · \(d.typeInfo.name)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if d.id == store.selectedID {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.remove(d.id)
                            } label: {
                                Label("Verwijder", systemImage: "trash")
                            }
                            Button {
                                renameTarget = d
                                newName = d.name
                            } label: {
                                Label("Naam", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    Button { showAdd = true } label: {
                        Label("Apparaat toevoegen", systemImage: "plus.circle.fill")
                    }
                }
                Section("Instellingen") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Hardware, verbinding en log", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Apparaten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddDeviceView(onFinished: {
                    showAdd = false
                    dismiss()
                })
                .environmentObject(store)
            }
            .alert("Naam wijzigen",
                   isPresented: Binding(get: { renameTarget != nil },
                                        set: { if !$0 { renameTarget = nil } })) {
                TextField("Naam", text: $newName)
                Button("Bewaar") {
                    if let t = renameTarget { store.rename(t.id, to: newName) }
                    renameTarget = nil
                }
                Button("Annuleer", role: .cancel) { renameTarget = nil }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Apparaat toevoegen: type, merk, naam

struct AddDeviceView: View {
    let onFinished: () -> Void

    var body: some View {
        NavigationView {
            TypeListView(onFinished: onFinished)
        }
        .preferredColorScheme(.dark)
    }
}

struct TypeListView: View {
    let onFinished: () -> Void
    @State private var search = ""

    private var types: [DeviceType] {
        Catalog.types.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(types) { t in
            NavigationLink {
                BrandListView(type: t, onFinished: onFinished)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.name)
                    Text("\(Catalog.brands(for: t.id).count) merken")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Type apparaat")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuleer") { onFinished() }
            }
        }
    }
}

struct BrandListView: View {
    let type: DeviceType
    let onFinished: () -> Void
    @State private var search = ""

    private var brands: [String] {
        let all = Catalog.brands(for: type.id)
        return search.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(brands, id: \.self) { brand in
            NavigationLink {
                NameDeviceView(type: type, brand: brand, onFinished: onFinished)
            } label: {
                HStack {
                    Text(brand)
                    Spacer()
                    Text("\(Catalog.codes(type: type.id, brand: brand).count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(type.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
    }
}

struct NameDeviceView: View {
    @EnvironmentObject var store: DeviceStore
    let type: DeviceType
    let brand: String
    let onFinished: () -> Void
    @State private var name = ""

    var body: some View {
        Form {
            Section("Naam") {
                TextField("Naam", text: $name)
            }
            Section {
                Text("\(brand) · \(type.name) · \(Catalog.codes(type: type.id, brand: brand).count) codes")
                    .foregroundColor(.secondary)
            }
            Section {
                Button("Toevoegen") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let finalName = trimmed.isEmpty ? "\(brand) \(type.name)" : trimmed
                    store.add(Device(name: finalName, type: type.id, brand: brand))
                    onFinished()
                }
            }
        }
        .navigationTitle("Naam")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if name.isEmpty { name = "\(brand) \(type.name)" }
        }
    }
}

// MARK: - Code kiezen

struct CodePickerView: View {
    @EnvironmentObject var store: DeviceStore
    @Environment(\.dismiss) private var dismiss
    let device: Device

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(device.codes.enumerated()), id: \.offset) { index, entry in
                    Button {
                        store.setCode(device.id, index: index)
                        dismiss()
                    } label: {
                        HStack {
                            Text("\(entry.code)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.white)
                            Spacer()
                            if index == device.codeIndex {
                                Image(systemName: "checkmark").foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(device.brand) · code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Instellingen en log

struct SettingsView: View {
    @EnvironmentObject var remote: RemoteController
    @EnvironmentObject var hardware: HardwareSettings

    private var chipBinding: Binding<Chip> {
        Binding(get: { hardware.chip(for: remote.accessoryKey) },
                set: { hardware.setChip($0, for: remote.accessoryKey) })
    }

    private var statusText: String {
        switch remote.status {
        case .noAccessory: return "Geen apparaat"
        case .accessoryFound: return "Gevonden, niet verbonden"
        case .connected: return "Verbonden"
        }
    }

    var body: some View {
        Form {
            Section(header: Text("UnityRemote-apparaat"),
                    footer: Text("Het chiptype hoort bij het apparaat en wordt per apparaat onthouden. Gondar II is de enige geteste chip.")) {
                if remote.accessoryName.isEmpty {
                    Text("Geen apparaat gevonden").foregroundColor(.secondary)
                } else {
                    LabeledContent("Naam", value: remote.accessoryName)
                    LabeledContent("Versie", value: remote.accessoryInfo)
                }
                Picker("Chip", selection: chipBinding) {
                    ForEach(Chip.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Verbinding") {
                LabeledContent("Status", value: statusText)
                Button("Verbind opnieuw") { remote.reconnect() }
                Button("Bluetooth-kiezer") { remote.showPicker() }
            }
            Section("Log") {
                NavigationLink {
                    LogView()
                } label: {
                    Text("Log bekijken")
                }
            }
            Section("Over") {
                Text("UnityRemote testapp, versie 0.4")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Instellingen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LogView: View {
    @EnvironmentObject var remote: RemoteController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(remote.log.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
        }
        .navigationTitle("Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Wis") { remote.log.removeAll() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Kopieer") { UIPasteboard.general.string = remote.log.joined(separator: "\n") }
            }
        }
    }
}
