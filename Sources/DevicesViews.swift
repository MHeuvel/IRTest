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
                Section("Devices") {
                    if store.devices.isEmpty {
                        Text("No devices yet").foregroundColor(.secondary)
                    }
                    ForEach(store.devices) { d in
                        Button {
                            store.selectedID = d.id
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).foregroundColor(.white)
                                    Text(d.subtitle)
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
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                renameTarget = d
                                newName = d.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                    Button { showAdd = true } label: {
                        Label("Add device", systemImage: "plus.circle.fill")
                    }
                }
                Section("Settings") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Hardware, connection and log", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddDeviceView(onFinished: {
                    showAdd = false
                    dismiss()
                })
                .environmentObject(store)
            }
            .alert("Rename device",
                   isPresented: Binding(get: { renameTarget != nil },
                                        set: { if !$0 { renameTarget = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") {
                    if let t = renameTarget { store.rename(t.id, to: newName) }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Add device: type, brand, name

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
            if t.id == 0 {
                NavigationLink {
                    NameDeviceView(type: t, brand: "Custom", onFinished: onFinished)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name)
                        Text("No code: learn every key yourself")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                NavigationLink {
                    BrandListView(type: t, onFinished: onFinished)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name)
                        Text("\(Catalog.brands(for: t.id).count) brands")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Device type")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onFinished() }
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

    private var defaultName: String {
        type.id == 0 ? "Learned remote" : "\(brand) \(type.name)"
    }

    private var summary: String {
        type.id == 0
            ? "Learned remote · learn every key yourself"
            : "\(brand) · \(type.name) · \(Catalog.codes(type: type.id, brand: brand).count) codes"
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $name)
            }
            Section {
                Text(summary)
                    .foregroundColor(.secondary)
            }
            Section {
                Button("Add") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let finalName = trimmed.isEmpty ? defaultName : trimmed
                    store.add(Device(name: finalName, type: type.id, brand: brand))
                    onFinished()
                }
            }
        }
        .navigationTitle("Name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if name.isEmpty { name = defaultName }
        }
    }
}

// MARK: - Choose code

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
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Settings and log

struct SettingsView: View {
    @EnvironmentObject var remote: RemoteController
    @EnvironmentObject var hardware: HardwareSettings

    private var chipBinding: Binding<Chip> {
        Binding(get: { hardware.chip(for: remote.accessoryKey) },
                set: { hardware.setChip($0, for: remote.accessoryKey) })
    }

    private var statusText: String {
        switch remote.status {
        case .noAccessory: return "No unit"
        case .accessoryFound: return "Found, not connected"
        case .connected: return "Connected"
        }
    }

    var body: some View {
        Form {
            Section(header: Text("UnityRemote unit"),
                    footer: Text("The chip type belongs to the unit and is remembered per unit. Gondar II is the only chip tested so far.")) {
                if remote.accessoryName.isEmpty {
                    Text("No unit found").foregroundColor(.secondary)
                } else {
                    LabeledContent("Name", value: remote.accessoryName)
                    LabeledContent("Version", value: remote.accessoryInfo)
                }
                Picker("Chip", selection: chipBinding) {
                    ForEach(Chip.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Connection") {
                LabeledContent("Status", value: statusText)
                Button("Reconnect") { remote.reconnect() }
                Button("Pair / connect UnityRemote") { remote.pairOrConnect() }
            }
            Section("Log") {
                NavigationLink {
                    LogView()
                } label: {
                    Text("View log")
                }
            }
            Section("About") {
                Text("UnityIRedux 0.6")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Settings")
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
                Button("Clear") { remote.log.removeAll() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Copy") { UIPasteboard.general.string = remote.log.joined(separator: "\n") }
            }
        }
    }
}
