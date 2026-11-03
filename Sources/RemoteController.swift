import Foundation
import ExternalAccessory
import UIKit

final class RemoteController: NSObject, ObservableObject, StreamDelegate {
    static let protocolString = "com.gear4.unityremote"

    enum Status { case noAccessory, accessoryFound, connected }

    @Published var log: [String] = []
    @Published var status: Status = .noAccessory
    @Published var gotReply = false
    @Published var notice: String?
    @Published var accessoryKey: String = "default"
    @Published var accessoryName: String = ""
    @Published var accessoryInfo: String = ""

    private let hardware: HardwareSettings
    private var session: EASession?
    private var pending = [UInt8]()
    private var rxBuffer = [UInt8]()
    private var noticeTimer: DispatchWorkItem?
    private var irQueue: [(bytes: [UInt8], label: String)] = []
    private var irBusy = false
    private var busyTimer: DispatchWorkItem?

    var chip: Chip { hardware.chip(for: accessoryKey) }

    init(hardware: HardwareSettings) {
        self.hardware = hardware
        super.init()
        EAAccessoryManager.shared().registerForLocalNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryChanged(_:)),
                                               name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryChanged(_:)),
                                               name: .EAAccessoryDidDisconnect, object: nil)
        refresh(autoOpen: true)
    }

    // MARK: Log en melding

    func addLog(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let line = "\(f.string(from: Date()))  \(text)"
        DispatchQueue.main.async { self.log.append(line) }
    }

    func showNotice(_ text: String) {
        noticeTimer?.cancel()
        notice = text
        let work = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    func clearNotice() {
        noticeTimer?.cancel()
        noticeTimer = nil
        if notice != nil { notice = nil }
    }

    private func warn() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }

    // MARK: Accessoires en sessie

    @objc private func accessoryChanged(_ note: Notification) {
        let event = note.name == .EAAccessoryDidConnect ? "verbonden" : "losgekoppeld"
        if let acc = note.userInfo?[EAAccessoryKey] as? EAAccessory {
            addLog("Event: \(acc.name) \(event)")
        }
        if note.name == .EAAccessoryDidDisconnect { closeSession() }
        refresh(autoOpen: note.name == .EAAccessoryDidConnect)
    }

    private func candidate() -> EAAccessory? {
        EAAccessoryManager.shared().connectedAccessories.first {
            $0.protocolStrings.contains(Self.protocolString)
        }
    }

    func refresh(autoOpen: Bool) {
        let all = EAAccessoryManager.shared().connectedAccessories
        addLog("Zoeken: \(all.count) accessoire(s)")
        for a in all {
            addLog("- \(a.name) | \(a.manufacturer) | model \(a.modelNumber) | serie \(a.serialNumber) | fw \(a.firmwareRevision) | hw \(a.hardwareRevision) | \(a.protocolStrings.joined(separator: ","))")
        }
        if session != nil { return }
        if let acc = candidate() {
            let key = acc.serialNumber.isEmpty ? acc.name : acc.serialNumber
            DispatchQueue.main.async {
                self.accessoryKey = key
                self.accessoryName = acc.name
                self.accessoryInfo = "firmware \(acc.firmwareRevision) · hardware \(acc.hardwareRevision)"
                self.status = .accessoryFound
            }
            if autoOpen { open(acc) }
        } else {
            DispatchQueue.main.async { self.status = .noAccessory }
        }
    }

    func reconnect() {
        closeSession()
        refresh(autoOpen: true)
    }

    func showPicker() {
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { error in
            self.addLog(error.map { "Kiezer: fout \($0.localizedDescription)" } ?? "Kiezer: klaar")
            self.refresh(autoOpen: true)
        }
    }

    private func open(_ accessory: EAAccessory) {
        guard let s = EASession(accessory: accessory, forProtocol: Self.protocolString) else {
            addLog("EASession kon niet worden geopend")
            return
        }
        session = s
        gotReply = false
        for stream in [s.inputStream, s.outputStream] {
            stream?.delegate = self
            stream?.schedule(in: .main, forMode: .default)
            stream?.open()
        }
        DispatchQueue.main.async { self.status = .connected }
        addLog("Sessie geopend met \(accessory.name)")
        send(Packet.build(cmd: 0x5D), label: "GetVersion")
    }

    func closeSession() {
        guard let s = session else { return }
        for stream in [s.inputStream, s.outputStream] {
            stream?.close()
            stream?.remove(from: .main, forMode: .default)
        }
        session = nil
        pending.removeAll()
        rxBuffer.removeAll()
        irQueue.removeAll()
        irBusy = false
        busyTimer?.cancel()
        busyTimer = nil
        DispatchQueue.main.async {
            self.status = (self.candidate() != nil) ? .accessoryFound : .noAccessory
        }
        addLog("Sessie gesloten")
    }

    // MARK: Toets versturen (met wachtrij: de chip heeft ongeveer een halve seconde per commando nodig)

    func send(_ key: RemoteKey, device: Device?) {
        clearNotice()
        guard let device = device, let entry = device.currentCode else {
            showNotice("Kies eerst een apparaat")
            warn()
            return
        }
        guard status == .connected else {
            addLog("Niet verbonden: \(key.title) niet verstuurd")
            showNotice("Niet verbonden")
            warn()
            return
        }
        guard let p = Packet.irPassthrough(chip: chip, deviceType: entry.base, irCode: entry.code, keyCode: key.slot) else {
            addLog("Toets \(key.title) (\(key.slot)) heeft geen toetsnummer op \(chip.title)")
            showNotice("Functie niet beschikbaar")
            warn()
            return
        }
        enqueueIR(p, label: "\(key.title) · \(device.brand) \(entry.code) · type \(entry.base) · \(chip.title)")
    }

    private func enqueueIR(_ bytes: [UInt8], label: String) {
        if irBusy {
            if irQueue.count < 5 {
                irQueue.append((bytes: bytes, label: label))
            } else {
                addLog("Wachtrij vol: \(label) overgeslagen")
            }
            return
        }
        startIR(bytes, label: label)
    }

    private func startIR(_ bytes: [UInt8], label: String) {
        irBusy = true
        send(bytes, label: label)
        busyTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishIR() }
        busyTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func finishIR() {
        busyTimer?.cancel()
        busyTimer = nil
        irBusy = false
        if !irQueue.isEmpty {
            let next = irQueue.removeFirst()
            startIR(next.bytes, label: next.label)
        }
    }

    // MARK: Ruwe verzending

    func send(_ bytes: [UInt8], label: String) {
        pending += bytes
        addLog("TX \(label): \(hex(bytes))")
        flush()
    }

    private func flush() {
        guard let out = session?.outputStream, out.hasSpaceAvailable, !pending.isEmpty else { return }
        let n = pending.withUnsafeBufferPointer { out.write($0.baseAddress!, maxLength: pending.count) }
        if n > 0 {
            pending.removeFirst(n)
        } else if n < 0 {
            addLog("TX fout: \(out.streamError?.localizedDescription ?? "onbekend")")
        }
    }

    // MARK: StreamDelegate

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let input = aStream as? InputStream else { return }
            var buf = [UInt8](repeating: 0, count: 1024)
            while input.hasBytesAvailable {
                let n = input.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                let chunk = Array(buf.prefix(n))
                addLog("RX raw (\(n)): \(hex(chunk))")
                rxBuffer += chunk
                for f in Packet.extract(from: &rxBuffer) {
                    let ok = Packet.checksumOK(f)
                    let data = f.count > 5 ? Array(f[4..<(f.count - 1)]) : []
                    addLog("RX frame: code \(String(format: "%02X", f[3])) data [\(hex(data))] checksum \(ok ? "OK" : "FOUT")")
                    if ok {
                        addLog("  → \(Packet.describe(f))")
                        DispatchQueue.main.async { self.gotReply = true }
                        // Slotbericht van een IR-commando: 20 | 01 | 00 | ...
                        if f.count >= 7, f[3] == 0x20, f[4] == 0x01, f[5] == 0x00 { finishIR() }
                    }
                }
            }
        case .hasSpaceAvailable:
            flush()
        case .errorOccurred:
            addLog("Stream-fout: \(aStream.streamError?.localizedDescription ?? "onbekend")")
        case .endEncountered:
            addLog("Stream beëindigd door het apparaat")
            closeSession()
        case .openCompleted:
            addLog("Stream geopend (\(aStream is InputStream ? "input" : "output"))")
        default:
            break
        }
    }
}
