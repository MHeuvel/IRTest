import SwiftUI

// Recognizes the structure of a learn response:
//   [N][id] + 00 00 LL + body(LL)     with N = number of bytes after N
// Returns the number of leading bytes to skip so that the rest starts with 00 00 LL.
enum LearnParse {
    static func guessSkip(_ d: [UInt8]) -> Int? {
        guard d.count >= 3 else { return nil }
        for k in 0...4 {
            guard d.count >= k + 3 else { break }
            if d[k] == 0, d[k + 1] == 0, Int(d[k + 2]) == d.count - k - 3 { return k }
        }
        return nil
    }

    static func lengthByteMatches(_ d: [UInt8]) -> Bool {
        !d.isEmpty && Int(d[0]) == d.count - 1
    }
}

struct LearnTarget: Identifiable {
    let id = UUID()
    let deviceID: UUID
    let existing: LearnedKey?
}

// MARK: - Custom page

struct CustomPage: View {
    let device: Device
    let learnMode: Bool
    let send: (LearnedKey) -> Void
    let onAdd: () -> Void
    let onEdit: (LearnedKey) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 12) {
            if learnMode {
                Text("Learn mode: tap + to add a key, or tap a key to edit it.")
                    .font(.system(size: 13))
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
            } else if device.learnedKeys.isEmpty {
                Text("No learned keys yet.\nTap the learn button at the top, then +.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(device.learnedKeys) { key in
                    tile(key)
                }
                if learnMode {
                    addTile
                }
            }
        }
    }

    private func tile(_ key: LearnedKey) -> some View {
        Button {
            if learnMode { onEdit(key) } else { send(key) }
        } label: {
            Text(key.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(learnMode ? Color.blue.opacity(0.7) : Theme.stroke, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressStyle())
    }

    private var addTile: some View {
        Button { onAdd() } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Learn screen (technical, with replay)

struct LearnKeyView: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var remote: RemoteController
    @Environment(\.dismiss) private var dismiss

    let deviceID: UUID
    let existing: LearnedKey?

    @State private var name = ""
    @State private var skip = 2
    @State private var skipTouched = false

    private var data: [UInt8] { remote.learnedData }
    private var guess: Int? { LearnParse.guessSkip(data) }
    private var signal: [UInt8] { Array(data.dropFirst(min(max(skip, 0), data.count))) }
    private var canSave: Bool {
        !data.isEmpty
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && signal.count >= 3 && signal.count <= 244
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Name") {
                    TextField("Key name", text: $name)
                }

                Section(footer: Text("Hold the original remote less than 1 cm from the UnityRemote's learn receiver (next to the flashing LED), tap Start learning, then press one key on the original remote once.")) {
                    if remote.isLearning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(remote.learnStatus)
                        }
                    } else {
                        Text(remote.learnStatus)
                    }
                    Button(data.isEmpty ? "Start learning" : "Relearn") {
                        skipTouched = false
                        remote.startLearning()
                    }
                    .disabled(remote.status != .connected || remote.isLearning)
                    if existing != nil && data.isEmpty {
                        Text("A signal is already saved for this key (\(existing?.signal.count ?? 0) bytes). Learn again to replace it.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                if !data.isEmpty {
                    Section("Raw data") {
                        Text("\(data.count) bytes")
                            .foregroundColor(.secondary)
                        Text(hex(data))
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Section(header: Text("Pattern check"),
                            footer: Text("The signal is expected to start with 00 00 LL, where LL is the number of bytes that follow.")) {
                        Label(LearnParse.lengthByteMatches(data)
                              ? "First byte matches the data length"
                              : "First byte does not match the data length",
                              systemImage: LearnParse.lengthByteMatches(data) ? "checkmark.circle" : "exclamationmark.triangle")
                        if let g = guess {
                            Label("Header 00 00 LL found after \(g) byte(s)", systemImage: "checkmark.circle")
                        } else {
                            Label("Pattern not recognized: 2 assumed, test with Replay", systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                        Stepper("Skip first bytes: \(skip)", value: $skip, in: 0...6) { _ in
                            skipTouched = true
                        }
                        Text("Signal sent: \(signal.count) bytes" + (signal.count > 244 ? " (too long)" : ""))
                            .foregroundColor(.secondary)
                        Button("Replay") {
                            remote.sendLearned(signal, label: name.isEmpty ? "test" : name)
                        }
                        .disabled(remote.status != .connected || signal.count < 3 || signal.count > 244)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New key" : "Edit key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        remote.cancelLearning()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveKey(device: deviceID, replacing: existing?.id, name: name,
                                      signal: signal, raw: data, skip: skip)
                        remote.resetLearn()
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                remote.resetLearn()
                if name.isEmpty { name = existing?.name ?? "" }
            }
            .onChange(of: remote.learnedData) { newData in
                if !skipTouched { skip = LearnParse.guessSkip(newData) ?? 2 }
            }
            .onDisappear { remote.cancelLearning() }
        }
        .preferredColorScheme(.dark)
    }
}
