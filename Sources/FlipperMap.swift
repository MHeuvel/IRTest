import Foundation

// Matches the names of Flipper keys (Power, Vol_up, Ch_next, Menu, 1, ...) to the standard buttons.
enum FlipperSlots {
    // Lowercase letters and digits only, except + and a closing - ("Vol -" gives "vol-")
    private static func norm(_ s: String) -> String {
        let chars = Array(s.lowercased())
        var out = ""
        for (i, ch) in chars.enumerated() {
            if ch.isLetter || ch.isNumber || ch == "+" || (ch == "-" && i == chars.count - 1) {
                out.append(ch)
            }
        }
        return out
    }

    private static let common: [String: Int] = [
        "power": 1, "pwr": 1, "poweronoff": 1, "onoff": 1, "powertoggle": 1, "standby": 1, "powerstandby": 1,
        "poweron": 2, "on": 2, "poweroff": 3, "off": 3,
        "volup": 6, "vol+": 6, "volumeup": 6, "volplus": 6, "vup": 6, "volumeplus": 6, "volumeincrease": 6,
        "voldown": 7, "voldn": 7, "vol-": 7, "volumedown": 7, "volminus": 7, "vdown": 7, "voldwn": 7,
        "volumeminus": 7, "volumedecrease": 7,
        "mute": 8, "muting": 8,
        "up": 38, "down": 39, "left": 40, "right": 41,
        "dpadup": 38, "dpaddown": 39, "dpadleft": 40, "dpadright": 41,
        "cursorup": 38, "cursordown": 39, "cursorleft": 40, "cursorright": 41,
        "arrowup": 38, "arrowdown": 39, "arrowleft": 40, "arrowright": 41,
        "navup": 38, "navdown": 39, "navleft": 40, "navright": 41,
        "menuup": 38, "menudown": 39, "menuleft": 40, "menuright": 41,
        "ok": 42, "select": 42, "center": 42, "centre": 42, "okselect": 42,
        "input": 22, "source": 22, "tvav": 22, "av": 22, "inputsource": 22, "sourceinput": 22, "avsource": 22,
        "tvvideo": 22, "inputselect": 22,
        "info": 46, "display": 46, "infodisplay": 46, "osd": 46,
        "back": 37, "return": 37, "goback": 37, "exit": 36, "close": 36, "cancel": 36,
        "play": 24, "playpause": 24, "stop": 25, "pause": 26,
        "rewind": 27, "rew": 27, "rev": 27, "reverse": 27, "fastrev": 27, "fastrewind": 27, "scanrev": 27, "frev": 27,
        "fastforward": 28, "fastfwd": 28, "ff": 28, "ffwd": 28, "forward": 28, "fwd": 28,
        "record": 29, "rec": 29,
        "eject": 51, "open": 51, "openclose": 51, "random": 52, "shuffle": 52,
        "red": 77, "green": 78, "yellow": 79, "blue": 80,
        "colorred": 77, "colorgreen": 78, "coloryellow": 79, "colorblue": 80,
        "favorite": 45, "fav": 45, "favourite": 45, "favlist": 45,
        "list": 72, "chlist": 72, "channellist": 72,
        "wide": 47, "aspect": 47, "psize": 47, "picturesize": 47, "screenformat": 47, "ratio": 47,
        "pip": 53, "pipon": 53, "pipoff": 54, "pipswap": 56,
        "hdmi1": 73, "hdmi2": 74, "hdmi3": 75, "hdmi4": 76,
        "band": 20, "+100": 20, "100": 20,
        "setup": 34, "settings": 34, "setupmenu": 34
    ]

    private static let channelUp: Set<String> = ["chup", "ch+", "channelup", "chnext", "chplus", "pgup", "pageup", "channelplus", "tuneup", "tune+"]
    private static let channelDown: Set<String> = ["chdown", "chdn", "ch-", "channeldown", "chprev", "chprevious", "chminus", "pgdn", "pagedown", "channelminus", "tunedown", "tune-"]
    private static let nextTrack: Set<String> = ["next", "nexttrack", "skipnext", "skipfwd", "nextchapter", "chapternext", "skip+"]
    private static let previousTrack: Set<String> = ["prev", "previous", "prevtrack", "previoustrack", "skipprev", "skipback", "previouschapter", "chapterprev", "skip-"]
    private static let lastChannel: Set<String> = ["last", "recall", "prech", "prevch", "lastch", "flashback", "previouschannel", "prevchannel", "lastchannel"]

