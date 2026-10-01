import CoreMIDI
import Foundation

/// Controls Logic as a Mackie Control (Logic Control) surface over a
/// virtual CoreMIDI port pair. Logic scans new ports and installs the
/// surface itself once the handshake is answered (EXP-MCU-001…009), so no
/// GUI setup is needed. Every write is verified from Logic's feedback:
/// LEDs, fader echo and LCD text.
///
/// Scope (v0.1): tracks 1–8 = MCU strips 1–8 of the first bank. Strip order
/// is Logic's mixer order and also contains Stereo Out / Master strips.
public final class MCUBackend: LogicBackend {
    public let kind = BackendKind.mcu
    /// Same name as the research probe so Logic reuses its surface entry.
    public static let portName = "logicctl-mcu"
    static let serial = Array("LCTL001".utf8)
    /// Logic reverts transient LCD text (dB, "Muted", pan) about 1 s after the last change.
    static let lcdRevert: TimeInterval = 1.3

    private let cond = NSCondition()
    private var surface = MCUSurface()
    private var handshakeAt: Date?
    private var lastTX = Date.distantPast
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private let log: (String) -> Void
    private let trace: Bool

    public init(trace: Bool = false, log: @escaping (String) -> Void) {
        self.trace = trace
        self.log = log
    }

    // MARK: - CoreMIDI

    public func start() throws {
        let status = MIDIClientCreateWithBlock("logicd" as CFString, &client) { _ in }
        guard status == noErr else { throw CommandError("midi_error", "MIDIClientCreate failed: \(status)") }
        try createPorts()
    }

    private func createPorts() throws {
        var status = MIDISourceCreate(client, Self.portName as CFString, &source)
        guard status == noErr else { throw CommandError("midi_error", "MIDISourceCreate failed: \(status)") }
        status = MIDIDestinationCreateWithBlock(client, Self.portName as CFString, &destination) { [weak self] list, _ in
            self?.received(list)
        }
        guard status == noErr else { throw CommandError("midi_error", "MIDIDestinationCreate failed: \(status)") }
        log("mcu: virtual ports '\(Self.portName)' created; waiting for Logic's device query")
    }

    /// Removes and recreates the ports, like unplugging the device. Logic did
    /// not re-scan when logicd restarted within ~0.3 s of the old ports
    /// disappearing (3 of 5 restarts, 2026-10-01); a fresh appearance after a
    /// pause does trigger the device query.
    private func replugPorts() {
        log("mcu: no device query from Logic; re-plugging virtual ports")
        MIDIEndpointDispose(source)
        MIDIEndpointDispose(destination)
        cond.lock()
        surface.reset()
        handshakeAt = nil
        cond.unlock()
        Thread.sleep(forTimeInterval: 1.0)
        do {
            try createPorts()
        } catch {
            log("mcu: \(error)")
        }
    }

    private func received(_ list: UnsafePointer<MIDIPacketList>) {
        var bytes: [UInt8] = []
        for packet in list.unsafeSequence() {
            let length = Int(packet.pointee.length)
            let data = UnsafeRawPointer(packet).advanced(by: MemoryLayout<MIDIPacket>.offset(of: \.data)!)
            bytes.append(contentsOf: UnsafeRawBufferPointer(start: data, count: length))
        }
        var replies: [[UInt8]] = []
        cond.lock()
        let events = surface.feed(bytes)
        for event in events {
            switch event {
            case .deviceQuery(MCU.model):
                replies.append(MCU.sysexHeader + [0x01] + Self.serial + [0x01, 0x02, 0x03, 0x04, 0xF7])
                handshakeAt = Date()
            case .versionRequest(MCU.model):
                replies.append(MCU.sysexHeader + [0x14] + Array("V1.02".utf8) + [0xF7])
            case .connectionReply(MCU.model):
                replies.append(MCU.sysexHeader + [0x03] + Self.serial + [0xF7])
            default:
                break
            }
        }
        cond.broadcast()
        cond.unlock()
        if trace { log("mcu RX \(hex(bytes))") }
        if !replies.isEmpty {
            log("mcu: answering Logic handshake (\(replies.count) replies)")
            send(replies)
        }
    }

