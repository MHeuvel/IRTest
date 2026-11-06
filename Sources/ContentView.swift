import SwiftUI

enum Sheet: String, Identifiable {
    case devices, codes
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var remote: RemoteController
    @EnvironmentObject var hardware: HardwareSettings
    @State private var sheet: Sheet?
    @State private var page: PageKind = .remote
    @State private var learnMode = false
    @State private var learnTarget: LearnTarget?
    @State private var editingKey: LearnedKey?
    @State private var renamingKey: LearnedKey?
    @State private var newKeyName = ""
    @State private var showReorder = false

    private func toggleLearn() {
        learnMode.toggle()
        if learnMode {
            withAnimation(.easeInOut(duration: 0.2)) { page = .custom }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    HeaderCard(sheet: $sheet, learnMode: learnMode, onToggleLearn: toggleLearn)
                    if remote.status == .noAccessory {
                        PairBanner()
                    }
                    if let device = store.selected {
                        if !device.isLearnedRemote {
                            CodeBar(device: device, sheet: $sheet)
                        }
                        RemoteContent(device: device,
                                      page: $page,
                                      width: geo.size.width - 40,
                                      learnMode: learnMode,
                                      onAddKey: { learnTarget = LearnTarget(deviceID: device.id, existing: nil) },
                                      onEditKey: { editingKey = $0 },
                                      onReorder: { showReorder = true })
                    } else {
                        EmptyState(sheet: $sheet)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
        }
        .overlay { NoticeView() }
        .animation(.easeInOut(duration: 0.15), value: remote.notice)
        .preferredColorScheme(.dark)
        .onChange(of: store.selectedID) { _ in learnMode = false }
        .sheet(item: $sheet) { s in
            switch s {
            case .devices:
                DevicesView()
                    .environmentObject(store)
                    .environmentObject(remote)
                    .environmentObject(hardware)
            case .codes:
                if let d = store.selected {
                    CodePickerView(device: d).environmentObject(store)
                }
            }
        }
        .sheet(isPresented: $showReorder) {
            if let d = store.selected {
                ReorderKeysView(deviceID: d.id).environmentObject(store)
            }
        }
        .sheet(item: $learnTarget) { t in
            LearnKeyView(deviceID: t.deviceID, existing: t.existing)
                .environmentObject(store)
                .environmentObject(remote)
        }
        .confirmationDialog(editingKey?.name ?? "",
                            isPresented: Binding(get: { editingKey != nil },
                                                 set: { if !$0 { editingKey = nil } }),
                            titleVisibility: .visible) {
            Button("Relearn") {
                if let k = editingKey, let d = store.selected {
                    learnTarget = LearnTarget(deviceID: d.id, existing: k)
                }
            }
            Button("Rename") {
                if let k = editingKey {
                    newKeyName = k.name
                    renamingKey = k
                }
            }
            Button("Delete", role: .destructive) {
                if let k = editingKey, let d = store.selected {
                    store.deleteKey(device: d.id, key: k.id)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename key",
               isPresented: Binding(get: { renamingKey != nil },
                                    set: { if !$0 { renamingKey = nil } })) {
            TextField("Name", text: $newKeyName)
            Button("Save") {
                if let k = renamingKey, let d = store.selected {
                    store.renameKey(device: d.id, key: k.id, to: newKeyName)
                }
                renamingKey = nil
            }
            Button("Cancel", role: .cancel) { renamingKey = nil }
        }
    }
}

struct NoticeView: View {
    @EnvironmentObject var remote: RemoteController

    var body: some View {
        if let text = remote.notice {
            Text(text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.black.opacity(0.88)))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

struct HeaderCard: View {
    @EnvironmentObject var store: DeviceStore
    @EnvironmentObject var remote: RemoteController
    @Binding var sheet: Sheet?
    let learnMode: Bool
    let onToggleLearn: () -> Void

    private var statusColor: Color {
        switch remote.status {
        case .noAccessory: return .gray
        case .accessoryFound: return .orange
        case .connected: return .green
        }
    }

    private var statusText: String {
        switch remote.status {
        case .noAccessory: return "No UnityRemote found"
        case .accessoryFound: return "UnityRemote found, not connected"
        case .connected: return remote.gotReply ? "Connected" : "Connecting…"
        }
    }

    private var subtitle: String {
        if let d = store.selected { return d.subtitle }
        return statusText
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Menu {
                ForEach(store.devices) { d in
                    Button {
                        store.selectedID = d.id
                    } label: {
                        if d.id == store.selectedID {
                            Label(d.name, systemImage: "checkmark")
                        } else {
                            Text(d.name)
                        }
                    }
                }
                Button("Manage devices") { sheet = .devices }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selected?.name ?? "No device")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            Spacer()
            if store.selected != nil {
                Button { onToggleLearn() } label: {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 19))
                        .foregroundColor(learnMode ? .white : .gray)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(learnMode ? Color.blue : Color.clear))
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
            }
            Button { sheet = .devices } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 21))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black))
    }
}

