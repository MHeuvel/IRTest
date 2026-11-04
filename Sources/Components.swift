import SwiftUI

enum Theme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let surface = Color(red: 0.16, green: 0.16, blue: 0.19)
    static let surfaceDark = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let stroke = Color.white.opacity(0.06)
}

struct RemoteKey: Hashable {
    let slot: Int
    let title: String
}

// Standaardtoetsen (toetsnummers uit de UnityRemote-database)
enum K {
    static let power = RemoteKey(slot: 1, title: "Power")
    static let powerOn = RemoteKey(slot: 2, title: "On")
    static let powerOff = RemoteKey(slot: 3, title: "Off")
    static let channelUp = RemoteKey(slot: 4, title: "CH+")
    static let channelDown = RemoteKey(slot: 5, title: "CH-")
    static let next = RemoteKey(slot: 4, title: "Next")
    static let previous = RemoteKey(slot: 5, title: "Previous")
    static let volumeUp = RemoteKey(slot: 6, title: "VOL+")
    static let volumeDown = RemoteKey(slot: 7, title: "VOL-")
    static let mute = RemoteKey(slot: 8, title: "Mute")
    static let digits: [RemoteKey] = (1...9).map { RemoteKey(slot: 8 + $0, title: "\($0)") }
    static let zero = RemoteKey(slot: 18, title: "0")
    static let enter = RemoteKey(slot: 19, title: "Enter")
    static let plus10 = RemoteKey(slot: 19, title: "+10")
    static let band = RemoteKey(slot: 20, title: "Band")
    static let last = RemoteKey(slot: 21, title: "Last")
    static let repeatKey = RemoteKey(slot: 21, title: "Repeat")
    static let input = RemoteKey(slot: 22, title: "Input")
    static let home = RemoteKey(slot: 22, title: "Home")   // only in code sets of base type 11
    static let play = RemoteKey(slot: 24, title: "Play")
    static let stop = RemoteKey(slot: 25, title: "Stop")
    static let pause = RemoteKey(slot: 26, title: "Pause")
    static let reverse = RemoteKey(slot: 27, title: "Reverse")
    static let fastForward = RemoteKey(slot: 28, title: "Forward")
    static let record = RemoteKey(slot: 29, title: "Record")
    static let sourceMenu = RemoteKey(slot: 33, title: "Source")
    static let menu = RemoteKey(slot: 34, title: "Menu")
    static let guide = RemoteKey(slot: 35, title: "Guide")
    static let title = RemoteKey(slot: 35, title: "Title")
    static let exit = RemoteKey(slot: 36, title: "Exit")
    static let back = RemoteKey(slot: 37, title: "Back")
    static let up = RemoteKey(slot: 38, title: "Up")
    static let down = RemoteKey(slot: 39, title: "Down")
    static let left = RemoteKey(slot: 40, title: "Left")
    static let right = RemoteKey(slot: 41, title: "Right")
    static let ok = RemoteKey(slot: 42, title: "OK")
    static let info = RemoteKey(slot: 46, title: "Info")
    static let eject = RemoteKey(slot: 51, title: "Eject")
    static let random = RemoteKey(slot: 52, title: "Random")
    static let red = RemoteKey(slot: 77, title: "Red")
    static let green = RemoteKey(slot: 78, title: "Green")
    static let yellow = RemoteKey(slot: 79, title: "Yellow")
    static let blue = RemoteKey(slot: 80, title: "Blue")
}

// Same behavior for all buttons: haptic on touch-down, send on release
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                if pressed { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            }
    }
}

// Platte ovaal met tekst (de aanraakzone is de hele ovaal)
struct PillKey: View {
    let key: RemoteKey
    var icon: String? = nil
    var tint: Color = .white
    var height: CGFloat = 44
    let press: (RemoteKey) -> Void

    var body: some View {
        Button { press(key) } label: {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                }
                Text(key.title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

struct PillRow: View {
    let keys: [RemoteKey]
    let press: (RemoteKey) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(keys, id: \.self) { key in
                PillKey(key: key, press: press)
            }
        }
    }
}

// Afgeronde tegel met cijfer of icoon
struct CellKey: View {
    let key: RemoteKey
    var text: String? = nil
    var icon: String? = nil
    var tint: Color = .white
    let press: (RemoteKey) -> Void

    var body: some View {
        Button { press(key) } label: {
            Group {
                if let text = text {
                    Text(text).font(.system(size: 26, weight: .semibold))
                } else if let icon = icon {
                    Image(systemName: icon).font(.system(size: 24, weight: .semibold))
                }
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity, minHeight: 66, maxHeight: 66)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(PressStyle())
    }
}

struct CapsuleSpec {
    let label: String
    let up: RemoteKey
    let down: RemoteKey
    let upIcon: String
    let downIcon: String
}

// Verticale balk met twee grote helften (bijvoorbeeld VOL + en -)
struct CapsuleKeys: View {
    let spec: CapsuleSpec
    let width: CGFloat
    let height: CGFloat
    let press: (RemoteKey) -> Void

    var body: some View {
        VStack(spacing: 0) {
            half(spec.up, spec.upIcon)
            Text(spec.label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.55))
            half(spec.down, spec.downIcon)
        }
        .frame(width: width, height: height)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    private func half(_ key: RemoteKey, _ icon: String) -> some View {
        Button { press(key) } label: {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct DPad: View {
    let size: CGFloat
    let press: (RemoteKey) -> Void

    var body: some View {
        let r = size * 0.33
        ZStack {
            Circle().fill(Theme.surface)
                .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
            arrow("chevron.up", K.up, dx: 0, dy: -r)
            arrow("chevron.down", K.down, dx: 0, dy: r)
            arrow("chevron.left", K.left, dx: -r, dy: 0)
            arrow("chevron.right", K.right, dx: r, dy: 0)
            Button { press(K.ok) } label: {
                Text("OK")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(Circle().fill(Theme.surfaceDark))
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
        }
        .frame(width: size, height: size)
    }

    private func arrow(_ icon: String, _ key: RemoteKey, dx: CGFloat, dy: CGFloat) -> some View {
        Button { press(key) } label: {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size * 0.34, height: size * 0.34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .offset(x: dx, y: dy)
    }
}

struct ColorRow: View {
    let press: (RemoteKey) -> Void

    var body: some View {
        HStack(spacing: 10) {
            colorKey(K.red, Color(red: 0.86, green: 0.24, blue: 0.22))
            colorKey(K.green, Color(red: 0.20, green: 0.66, blue: 0.30))
            colorKey(K.yellow, Color(red: 0.95, green: 0.78, blue: 0.22))
            colorKey(K.blue, Color(red: 0.20, green: 0.50, blue: 0.90))
        }
    }

    private func colorKey(_ key: RemoteKey, _ color: Color) -> some View {
        Button { press(key) } label: {
            Capsule().fill(color)
                .frame(height: 30)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}