    private func send(_ messages: [[UInt8]]) {
        for m in messages {
            var list = MIDIPacketList()
            let packet = MIDIPacketListInit(&list)
            _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, m.count, m)
            MIDIReceived(source, &list)
            if trace { log("mcu TX \(hex(m))") }
        }
        cond.lock()
        lastTX = Date()
        cond.unlock()
    }

    private func read<T>(_ f: (MCUSurface) -> T) -> T {
        cond.lock()
        defer { cond.unlock() }
        return f(surface)
    }

    /// Waits until `pred` holds or `timeout` passes; returns the final value of `pred`.
    @discardableResult
    private func wait(_ timeout: TimeInterval, until pred: (MCUSurface) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock()
        defer { cond.unlock() }
        while !pred(surface) {
            if !cond.wait(until: deadline) { return pred(surface) }
        }
        return true
    }

    /// Waits until Logic has had time to revert transient LCD text.
    private func waitForSteadyLCD() {
        let since = read { _ in Date().timeIntervalSince(lastTX) }
        if since < Self.lcdRevert { Thread.sleep(forTimeInterval: Self.lcdRevert - since) }
    }

    // MARK: - LogicBackend

    public func execute(_ command: LogicCommand) -> Outcome {
        if case .status = command { return status() }
        if let failure = ensureConnected() { return failure }
        switch command {
        case .status, .daemonStop: return status()
        case .state: return state()
        case .transportPlay: return transport(play: true)
        case .transportStop: return transport(play: false)
        case .trackList: return Outcome(ok: true, result: .array(trackList()))
        case .trackGet(let t): return withStrip(t) { Outcome(ok: true, result: self.trackInfo($0, readVolume: true)) }
        case .trackSelect(let t): return withStrip(t) { self.select($0) }
        case .trackMute(let t, let on): return withStrip(t) { self.toggle($0, on: on, kind: .mute) }
        case .trackSolo(let t, let on): return withStrip(t) { self.toggle($0, on: on, kind: .solo) }
        case .trackVolume(let t, let db, let tol): return withStrip(t) { self.volume($0, db: db, tolerance: tol) }
        case .trackPan(let t, let pan): return withStrip(t) { self.pan($0, normalized: pan) }
        }
    }

    public var isConnected: Bool { read { $0.lcdUpdates > 0 } && handshakeAt != nil }

    private func ensureConnected() -> Outcome? {
        guard LogicApp.running() != nil else {
            return .failure("logic_not_running", "Logic Pro is not running.")
        }
        let connected = { (s: MCUSurface) in self.handshakeAt != nil && s.lcdUpdates > 0 }
        if !wait(2.5, until: connected) { replugPorts() }
        if wait(4, until: connected) {
            // Logic streams its full state dump for a few hundred ms after the
            // handshake; LCD writes from it would overwrite our readback.
            let age = read { _ in handshakeAt.map { Date().timeIntervalSince($0) } ?? 0 }
            if age < 1.0 { Thread.sleep(forTimeInterval: 1.0 - age) }
            return nil
        }
        return .failure("surface_not_connected",
                        "Logic has not connected to the '\(Self.portName)' control surface. "
                            + "Check Logic Pro > Control Surfaces > Setup… for a Logic Control on that port.")
    }

    private func withStrip(_ track: Int, _ body: (Int) -> Outcome) -> Outcome {
        guard (1...MCU.strips).contains(track) else {
            return .failure("track_out_of_bank",
                            "v0.1 controls tracks 1–\(MCU.strips) (first MCU bank). Track \(track) needs bank switching.")
        }
        let strip = track - 1
        guard !read({ $0.upperText(strip) }).isEmpty else {
            return .failure("no_such_track", "MCU strip \(track) is empty: the project has fewer channel strips.")
        }
        return body(strip)
    }

    // MARK: - Reads

    private func status() -> Outcome {
        let logic = LogicApp.running()
        let connected = logic != nil && isConnected
        var result: [String: JSONValue] = [
            "daemon": ["pid": .int(Int(getpid()))],
            "logic": logic?.json ?? ["running": false],
            "mcu": ["port": .string(Self.portName), "connected": .bool(connected),
                    "handshake_at": .string(read { _ in handshakeAt }.map { ISO8601DateFormatter().string(from: $0) })],
        ]
        if connected {
            result["transport"] = transportJSON()
            // Raw surface LCD, for diagnosing readback problems.
            result["mcu_lcd"] = read { s in [.string(s.row(0)), .string(s.row(1))] }
        }
        return Outcome(ok: true, result: .object(result))
    }

    private func transportJSON() -> JSONValue {
        read { s in ["playing": .bool(s.led(MCU.playNote)), "recording": .bool(s.led(MCU.recordNote))] }
    }

    private func state() -> Outcome {
        let tracks = trackList()
        let selected = read { s in (0..<MCU.strips).first { s.led(MCU.selectNote($0)) } }
        return Outcome(ok: true, result: [
            "transport": transportJSON(),
            "selected_track": .int(selected.map { $0 + 1 }),
            "tracks": .array(tracks),
        ])
    }

    private func trackList() -> [JSONValue] {
        waitForSteadyLCD()
        let strips = read { s in (0..<MCU.strips).filter { !s.upperText($0).isEmpty } }
        // Read pan (steady LCD) for all strips first; touching faders makes the LCD transient.
        let infos = strips.map { trackInfo($0, readVolume: false) }
        return zip(strips, infos).map { strip, info in
            guard case .object(var o) = info else { return info }
            let (db, source) = readVolume(strip)
            o["volume_db"] = .db(db)
            o["volume_source"] = .string(source)
            return .object(o)
        }
    }

    /// Waits until the strip's lower LCD cell shows a pan value again. After a
    /// select Logic shows the track name there for up to ~3 s (EXP-MCU-012,
    /// logicctl run 2026-10-01). An empty cell (e.g. Master) has no pan.
    private func waitForPanDisplay(_ strip: Int) {
        waitForSteadyLCD()
        wait(3) { s in
            let t = s.lowerText(strip)
            return t.isEmpty || parseLCDPan(t) != nil
        }
    }

    private func trackInfo(_ strip: Int, readVolume withVolume: Bool) -> JSONValue {
        waitForPanDisplay(strip)
        var o: [String: JSONValue] = read { s in
            let soloActive = s.anySoloActive
            let pan = parseLCDPan(s.lowerText(strip))
            var o: [String: JSONValue] = [
                "id": .int(strip + 1),
                "name": .string(s.upperText(strip)),
                "solo": .bool(s.led(MCU.soloNote(strip))),
                "selected": .bool(s.led(MCU.selectNote(strip))),
                "rec_armed": .bool(s.led(MCU.recNote(strip))),
                "pan": pan.map { .number(Double($0) / 64) } ?? .null,
                "pan_raw": .int(pan),
                // Logic blinks the mute LED of strips muted implicitly by a solo.
                "mute": soloActive ? .null : .bool(s.led(MCU.muteNote(strip))),
            ]
            if soloActive { o["mute_note"] = "unknown while a solo is active (Logic blinks implied mutes)" }
            return o
        }
        if withVolume {
            let (db, source) = readVolume(strip)
            o["volume_db"] = .db(db)
            o["volume_source"] = .string(source)
        }
        return .object(o)
    }

    /// Exact dB via fader touch: Logic prints the current value on the LCD.
    private func readVolume(_ strip: Int) -> (Double?, String) {
        let before = read { $0.lowerWrites[strip] }
        send([[0x90, MCU.touchNote(strip), 0x7F]])
        wait(0.3) { $0.lowerWrites[strip] > before }
        let (text, fader) = read { ($0.lowerText(strip), $0.faders[strip]) }
        send([[0x90, MCU.touchNote(strip), 0x00]])
        if let db = parseLCDDecibels(text) { return (db, "lcd") }
        return (fader.map { (FaderCalibration.db(forValue: $0) * 10).rounded() / 10 }, "fader_estimate")
    }

    // MARK: - Writes

    private func transport(play: Bool) -> Outcome {
        let requested: JSONValue = ["playing": .bool(play)]
        let (playing, recording) = read { ($0.led(MCU.playNote), $0.led(MCU.recordNote)) }
        // A second Stop moves the playhead to the start, so never send Stop when already stopped.
        if playing == play && !(recording && !play) {
            return .write(matched: true, requested: requested, observed: ["playing": .bool(playing)],
                          message: "already in the requested state; nothing sent")
        }
        send(MCU.press(play ? MCU.playNote : MCU.stopNote))
        let ok = wait(1.0) { $0.led(MCU.playNote) == play }
        return .write(matched: ok, requested: requested, observed: transportJSON())
    }

    private func select(_ strip: Int) -> Outcome {
        let requested: JSONValue = ["selected_track": .int(strip + 1)]
        func observed() -> JSONValue {
            read { s in ["selected_track": .int((0..<MCU.strips).first { s.led(MCU.selectNote($0)) }.map { $0 + 1 })] }
        }
        if read({ $0.led(MCU.selectNote(strip)) }) {
            return .write(matched: true, requested: requested, observed: observed(),
                          message: "already selected; nothing sent")
        }
        send(MCU.press(MCU.selectNote(strip)))
        let ok = wait(0.5) { $0.led(MCU.selectNote(strip)) }
        return .write(matched: ok, requested: requested, observed: observed(),
                      message: "Logic moves record-arm with the selection when auto rec-arm is on.")
    }

    private enum Toggle {
        case mute, solo
        var key: String { self == .mute ? "mute" : "solo" }
        func note(_ strip: Int) -> UInt8 { self == .mute ? MCU.muteNote(strip) : MCU.soloNote(strip) }
        /// LCD text Logic shows right after the button press.
        func state(fromLCD text: String) -> Bool? {
            switch text {
            case self == .mute ? "Muted" : "Soloed": return true
            case "--": return false
            default: return nil
            }
        }
    }

    private func toggle(_ strip: Int, on: Bool, kind: Toggle) -> Outcome {
        let requested: JSONValue = ["track": .int(strip + 1), kind.key: .bool(on)]
        let note = kind.note(strip)
        // While a solo is active the mute LED blinks for implied mutes, so it is not the mute state.
        let ledTrustworthy = { (s: MCUSurface) in kind == .solo || !s.anySoloActive }
        if read({ ledTrustworthy($0) && $0.led(note) == on }) {
            return .write(matched: true, requested: requested,
                          observed: ["track": .int(strip + 1), kind.key: .bool(on)],
                          message: "already in the requested state; nothing sent")
        }
        var observedState: Bool?
        for _ in 0..<2 {
            let before = read { $0.lowerWrites[strip] }
            send(MCU.press(note))
            wait(0.5) { $0.lowerWrites[strip] > before }
            observedState = kind.state(fromLCD: read { $0.lowerText(strip) })
            if observedState == nil, read(ledTrustworthy) {
                wait(0.3) { $0.led(note) == on }
                observedState = read { $0.led(note) }
            }
            // The starting state was unknown (blinking LED) and the toggle went the wrong way.
            if observedState != on && observedState != nil { continue }
            break
        }
        var matched = observedState == on
        if matched, read(ledTrustworthy) {
            matched = wait(0.5) { $0.led(note) == on }
        }
        return .write(matched: matched, requested: requested,
                      observed: ["track": .int(strip + 1), kind.key: .bool(observedState)])
    }

    private func volume(_ strip: Int, db target: Double, tolerance: Double) -> Outcome {
        let requested: JSONValue = ["track": .int(strip + 1), "volume_db": .db(target)]
        func error(_ obs: Double) -> Double {
            if target.isInfinite || obs.isInfinite { return target == obs ? 0 : .infinity }
            return abs(obs - target)
        }
        send([[0x90, MCU.touchNote(strip), 0x7F]])
        defer { send([[0x90, MCU.touchNote(strip), 0x00]]) }

        var value = FaderCalibration.value(forDB: target)
        var step = 1
        var best: (value: Int, db: Double)?
        var last: Double?
        for _ in 0..<8 {
            let before = read { $0.faderUpdates[strip] }
            send([MCU.fader(strip, value)])
            wait(0.4) { $0.faderUpdates[strip] > before }
            guard let obs = parseLCDDecibels(read { $0.lowerText(strip) }) else { break }
            if best == nil || error(obs) < error(best!.db) { best = (read { $0.faders[strip] } ?? value, obs) }
            if error(obs) <= 0.05 { break }
            // Logic snaps the fader; if the LCD did not move, take bigger steps.
            step = (last == obs) ? step * 2 : 1
            last = obs
            let guess = FaderCalibration.value(forDB: target) - FaderCalibration.value(forDB: obs)
            let delta = guess == 0 ? (target > obs ? step : -step) : guess.signum() * max(abs(guess), step)
            value = max(0, min(16383, value + delta))
        }
        if let b = best, read({ $0.faders[strip] }) != b.value {
            send([MCU.fader(strip, b.value)])
            wait(0.4) { $0.faders[strip] == b.value }
        }
        let obs = parseLCDDecibels(read { $0.lowerText(strip) }) ?? best?.db
        let fader = read { $0.faders[strip] }
        return .write(matched: obs.map { error($0) <= tolerance + 1e-9 } ?? false, requested: requested,
                      observed: ["track": .int(strip + 1), "volume_db": .db(obs), "fader_value": .int(fader)],
                      message: obs == nil ? "no dB readback on the LCD" : nil)
    }

    private func pan(_ strip: Int, normalized: Double) -> Outcome {
        let target = max(-64, min(63, Int((normalized * 64).rounded())))
        let requested: JSONValue = ["track": .int(strip + 1), "pan": .number(normalized), "pan_raw": .int(target)]
        func observed(_ raw: Int?) -> JSONValue {
            ["track": .int(strip + 1), "pan": raw.map { .number(Double($0) / 64) } ?? .null, "pan_raw": .int(raw)]
        }
        /// Turns the V-Pot and returns the pan value Logic prints afterwards.
        func turn(_ ticks: Int) -> Int? {
            var remaining = ticks
            while remaining != 0 {
                let chunk = max(-20, min(20, remaining))  // ≤20 ticks per message verified linear
                let before = read { $0.lowerWrites[strip] }
                send([MCU.vpot(strip, ticks: chunk)])
                wait(0.4) { $0.lowerWrites[strip] > before }
                remaining -= chunk
            }
            return parseLCDPan(read { $0.lowerText(strip) })
        }
        waitForPanDisplay(strip)
        var current = parseLCDPan(read { $0.lowerText(strip) })
        if current == nil {
            // Learn the absolute value: one tick towards the target prints it.
            current = turn(target < 0 ? -1 : 1)
        }
        guard var now = current else {
            return .failure("readback_unavailable", "Logic did not print a pan value on the MCU LCD.",
                            requested: requested)
        }
        if now == target {
            return .write(matched: true, requested: requested, observed: observed(now),
                          message: "already in the requested state; nothing sent")
        }
        for _ in 0..<2 {
            guard let after = turn(target - now) else { break }
            now = after
            if now == target { break }
        }
        return .write(matched: now == target, requested: requested, observed: observed(now))
    }
}

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
