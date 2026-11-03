import SwiftUI

@main
struct UnityRemoteApp: App {
    @StateObject private var store = DeviceStore()
    @StateObject private var hardware: HardwareSettings
    @StateObject private var remote: RemoteController

    init() {
        let hw = HardwareSettings()
        _hardware = StateObject(wrappedValue: hw)
        _remote = StateObject(wrappedValue: RemoteController(hardware: hw))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(hardware)
                .environmentObject(remote)
        }
    }
}