struct PairBanner: View {
    @EnvironmentObject var remote: RemoteController

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("No UnityRemote found")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Last used with another phone? Tap Pair / connect.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button { remote.pairOrConnect() } label: {
                Text("Pair / connect")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.blue))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
}

struct CodeBar: View {
    @EnvironmentObject var store: DeviceStore
    let device: Device
    @Binding var sheet: Sheet?

    private var text: String {
        guard let entry = device.currentCode else { return "No codes" }
        let index = min(max(device.codeIndex, 0), device.codes.count - 1) + 1
        return "Code \(entry.code)  ·  \(index)/\(device.codes.count)"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button { store.stepCode(device.id, by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            Button { sheet = .codes } label: {
                Text(text)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            Button { store.stepCode(device.id, by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
}

struct EmptyState: View {
    @Binding var sheet: Sheet?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tv")
                .font(.system(size: 44))
                .foregroundColor(.gray)
            Text("No device yet")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            Text("Tap the gear and choose \"Add device\".")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button { sheet = .devices } label: {
                Text("Open devices")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.blue))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct RemoteContent: View {
    @EnvironmentObject var remote: RemoteController
    let device: Device
    @Binding var page: PageKind
    let width: CGFloat
    let learnMode: Bool
    let onAddKey: () -> Void
    let onEditKey: (LearnedKey) -> Void
    let onReorder: () -> Void

    private var layout: LayoutKind { device.typeInfo.layout }
    private var pages: [PageKind] { layout.pages }
    private var active: PageKind { pages.contains(page) ? page : pages[0] }
    private var homeKey: Bool { device.currentCode?.base == 11 }

    private func press(_ key: RemoteKey) {
        remote.send(key, device: device)
    }

    private func select(_ p: PageKind) {
        withAnimation(.easeInOut(duration: 0.2)) { page = p }
    }

    private func move(_ delta: Int) {
        guard let i = pages.firstIndex(of: active) else { return }
        let n = i + delta
        guard pages.indices.contains(n) else { return }
        select(pages[n])
    }

    // Swipe left/right (on top of the page bar); mostly horizontal and at least 60 pt
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { v in
                let dx = v.translation.width
                let dy = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                move(dx < 0 ? 1 : -1)
            }
    }

    private var customPage: some View {
        CustomPage(device: device,
                   learnMode: learnMode,
                   send: { key in remote.sendLearned(key.signal, label: "\(key.name) · \(device.name)") },
                   onAdd: onAddKey,
                   onEdit: onEditKey,
                   onReorder: onReorder)
    }

    private var standardPage: some View {
        PageView(layout: layout, page: active, width: width, press: press, home: homeKey,
                 holdStart: { remote.startContinuous($0, device: device) },
                 holdEnd: { remote.stopContinuous() })
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                if !device.isLearnedRemote {
                    HStack(spacing: 10) {
                        PillKey(key: K.power, icon: "power", tint: .white, height: 38, press: press)
                        PillKey(key: K.powerOn, icon: "power", tint: .green, height: 38, press: press)
                        PillKey(key: K.powerOff, icon: "power", tint: .red, height: 38, press: press)
                    }
                }
                Group {
                    if active == .custom {
                        ScrollView { customPage }
                    } else {
                        ViewThatFits(in: .vertical) {
                            standardPage
                            ScrollView { standardPage }
                        }
                    }
                }
                .id(active)
                .transition(.opacity)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe)
            PageBar(pages: pages, active: active, select: select)
        }
    }
}
