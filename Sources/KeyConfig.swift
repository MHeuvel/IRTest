import SwiftUI

// Which buttons of a device are shown. A device starts with all standard buttons; the user can hide
// buttons (Edit device) and add extra buttons that the Gear4 knows but no standard page has.
// Everything is stored per device as key slots, so it stays valid when the chip is changed.

enum KeyGroup: String, CaseIterable, Identifiable {
    case volume, channel, arrows, digits, colors
    var id: String { rawValue }

    func title(_ layout: LayoutKind) -> String {
        switch self {
        case .volume: return "Volume (VOL + and -)"
        case .channel: return layout == .audio ? "Tune (+ and -)" : "Channel (CH + and -)"
        case .arrows: return "Arrow pad (arrows and OK)"
        case .digits: return "Number keys (0 to 9 and Enter)"
        case .colors: return "Color keys (red, green, yellow, blue)"
        }
    }

    var slots: [Int] {
        switch self {
        case .volume: return [6, 7]
        case .channel: return [4, 5]
        case .arrows: return [38, 39, 40, 41, 42]
        case .digits: return Array(9...19)
        case .colors: return [77, 78, 79, 80]
        }
    }

    // Groups that appear on the pages of a layout
    static func groups(for layout: LayoutKind) -> [KeyGroup] {
        switch layout {
        case .tv: return [.volume, .channel, .arrows, .digits, .colors]
        case .audio: return [.volume, .channel, .arrows, .digits]
        case .disc: return [.arrows, .digits, .colors]
        case .learned: return []
        }
    }
}

// Extra keys that the Gear4 knows (slot numbers from the original database)
extension K {
    static let setup = RemoteKey(slot: 34, title: "Setup")
    static let plus100 = RemoteKey(slot: 20, title: "+100")
    static let favorite = RemoteKey(slot: 45, title: "Favorite")
    static let wide = RemoteKey(slot: 47, title: "Wide")
    static let pipOn = RemoteKey(slot: 53, title: "PIP On")
    static let pipOff = RemoteKey(slot: 54, title: "PIP Off")
    static let pipSwap = RemoteKey(slot: 56, title: "PIP Swap")
    static let list = RemoteKey(slot: 72, title: "List")
    static let hdmi1 = RemoteKey(slot: 73, title: "HDMI 1")
    static let hdmi2 = RemoteKey(slot: 74, title: "HDMI 2")
    static let hdmi3 = RemoteKey(slot: 75, title: "HDMI 3")
    static let hdmi4 = RemoteKey(slot: 76, title: "HDMI 4")
}

extension LayoutKind {
    // The standard block of eight buttons
    var defaultBlock: [RemoteKey] {
        switch self {
        case .tv: return MainSpec.tv.row1 + MainSpec.tv.row3
        case .audio: return MainSpec.audio.row1 + MainSpec.audio.row3
        case .disc: return [K.menu, K.title, K.info, K.eject, K.back, K.exit, K.repeatKey, K.random]
        case .learned: return []
        }
    }

    // Keys that can be added to the block (off by default)
    var extraKeys: [RemoteKey] {
        switch self {
        case .tv:
            return [K.setup, K.favorite, K.wide, K.list, K.plus100, K.pipOn, K.pipOff, K.pipSwap,
                    K.hdmi1, K.hdmi2, K.hdmi3, K.hdmi4]
        case .audio:
            return [K.title, K.favorite, K.list, K.eject, K.random, K.repeatKey]
        case .disc:
            return [K.mute, K.volumeUp, K.volumeDown, K.input, K.sourceMenu, K.wide, K.list, K.favorite]
        case .learned:
            return []
        }
    }
}

struct KeyConfig: Equatable {
    var hidden: Set<Int> = []
    var extras: [Int] = []

    func shows(_ key: RemoteKey) -> Bool { !hidden.contains(key.slot) }

    func shows(_ group: KeyGroup) -> Bool { !group.slots.allSatisfy { hidden.contains($0) } }

    // The block of pill buttons: standard buttons that are not hidden, then the extra buttons that are on
    func blockKeys(layout: LayoutKind, home: Bool) -> [RemoteKey] {
        var keys = layout.defaultBlock.filter { shows($0) }
        for slot in extras {
            if let k = layout.extraKeys.first(where: { $0.slot == slot }), shows(k), !keys.contains(k) {
                keys.append(k)
            }
        }
        if home { keys = keys.map { $0 == K.input ? K.home : $0 } }
        return keys
    }

    // A page without any visible button leaves the page bar
    func isEmpty(_ page: PageKind, layout: LayoutKind) -> Bool {
        switch page {
        case .custom:
            return false
        case .remote:
            if !blockKeys(layout: layout, home: false).isEmpty { return false }
            if shows(.arrows) { return false }
            switch layout {
            case .tv: return !(shows(.volume) || shows(.channel) || shows(.colors))
            case .audio: return !(shows(.volume) || shows(.channel))
            case .disc, .learned: return true
            }
        case .numbers:
            if shows(.digits) { return false }
            let corner: RemoteKey = layout == .disc ? K.eject : (layout == .audio ? K.input : K.last)
            if shows(corner) { return false }
            return !((layout == .tv || layout == .disc) && shows(.colors))
        case .media:
            return MediaPage.keys(layout).allSatisfy { !shows($0) }
        }
    }
}

extension Device {
    var keyConfig: KeyConfig { KeyConfig(hidden: Set(hiddenKeys), extras: extraKeys) }
}
