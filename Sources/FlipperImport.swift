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
    @State private var problem: String?

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
            fileName = url.lastPathComponent
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
        case .failure:
            problem = "Could not open the file."
        }
    }

    private func setAll(_ on: Bool) {
        for i in rows.indices where rows[i].signal != nil { rows[i].selected = on }
    }

    private func importSelected() {
        guard let device = store.devices.first(where: { $0.id == deviceID }) else { return }
        var added = 0
        var replaced = 0
        for row in rows where row.selected {
            guard let signal = row.signal else { continue }
            let name = row.key.name
            let existing = device.learnedKeys.first { $0.name.lowercased() == name.lowercased() }
            // Same layout as a learn response: [N][00] + signal, N = number of bytes after N
            let raw: [UInt8] = [UInt8(min(255, signal.count + 1)), 0] + signal
            store.saveKey(device: deviceID, replacing: existing?.id, name: name, signal: signal, raw: raw, skip: 2)
            if existing == nil { added += 1 } else { replaced += 1 }
        }
        remote.showNotice(replaced > 0 ? "\(added) added, \(replaced) replaced" : "\(added) key(s) imported")
        dismiss()
    }

    var body: some View {
        NavigationView {
            Form {
                Section(footer: Text("Choose a .ir file from Flipper-IRDB (for example from the Files app). Keys with a supported protocol are converted to the chip's format; use Test to check a key before importing.")) {
                    Button(rows.isEmpty ? "Choose Flipper .ir file" : "Choose another file") {
                        showPicker = true
                    }
                    if let p = problem {
                        Text(p).font(.footnote).foregroundColor(.orange)
                    }
                }

                if !rows.isEmpty {
                    Section(header: Text("\(fileName): \(convertible) of \(rows.count) keys can be converted")) {
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
