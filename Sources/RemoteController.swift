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

    // Learning
    @Published var learnStatus: String = "Idle"
    @Published var learnedData: [UInt8] = []
    @Published var isLearning = false
    @Published var learnFailed = false

    private let hardware: HardwareSettings
    private var session: EASession?
    private var pending = [UInt8]()
    private var rxBuffer = [UInt8]()
    private var noticeTimer: DispatchWorkItem?
    private var irQueue: [(bytes: [UInt8], label: String, busy: TimeInterval)] = []
    private var irBusy = false
    private var busyTimer: DispatchWorkItem?
    private var learnTimer: DispatchWorkItem?
    private var monitorTimer: Timer?
    private var openFailures = 0
    private var holdActive = false
    private var holdTimeout: DispatchWorkItem?
    private var holdStartedAt = Date.distantPast

    var chip: Chip { hardware.chip(for: accessoryKey) }

    init(hardware: HardwareSettings) {
        self.hardware = hardware
        super.init()
        EAAccessoryManager.shared().registerForLocalNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryChanged(_:)),
                                               name: .EAAccessoryDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accessoryChanged(_:)),
                                               name: .EAAccessoryDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        refresh(autoOpen: true)
        // While there is no session, check every 2 seconds whether the unit is back
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, self.session == nil else { return }
            self.refresh(autoOpen: true, quiet: true)
        }
    }

    // MARK: Log and notice

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

    // MARK: Accessories and session

    @objc private func appBecameActive() {
        if session == nil { refresh(autoOpen: true, quiet: true) }
    }

    @objc private func accessoryChanged(_ note: Notification) {
        let event = note.name == .EAAccessoryDidConnect ? "connected" : "disconnected"
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

    func refresh(autoOpen: Bool, quiet: Bool = false) {
        let all = EAAccessoryManager.shared().connectedAccessories
        if !quiet {
            addLog("Scan: \(all.count) accessory(ies)")
            for a in all {
                addLog("- \(a.name) | \(a.manufacturer) | model \(a.modelNumber) | serial \(a.serialNumber) | fw \(a.firmwareRevision) | hw \(a.hardwareRevision) | \(a.protocolStrings.joined(separator: ","))")
            }
        }
        if session != nil { return }
        if let acc = candidate() {
            let key = acc.serialNumber.isEmpty ? acc.name : acc.serialNumber
            DispatchQueue.main.async {
                self.accessoryKey = key
                self.accessoryName = acc.name
                self.accessoryInfo = "firmware \(acc.firmwareRevision) · hardware \(acc.hardwareRevision)"
                if self.status == .noAccessory { self.status = .accessoryFound }
            }
            if autoOpen { open(acc) }
        } else {
            DispatchQueue.main.async { self.status = .noAccessory }
        }
    }

    @discardableResult
    func reconnect() -> String {
        closeSession()
        refresh(autoOpen: true)
        let message = "Reconnecting…"
        showNotice(message)
        return message
    }

    // "Pair / connect": use a unit iOS already knows; only show the system picker when none is found.
    // Returns a short message for the caller to display.
    @discardableResult
    func pairOrConnect() -> String {
        if status == .connected {
            let message = "Already connected"
            showNotice(message)
            return message
        }
        if candidate() != nil {
            addLog("Unit already known to iOS: connecting")
            if session == nil { refresh(autoOpen: true) }
            let message = "Connecting…"
            showNotice(message)
            return message
        }
        showPicker()
        return "Choose your unit in the iOS list"
    }

    func showPicker() {
        EAAccessoryManager.shared().showBluetoothAccessoryPicker(withNameFilter: nil) { error in
            self.addLog(error.map { "Picker: error \($0.localizedDescription)" } ?? "Picker: done")
            self.refresh(autoOpen: true)
        }
    }

    private func open(_ accessory: EAAccessory) {
        guard let s = EASession(accessory: accessory, forProtocol: Self.protocolString) else {
            openFailures += 1
            if openFailures <= 3 { addLog("Could not open EASession (attempt \(openFailures)); retrying") }
            return
        }
        openFailures = 0
        session = s
        gotReply = false
        for stream in [s.inputStream, s.outputStream] {
            stream?.delegate = self
            stream?.schedule(in: .main, forMode: .default)
            stream?.open()
        }
        DispatchQueue.main.async { self.status = .connected }
        addLog("Session opened with \(accessory.name)")
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
        isLearning = false
        holdActive = false
        holdTimeout?.cancel()
        learnTimer?.cancel()
        busyTimer?.cancel()
        busyTimer = nil
        DispatchQueue.main.async {
            self.status = (self.candidate() != nil) ? .accessoryFound : .noAccessory
        }
        addLog("Session closed")
    }

    // MARK: Sending a key (queued: the chip needs about half a second per command)

    func send(_ key: RemoteKey, device: Device?) {
        clearNotice()
        guard let device = device, let entry = device.currentCode else {
            showNotice("Choose a device first")
            warn()
            return
        }
        guard status == .connected else {
            addLog("Not connected: \(key.title) not sent")
            showNotice("Not connected")
            warn()
            return
        }
        guard let p = Packet.irPassthrough(chip: chip, deviceType: entry.base, irCode: entry.code, keyCode: key.slot) else {
            addLog("Key \(key.title) (\(key.slot)) has no key number on \(chip.title)")
            showNotice("Function not available")
            warn()
            return
        }
        if key == K.power, device.powerHoldMs > 0,
           let hold = Packet.irPassthroughStopAfter(chip: chip, deviceType: entry.base, irCode: entry.code,
                                                    keyCode: key.slot, milliseconds: device.powerHoldMs) {
            enqueueIR(hold, label: "\(key.title) hold \(device.powerHoldMs) ms · \(device.brand) \(entry.code) · type \(entry.base) · \(chip.title)",
                      busy: max(1.5, Double(device.powerHoldMs) / 1000 + 0.8))
            return
        }
        enqueueIR(p, label: "\(key.title) · \(device.brand) \(entry.code) · type \(entry.base) · \(chip.title)")
    }

    // Press and hold, as the original app does it:
    //   start = the key packet with CMD 02 and trailer 00 (a single key uses CMD 01 and trailer 80)
    //   stop  = AA 55 02 04 CHK (no chip ID)
    // The chip needs about 0.5 s per command, so a stop is never sent sooner than that after the start.
    func startContinuous(_ key: RemoteKey, device: Device?) {
        clearNotice()
        guard let device = device, let entry = device.currentCode else { return }
        guard status == .connected else {
            addLog("HOLD ignored: not connected")
            showNotice("Not connected")
            warn()
            return
        }
        guard !holdActive else { return }
        guard let p = Packet.irPassthrough(chip: chip, deviceType: entry.base, irCode: entry.code,
                                           keyCode: key.slot, cmd: 0x02) else {
            showNotice("Function not available")
            warn()
            return
        }
        irQueue.removeAll()
        holdActive = true
        holdStartedAt = Date()
        send(p, label: "HOLD start \(key.title) · \(device.brand) \(entry.code)")
        holdTimeout?.cancel()
        // Safety: never send continuously for more than 10 seconds
        let work = DispatchWorkItem { [weak self] in self?.stopContinuous() }
        holdTimeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    func stopContinuous() {
        guard holdActive else { return }
        holdActive = false
        holdTimeout?.cancel()
        holdTimeout = nil
        let wait = max(0, 0.5 - Date().timeIntervalSince(holdStartedAt))
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.send(Packet.build(cmd: 0x04), label: "HOLD stop")
            // Give the chip a moment before the next command
            self.irBusy = true
            self.busyTimer?.cancel()
            let done = DispatchWorkItem { [weak self] in self?.finishIR() }
            self.busyTimer = done
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: done)
        }
        irBusy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    // Replay of a learned signal (00 00 LL + body):
    // AA 55 (L+11) 01 | chip(4) | (L+4) | 10 | 00 00 90 | signal(L) | CHK
    func sendLearned(_ signal: [UInt8], label: String) {
        clearNotice()
        guard status == .connected else {
            addLog("Not connected: \(label) not sent")
            showNotice("Not connected")
            warn()
            return
        }
        guard signal.count >= 3, signal.count <= 244 else {
            addLog("Learned signal has an invalid size (\(signal.count) bytes)")
            showNotice("Invalid signal")
            warn()
            return
        }
        let payload = chip.idBytes + [UInt8(signal.count + 4), 0x10, 0x00, 0x00, 0x90] + signal
        enqueueIR(Packet.build(cmd: 0x01, payload: payload), label: "LEARNED \(label) · \(signal.count) bytes")
    }

    private func enqueueIR(_ bytes: [UInt8], label: String, busy: TimeInterval = 1.5) {
        if irBusy {
            if irQueue.count < 5 {
                irQueue.append((bytes: bytes, label: label, busy: busy))
            } else {
                addLog("Queue full: \(label) skipped")
            }
            return
        }
        startIR(bytes, label: label, busy: busy)
    }

    private func startIR(_ bytes: [UInt8], label: String, busy: TimeInterval = 1.5) {
        irBusy = true
        send(bytes, label: label)
        busyTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishIR() }
        busyTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + busy, execute: work)
    }

    private func finishIR() {
        busyTimer?.cancel()
        busyTimer = nil
        irBusy = false
        if !irQueue.isEmpty {
            let next = irQueue.removeFirst()
            startIR(next.bytes, label: next.label, busy: next.busy)
        }
    }

    // MARK: Learning
    //
    // Begin learning:  AA 55 0A 01 | chip(4) | 03 | 12 | 00 00 | CHK
    // The chip answers 06 first, then (after a key press) status 00 with the data,
    // or an error status when learning times out.

    func resetLearn() {
        learnTimer?.cancel()
        isLearning = false
        learnFailed = false
        learnedData = []
        learnStatus = "Idle"
    }

    func startLearning() {
        clearNotice()
        guard status == .connected else {
            learnStatus = "Not connected"
            warn()
            return
        }
        learnedData = []
        isLearning = true
        learnFailed = false
        learnStatus = "Waiting for a key…"
        let p = Packet.build(cmd: 0x01, payload: chip.idBytes + [0x03, 0x12, 0x00, 0x00])
        send(p, label: "LEARN begin · \(chip.title)")
        learnTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.isLearning else { return }
            self.isLearning = false
            self.learnFailed = true
            self.learnStatus = "No response from the unit. Try again."
            self.addLog("LEARN: no response after 60 s")
        }
        learnTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    func cancelLearning() {
        learnTimer?.cancel()
        isLearning = false
        if learnedData.isEmpty { learnStatus = "Idle" }
    }

    private func handleLearnFrame(_ f: [UInt8]) {
        // Response frame: AA 55 LEN 20 | 01 | status | data... | CHK
        guard isLearning, f.count >= 7, f[3] == 0x20, f[4] == 0x01 else { return }
        let st = f[5]
        let data = Array(f[6..<(f.count - 1)])
        addLog("LEARN response: status \(String(format: "%02X", st)), \(data.count) data byte(s)")
        if st == 0x00 && data.count > 2 {
            learnTimer?.cancel()
            learnedData = data
            learnStatus = "Learned \(data.count) bytes"
            isLearning = false
        } else if st != 0x00 && st != 0x06 {
            learnTimer?.cancel()
            learnFailed = true
            learnStatus = st == 0x08
                ? "Learning timed out: no signal received."
                : "Learning failed (status \(String(format: "%02X", st)))."
            isLearning = false
        }
    }

    // MARK: Raw sending

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
            addLog("TX error: \(out.streamError?.localizedDescription ?? "unknown")")
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
                    addLog("RX frame: code \(String(format: "%02X", f[3])) data [\(hex(data))] checksum \(ok ? "OK" : "BAD")")
                    if ok {
                        addLog("  → \(Packet.describe(f))")
                        DispatchQueue.main.async { self.gotReply = true }
                        handleLearnFrame(f)
                        // Final response of an IR command: 20 | 01 | 00 | ...
                        if !isLearning, f.count >= 7, f[3] == 0x20, f[4] == 0x01, f[5] == 0x00 { finishIR() }
                    }
                }
            }
        case .hasSpaceAvailable:
            flush()
        case .errorOccurred:
            addLog("Stream error: \(aStream.streamError?.localizedDescription ?? "unknown")")
        case .endEncountered:
            addLog("Stream ended by the device")
            closeSession()
        case .openCompleted:
            addLog("Stream opened (\(aStream is InputStream ? "input" : "output"))")
        default:
            break
        }
    }
}
