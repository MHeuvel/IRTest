import SwiftUI

enum PageKind: String, Identifiable {
    case remote, numbers, media, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .remote: return "Remote"
        case .numbers: return "Numbers"
        case .media: return "Media"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .remote: return "av.remote"
        case .numbers: return "circle.grid.3x3"
        case .media: return "playpause"
        case .custom: return "square.grid.2x2"
        }
    }
}

struct MainSpec {
    let row1: [RemoteKey]
    let left: CapsuleSpec
    let right: CapsuleSpec
    let row3: [RemoteKey]

    static let tv = MainSpec(
        row1: [K.input, K.tvMenu, K.guide, K.info],
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

struct PillGrid: View {
    let keys: [RemoteKey]
    let press: (RemoteKey) -> Void

    var body: some View {
        let rows = stride(from: 0, to: keys.count, by: 4).map { Array(keys[$0..<min($0 + 4, keys.count)]) }
        VStack(spacing: 14) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.self) { key in
                        PillKey(key: key, press: press)
                    }
                    ForEach(0..<(4 - rows[r].count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                    }
                }
            }
        }
    }
}

struct MainPage: View {
    let spec: MainSpec
    let width: CGFloat
    let block: [RemoteKey]
    let config: KeyConfig
    let press: (RemoteKey) -> Void
    var holdStart: (RemoteKey) -> Void = { _ in }
    var holdEnd: () -> Void = {}

    private func shown(_ c: CapsuleSpec) -> Bool { config.shows(c.up) || config.shows(c.down) }

    var body: some View {
        let cap = min(76, width * 0.2)
        let pad = min(230, width - 2 * cap - 16)
        let showLeft = shown(spec.left)
        let showRight = shown(spec.right)
        let showPad = config.shows(.arrows)
        VStack(spacing: 14) {
            if showLeft || showRight || showPad {
                HStack(spacing: 8) {
                    if showLeft {
                        CapsuleKeys(spec: spec.left, width: cap, height: pad, press: press, holdStart: holdStart, holdEnd: holdEnd)
                    } else {
                        Color.clear.frame(width: cap, height: pad)
                    }
                    if showPad {
                        DPad(size: pad, press: press)
                    } else {
                        Color.clear.frame(width: pad, height: pad)
                    }
                    if showRight {
                        CapsuleKeys(spec: spec.right, width: cap, height: pad, press: press, holdStart: holdStart, holdEnd: holdEnd)
                    } else {
                        Color.clear.frame(width: cap, height: pad)
                    }
                }
            }
            if !block.isEmpty {
                PillGrid(keys: block, press: press)
            }
        }
    }
}

struct DiscMenuPage: View {
    let width: CGFloat
    let block: [RemoteKey]
    let config: KeyConfig
    let press: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 14) {
            if config.shows(.arrows) {
                DPad(size: min(250, width - 20), press: press)
            }
            if !block.isEmpty {
                PillGrid(keys: block, press: press)
            }
        }
    }
}

struct NumbersPage: View {
    let layout: LayoutKind
    let config: KeyConfig
    let press: (RemoteKey) -> Void

    private var corner: (key: RemoteKey, icon: String) {
        switch layout {
        case .tv, .learned: return (key: K.last, icon: "arrow.uturn.backward")
        case .disc: return (key: K.eject, icon: "eject.fill")
        case .audio: return (key: K.input, icon: "rectangle.portrait.and.arrow.right")
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            if config.shows(.digits) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { col in
                            let key = K.digits[row * 3 + col]
                            CellKey(key: key, text: key.title, press: press)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                if config.shows(corner.key) {
                    CellKey(key: corner.key, icon: corner.icon, press: press)
                }
                if config.shows(.digits) {
                    CellKey(key: K.zero, text: "0", press: press)
                    if layout == .disc {
                        CellKey(key: K.plus10, text: "+10", press: press)
                    } else {
                        CellKey(key: K.enter, text: "Enter", press: press)
                    }
                }
            }
        }
    }
}

struct MediaPage: View {
    typealias Item = (key: RemoteKey, icon: String, tint: Color)

    let layout: LayoutKind
    let config: KeyConfig
    let press: (RemoteKey) -> Void

    private static func item(_ key: RemoteKey, _ icon: String, _ tint: Color = Color.white) -> Item {
        (key: key, icon: icon, tint: tint)
    }

    static func rows(_ layout: LayoutKind) -> [[Item]] {
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
        case .tv, .learned:
            return [transport, tvRow]
        case .disc, .audio:
            return [transport, skipRow, discRow]
        }
    }

    static func keys(_ layout: LayoutKind) -> [RemoteKey] {
        rows(layout).flatMap { row in row.map { $0.key } }
    }

    private var rows: [[Item]] {
        MediaPage.rows(layout)
            .map { row in row.filter { config.shows($0.key) } }
            .filter { !$0.isEmpty }
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
    var home: Bool = false
    var holdStart: (RemoteKey) -> Void = { _ in }
    var holdEnd: () -> Void = {}
    var config: KeyConfig = KeyConfig()

    var body: some View {
        VStack(spacing: 14) {
            switch page {
            case .remote: remotePage
            case .numbers: NumbersPage(layout: layout, config: config, press: press)
            case .media: MediaPage(layout: layout, config: config, press: press)
            case .custom: EmptyView()
            }
            if showsColors && config.shows(.colors) { ColorRow(press: press) }
        }
    }

    @ViewBuilder private var remotePage: some View {
        let block = config.blockKeys(layout: layout, home: home)
        switch layout {
        case .tv: MainPage(spec: .tv, width: width, block: block, config: config, press: press, holdStart: holdStart, holdEnd: holdEnd)
        case .audio: MainPage(spec: .audio, width: width, block: block, config: config, press: press, holdStart: holdStart, holdEnd: holdEnd)
        case .disc: DiscMenuPage(width: width, block: block, config: config, press: press)
        case .learned: EmptyView()
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
