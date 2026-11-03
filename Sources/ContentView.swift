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

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    HeaderCard(sheet: $sheet)
                    if let device = store.selected {
                        CodeBar(device: device, sheet: $sheet)
                        RemoteContent(device: device, page: $page, width: geo.size.width - 40)
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

    private var statusColor: Color {
        switch remote.status {
        case .noAccessory: return .gray
        case .accessoryFound: return .orange
        case .connected: return .green
        }
    }

    private var statusText: String {
        switch remote.status {
        case .noAccessory: return "Geen UnityRemote gevonden"
        case .accessoryFound: return "UnityRemote gevonden, niet verbonden"
        case .connected: return remote.gotReply ? "Verbonden" : "Verbinden…"
        }
    }

    private var subtitle: String {
        if let d = store.selected { return "\(d.brand) · \(d.typeInfo.name)" }
        return statusText
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
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
                    Button("Apparaten beheren") { sheet = .devices }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.selected?.name ?? "Geen apparaat")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                Spacer()
                Button { sheet = .devices } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 21))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
            LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 2)
                .opacity(0.7)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black))
    }
}

struct CodeBar: View {
    @EnvironmentObject var store: DeviceStore
    let device: Device
    @Binding var sheet: Sheet?

    private var text: String {
        guard let entry = device.currentCode else { return "Geen codes" }
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
            Text("Nog geen apparaat")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            Text("Tik op het tandwiel en kies \"Apparaat toevoegen\".")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button { sheet = .devices } label: {
                Text("Apparaten openen")
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

    private var layout: LayoutKind { device.typeInfo.layout }
    private var pages: [PageKind] { layout.pages }
    private var active: PageKind { pages.contains(page) ? page : pages[0] }

    private func press(_ key: RemoteKey) {
        remote.send(key, device: device)
    }

    private var pageBody: some View {
        PageView(layout: layout, page: active, width: width, press: press)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                PillKey(key: K.power, icon: "power", tint: .white, height: 38, press: press)
                PillKey(key: K.powerOn, icon: "power", tint: .green, height: 38, press: press)
                PillKey(key: K.powerOff, icon: "power", tint: .red, height: 38, press: press)
            }
            ViewThatFits(in: .vertical) {
                pageBody
                ScrollView { pageBody }
            }
            Spacer(minLength: 0)
            PageBar(pages: pages, active: active, select: { page = $0 })
        }
    }
}
