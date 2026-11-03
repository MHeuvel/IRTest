import SwiftUI

enum PageKind: String, Identifiable {
    case remote, numbers, media
    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: return "Remote"
        case .numbers: return "Cijfers"
        case .media: return "Media"
        }
    }

    var icon: String {
        switch self {
        case .remote: return "av.remote"
        case .numbers: return "circle.grid.3x3"
        case .media: return "playpause"
        }
    }
}

struct MainSpec {
    let row1: [RemoteKey]
    let left: CapsuleSpec
    let right: CapsuleSpec
    let row3: [RemoteKey]

    static let tv = MainSpec(
        row1: [K.input, K.menu, K.guide, K.info],
        left: CapsuleSpec(label: "CH", up: K.channelUp, down: K.channelDown, upIcon: "chevron.up", downIcon: "chevron.down"),
        right: CapsuleSpec(label: "VOL", up: K.volumeUp, down: K.volumeDown, upIcon: "plus", downIcon: "minus"),
        row3: [K.back, K.exit, K.mute, K.last]
    )

    static let audio = MainSpec(
        row1: [K.input, K.sourceMenu, K.menu, K.info],
        left: CapsuleSpec(label: "VOL", up: K.volumeUp, down: K.volumeDown, upIcon: "plus", downIcon: "minus"),
        right: CapsuleSpec(label: "TUNE", up: K.channelUp, down: K.channelDown, upIcon: "plus", downIcon: "minus"),
        row3: [K.mute, K.exit, K.back, K.band]
    )
}

struct MainPage: View {
    let spec: MainSpec
    let width: CGFloat
    let press: (RemoteKey) -> Void

    var body: some View {
        let cap = min(76, width * 0.2)
        let pad = min(230, width - 2 * cap - 16)
        VStack(spacing: 14) {
            PillRow(keys: spec.row1, press: press)
            HStack(spacing: 8) {
                CapsuleKeys(spec: spec.left, width: cap, height: pad, press: press)
                DPad(size: pad, press: press)
                CapsuleKeys(spec: spec.right, width: cap, height: pad, press: press)
            }
            PillRow(keys: spec.row3, press: press)
        }
    }
}

struct DiscMenuPage: View {
    let width: CGFloat
    let press: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 14) {
            PillRow(keys: [K.menu, K.title, K.info, K.eject], press: press)
            DPad(size: min(250, width - 20), press: press)
            PillRow(keys: [K.back, K.exit, K.repeatKey, K.random], press: press)
        }
    }
}

struct NumbersPage: View {
    let layout: LayoutKind
    let press: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { col in
                        let key = K.digits[row * 3 + col]
                        CellKey(key: key, text: key.title, press: press)
                    }
                }
            }
            HStack(spacing: 10) {
                switch layout {
                case .tv:
                    CellKey(key: K.last, icon: "arrow.uturn.backward", press: press)
                case .disc:
                    CellKey(key: K.eject, icon: "eject.fill", press: press)
                case .audio:
                    CellKey(key: K.input, icon: "rectangle.portrait.and.arrow.right", press: press)
                }
                CellKey(key: K.zero, text: "0", press: press)
                switch layout {
                case .disc:
                    CellKey(key: K.plus10, text: "+10", press: press)
                default:
                    CellKey(key: K.enter, text: "Enter", press: press)
                }
            }
        }
    }
}

struct MediaPage: View {
    typealias Item = (key: RemoteKey, icon: String, tint: Color)

    let layout: LayoutKind
    let press: (RemoteKey) -> Void

    private func item(_ key: RemoteKey, _ icon: String, _ tint: Color = Color.white) -> Item {
        (key: key, icon: icon, tint: tint)
    }

    private var rows: [[Item]] {
        let transport: [Item] = [
            item(K.reverse, "backward.fill"),
            item(K.play, "play.fill"),
            item(K.fastForward, "forward.fill")
        ]
        let tvRow: [Item] = [
            item(K.pause, "pause.fill"),
            item(K.stop, "stop.fill"),
            item(K.record, "circle.fill", Color.red)
        ]
        let skipRow: [Item] = [
            item(K.previous, "backward.end.fill"),
            item(K.pause, "pause.fill"),
            item(K.next, "forward.end.fill")
        ]
        let discRow: [Item] = [
            item(K.eject, "eject.fill"),
            item(K.stop, "stop.fill"),
            item(K.record, "circle.fill", Color.red)
        ]
        switch layout {
        case .tv:
            return [transport, tvRow]
        case .disc, .audio:
            return [transport, skipRow, discRow]
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        CellKey(key: rows[r][c].key, icon: rows[r][c].icon, tint: rows[r][c].tint, press: press)
                    }
                }
            }
        }
    }
}

struct PageView: View {
    let layout: LayoutKind
    let page: PageKind
    let width: CGFloat
    let press: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 14) {
            switch page {
            case .remote: remotePage
            case .numbers: NumbersPage(layout: layout, press: press)
            case .media: MediaPage(layout: layout, press: press)
            }
            if showsColors { ColorRow(press: press) }
        }
    }

    @ViewBuilder private var remotePage: some View {
        switch layout {
        case .tv: MainPage(spec: .tv, width: width, press: press)
        case .audio: MainPage(spec: .audio, width: width, press: press)
        case .disc: DiscMenuPage(width: width, press: press)
        }
    }

    private var showsColors: Bool {
        switch (layout, page) {
        case (.tv, .remote), (.tv, .numbers), (.disc, .numbers): return true
        default: return false
        }
    }
}

struct PageBar: View {
    let pages: [PageKind]
    let active: PageKind
    let select: (PageKind) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(pages) { p in
                Button { select(p) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: p.icon).font(.system(size: 20))
                        Text(p.title).font(.system(size: 11))
                    }
                    .foregroundColor(p == active ? .white : .gray)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black))
    }
}