    private static func lookup(_ n: String, layout: LayoutKind, hasOK: Bool) -> Int? {
        // digits: "0" to "9", also "num5", "digit5", "key5", "button5"
        var digitText = n
        for prefix in ["number", "digit", "num", "key", "button", "btn"] where digitText.hasPrefix(prefix) {
            digitText = String(digitText.dropFirst(prefix.count))
            break
        }
        if digitText.count == 1, let d = Int(digitText), n != "100" {
            return d == 0 ? 18 : 8 + d
        }
        if n == "enter" { return hasOK ? 19 : 42 }
        if n == "menu" || n == "mainmenu" || n == "homemenu" { return layout == .tv ? 33 : 34 }
        if channelUp.contains(n) { return layout == .disc ? nil : 4 }
        if channelDown.contains(n) { return layout == .disc ? nil : 5 }
        if layout == .disc {
            if nextTrack.contains(n) { return 4 }
            if previousTrack.contains(n) { return 5 }
            if n == "title" || n == "topmenu" || n == "discmenu" { return 35 }
            if n == "repeat" || n == "last" { return 21 }
        } else {
            if layout == .tv && (n == "guide" || n == "epg" || n == "tvguide" || n == "programguide") { return 35 }
            if lastChannel.contains(n) { return 21 }
            if layout == .audio && n == "repeat" { return 21 }
        }
        return common[n]
    }

    // One slot (or nil) per name; a slot is given to the first key that matches
    static func assign(names: [String], layout: LayoutKind) -> [Int?] {
        let normalized = names.map { norm($0) }
        let hasOK = normalized.contains { ["ok", "select", "center", "centre", "okselect"].contains($0) }
        var used = Set<Int>()
        var result = [Int?](repeating: nil, count: names.count)
        for (i, n) in normalized.enumerated() {
            if let s = lookup(n, layout: layout, hasOK: hasOK), !used.contains(s) {
                used.insert(s)
                result[i] = s
            }
        }
        return result
    }

    static func title(_ slot: Int, layout: LayoutKind) -> String {
        switch slot {
        case 1: return "Power"
        case 2: return "Power on"
        case 3: return "Power off"
        case 4: return layout == .disc ? "Next" : (layout == .audio ? "Tune +" : "CH +")
        case 5: return layout == .disc ? "Previous" : (layout == .audio ? "Tune -" : "CH -")
        case 6: return "VOL +"
        case 7: return "VOL -"
        case 8: return "Mute"
        case 9...17: return "\(slot - 8)"
        case 18: return "0"
        case 19: return "Enter"
        case 20: return layout == .tv ? "+100" : "Band"
        case 21: return layout == .disc ? "Repeat" : "Last"
        case 22: return "Input"
        case 24: return "Play"
        case 25: return "Stop"
        case 26: return "Pause"
        case 27: return "Reverse"
        case 28: return "Fast forward"
        case 29: return "Record"
        case 33: return layout == .tv ? "Menu" : "Source"
        case 34: return layout == .tv ? "Setup" : "Menu"
        case 35: return layout == .disc ? "Title" : "Guide"
        case 36: return "Exit"
        case 37: return "Back"
        case 38: return "Up"
        case 39: return "Down"
        case 40: return "Left"
        case 41: return "Right"
        case 42: return "OK"
        case 45: return "Favorite"
        case 46: return "Info"
        case 47: return "Wide"
        case 51: return "Eject"
        case 52: return "Random"
        case 53: return "PIP On"
        case 54: return "PIP Off"
        case 56: return "PIP Swap"
        case 72: return "List"
        case 73...76: return "HDMI \(slot - 72)"
        case 77: return "Red"
        case 78: return "Green"
        case 79: return "Yellow"
        case 80: return "Blue"
        default: return "Key \(slot)"
        }
    }
}
