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
/// What the backend needs from the outside world. The default talks to CoreMIDI
/// and the running Logic; tests inject a fake surface and shrink time.
public struct MCUEnvironment {
    /// Sends one MIDI message to Logic. nil = through the virtual CoreMIDI source.
    public var transmit: (([UInt8]) -> Void)?
    public var runningApp: () -> LogicAppInfo?
    /// Multiplies every wait and sleep. Only tests set it below 1.
    public var timeScale: Double

    public init(transmit: (([UInt8]) -> Void)? = nil,
                runningApp: @escaping () -> LogicAppInfo? = { LogicApp.running() },
                timeScale: Double = 1) {
        self.transmit = transmit
        self.runningApp = runningApp
        self.timeScale = timeScale
    }
}

public final class MCUBackend: LogicBackend, TransportReadback {
    public let kind = BackendKind.mcu
    /// Same name as the research probe so Logic reuses its surface entry.
    public static let portName = "logicctl-mcu"
    static let serial = Array("LCTL001".utf8)
    /// Logic reverts transient LCD text (dB, "Muted", pan) about 1 s after the last change.
    static let lcdRevert: TimeInterval = 1.3

    private let cond = NSCondition()
    private var surface = MCUSurface()
    private var handshakeAt: Date?
    private var handshakePID: Int32?
    private var handshakeGeneration = 0
    private var handshakeLCDBaseline = 0
    private var transportBaseline = (play: 0, record: 0)
    // A prepare/snapshot/send/wait sequence runs under logicd's command lock.
    // Capturing the session and counters keeps old LEDs out of write verification.
    private var preparedTransport: (pid: Int32, generation: Int, playUpdates: Int,
                                    recordUpdates: Int, state: TransportSnapshot)?
    private var lastTX = Date.distantPast
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private let log: (String) -> Void
    private let trace: Bool
    private let environment: MCUEnvironment

    public init(trace: Bool = false, environment: MCUEnvironment = MCUEnvironment(),
                log: @escaping (String) -> Void) {
        self.trace = trace
        self.environment = environment
        self.log = log
    }

    private func pause(_ t: TimeInterval) { Thread.sleep(forTimeInterval: t * environment.timeScale) }

    // MARK: - CoreMIDI

    public func start() throws {
        let status = MIDIClientCreateWithBlock("logicd" as CFString, &client) { _ in }
        guard status == noErr else { throw CommandError("midi_error", "MIDIクライアントの作成に失敗しました: \(status)") }
        try createPorts()
    }

    private func createPorts() throws {
        var status = MIDISourceCreate(client, Self.portName as CFString, &source)
        guard status == noErr else { throw CommandError("midi_error", "MIDI送信ポートの作成に失敗しました: \(status)") }
        status = MIDIDestinationCreateWithBlock(client, Self.portName as CFString, &destination) { [weak self] list, _ in
            self?.received(list)
        }
        guard status == noErr else { throw CommandError("midi_error", "MIDI受信ポートの作成に失敗しました: \(status)") }
        log("mcu: 仮想ポート '\(Self.portName)' を作成しました。Logicの接続要求を待っています")
    }

    /// Removes and recreates the ports, like unplugging the device. Logic did
    /// not re-scan when logicd restarted within ~0.3 s of the old ports
    /// disappearing (3 of 5 restarts, 2026-10-01); a fresh appearance after a
    /// pause does trigger the device query.
    private func replugPorts() {
        log("mcu: Logicから接続要求がないため、仮想ポートを作り直します")
        if environment.transmit == nil {
            MIDIEndpointDispose(source)
            MIDIEndpointDispose(destination)
        }
        cond.lock()
        surface.reset()
        handshakeAt = nil
        handshakePID = nil
        handshakeGeneration += 1
        handshakeLCDBaseline = 0
        transportBaseline = (0, 0)
        preparedTransport = nil
        cond.unlock()
        bankOffset = nil
        colorsAtPositioning = -1
        generationAtPositioning = -1
        namesAtPositioning = nil
        guard environment.transmit == nil else { return }
        pause(1.0)
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
        ingest(bytes)
    }

    /// Feeds bytes received from Logic into the surface mirror and answers the
    /// handshake. Internal so tests can play Logic's part without CoreMIDI.
    func ingest(_ bytes: [UInt8]) {
        var replies: [[UInt8]] = []
        cond.lock()
        let events = surface.feed(bytes)
        for (index, event) in events.enumerated() {
            switch event {
            case .deviceQuery(MCU.model):
                replies.append(MCU.sysexHeader + [0x01] + Self.serial + [0x01, 0x02, 0x03, 0x04, 0xF7])
                handshakeAt = Date()
                handshakePID = environment.runningApp()?.pid
                handshakeGeneration += 1
                let baseline = surface.feedbackCounters(atEvent: index, in: events)
                handshakeLCDBaseline = baseline.lcd
                transportBaseline = (baseline.play, baseline.record)
                preparedTransport = nil
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
            log("mcu: Logicの接続要求に応答します（\(replies.count) 件）")
            send(replies)
        }
    }

    /// `transient: false` for messages that do not make Logic show temporary
    /// LCD text (bank navigation), so they do not delay LCD reads.
    private func send(_ messages: [[UInt8]], transient: Bool = true) {
        for m in messages {
            if let transmit = environment.transmit {
                transmit(m)
            } else {
                var list = MIDIPacketList()
                let packet = MIDIPacketListInit(&list)
                _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, m.count, m)
                MIDIReceived(source, &list)
            }
            if trace { log("mcu TX \(hex(m))") }
        }
        guard transient else { return }
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
        let deadline = Date().addingTimeInterval(timeout * environment.timeScale)
        cond.lock()
        var held = true
        while !pred(surface) {
            if !cond.wait(until: deadline) { held = pred(surface); break }
        }
        cond.unlock()
        testHook?("afterWait")
        return held
    }

    /// Tests only: called (outside the lock) at named points of the button writes, to let a fake Logic
    /// re-run the handshake exactly there. Never set in the product.
    var testHook: ((String) -> Void)?

    /// Waits until Logic has had time to revert transient LCD text.
    private func waitForSteadyLCD() {
        let since = read { _ in Date().timeIntervalSince(lastTX) }
        let revert = Self.lcdRevert * environment.timeScale
        if since < revert { Thread.sleep(forTimeInterval: revert - since) }
    }

    // MARK: - LogicBackend

    public func execute(_ command: LogicCommand) -> Outcome { execute(command, expectName: nil) }

    /// `expectName` is the strip name exactly as `track list` / `track get` showed it. It is
    /// checked against the LCD after positioning and before anything is sent: a track number
    /// is a mixer position, and a rename, reorder, add or delete since the read moves it
    /// (docs/target-contract.md). A mismatch is `target_mismatch`, nothing sent.
    public func execute(_ command: LogicCommand, expectName: String?) -> Outcome {
        if expectName != nil, command.trackNumber == nil {
            return .failure("invalid_argument", "名前の照合はトラックを指定するコマンドだけで使えます。")
        }
        if case .status = command { return status() }
        if let failure = ensureConnected() { return failure }
        switch command {
        case .status, .daemonStop: return status()
        case .state: return state()
        case .transportPlay: return transport(play: true)
        case .transportStop: return transport(play: false)
        case .trackList:
            let scan = scanTracks()
            return Outcome(ok: scan.complete, result: .array(scan.tracks), error: scan.error, message: scan.message,
                           observation: observation(scope: "mixer_strips", complete: scan.complete, extra: scan.extra))
        case .trackGet(let t):
            return withStrip(t, expectName: expectName) { strip in
                let info = self.trackInfo(strip, readVolume: true)
                let known = info["unknown"] == .array([])
                return Outcome(ok: true, result: info,
                               observation: self.observation(scope: "mixer_strip", complete: known,
                                                             extra: ["track": .int(self.trackID(strip))]))
            }
        case .trackSelect(let t): return withStrip(t, expectName: expectName) { self.select($0) }
        case .trackMute(let t, let on): return withStrip(t, expectName: expectName) { self.toggle($0, on: on, kind: .mute) }
        case .trackArm(let t, let on): return withStrip(t, expectName: expectName) { self.arm($0, on: on) }
        case .trackSolo(let t, let on): return withStrip(t, expectName: expectName) { self.toggle($0, on: on, kind: .solo) }
        case .trackVolume(let t, let db, let tol): return withStrip(t, expectName: expectName) { self.volume($0, db: db, tolerance: tol) }
        case .trackPan(let t, let pan): return withStrip(t, expectName: expectName) { self.pan($0, normalized: pan) }
        case .debugMCU(let messages): return debugMCU(messages)
        }
    }

    /// Generation of Logic's current connection (the same number reads report as
    /// `observation.session.handshake_generation`), or nil when not connected.
    public func sessionGeneration() -> Int? {
        read { _ in handshakeAt == nil ? nil : handshakeGeneration }
    }

    public var isConnected: Bool {
        guard let pid = environment.runningApp()?.pid else { return false }
        return read { $0.lcdUpdates > handshakeLCDBaseline && handshakeAt != nil && handshakePID == pid }
    }

    private func ensureConnected() -> Outcome? {
        guard let app = environment.runningApp() else {
            return .failure("logic_not_running", "Logic Proを起動してください。")
        }
        let connected = { (s: MCUSurface) in
            self.handshakeAt != nil && self.handshakePID == app.pid && s.lcdUpdates > self.handshakeLCDBaseline
        }
        if !wait(2.5, until: connected) { replugPorts() }
        if wait(4, until: connected) {
            // Logic streams its full state dump for a few hundred ms after the
            // handshake; LCD writes from it would overwrite our readback.
            let age = read { _ in handshakeAt.map { Date().timeIntervalSince($0) } ?? 0 }
            let dump = 1.0 * environment.timeScale
            if age < dump { Thread.sleep(forTimeInterval: dump - age) }
            return nil
        }
        return .failure("surface_not_connected",
                        "Logicが '\(Self.portName)' コントロールサーフェスに接続していません。 "
                            + "Logic Proの「コントロールサーフェス」→「設定」で、このポートのLogic Controlを確認してください。")
    }

    // MARK: - Independent transport readback (no transport MIDI writes)

    private func transportSnapshotLocked(_ state: MCUSurface, pid: Int32) -> TransportSnapshot? {
        guard handshakePID == pid, handshakeAt != nil, state.lcdUpdates > handshakeLCDBaseline else { return nil }
        return state.transportSnapshot(sincePlayUpdate: transportBaseline.play,
                                       sinceRecordUpdate: transportBaseline.record)
    }

    public func prepareTransportReadback() -> Outcome? {
        if let failure = ensureConnected() { return failure }
        guard let pid = environment.runningApp()?.pid else {
            return .failure("logic_not_running", "Logic Proを起動してください。")
        }
        guard wait(1.0, until: { self.transportSnapshotLocked($0, pid: pid) != nil }) else {
            return .failure("readback_unavailable", "この接続で再生・録音の両方のLED状態を受信できていません。")
        }
        cond.lock()
        defer { cond.unlock() }
        guard let snapshot = transportSnapshotLocked(surface, pid: pid) else {
            return .failure("readback_unavailable", "状態の確認中にLogicとの接続が変わりました。")
        }
        preparedTransport = (pid, handshakeGeneration, surface.ledUpdates[Int(MCU.playNote)],
                             surface.ledUpdates[Int(MCU.recordNote)], snapshot)
        return nil
    }

    public func transportSnapshot() -> TransportSnapshot? {
        guard let pid = environment.runningApp()?.pid else { return nil }
        return read { transportSnapshotLocked($0, pid: pid) }
    }

    public func waitForTransport(playing: Bool, recording: Bool?, timeout: TimeInterval) -> TransportSnapshot? {
        guard let pid = environment.runningApp()?.pid else { return nil }
        let deadline = Date().addingTimeInterval(max(0, timeout))
        cond.lock()
        guard let start = preparedTransport, start.pid == pid else { cond.unlock(); return nil }
        while true {
            guard handshakeGeneration == start.generation,
                  let snapshot = transportSnapshotLocked(surface, pid: pid) else { cond.unlock(); return nil }
            let freshPlay = start.state.playing == playing || surface.ledUpdates[Int(MCU.playNote)] > start.playUpdates
            let freshRecord = recording == nil || start.state.recording == recording ||
                surface.ledUpdates[Int(MCU.recordNote)] > start.recordUpdates
            let matched = snapshot.playing == playing && (recording == nil || snapshot.recording == recording)
            if (matched && freshPlay && freshRecord) || Date() >= deadline {
                cond.unlock()
                return environment.runningApp()?.pid == pid ? snapshot : nil
            }
            _ = cond.wait(until: deadline)
        }
    }

    // MARK: - Banking

    /// Index (0-based, Logic mixer order) of the channel strip shown on surface
    /// strip 1, or nil when unknown. Logic moves the bank by itself (e.g. to
    /// follow the selection), so the value is trusted only while no colour
    /// sysex arrived that we did not cause.
    private var bankOffset: Int?
    private var colorsAtPositioning = -1
    private var generationAtPositioning = -1
    /// The name row as it was when the bank position was last established. Logic can shift the
    /// visible strips without a colour sysex (a delete that clamps the bank: EXP-MCU-023), so a
    /// position is only trusted while the surface still shows what it showed then.
    private var namesAtPositioning: String?

    private func rememberBankSession() {
        let session = read { ($0.colorUpdates, handshakeGeneration) }
        colorsAtPositioning = session.0
        generationAtPositioning = session.1
        namesAtPositioning = read { $0.row(0) }
    }

    private func trackID(_ strip: Int) -> Int { strip + (bankOffset ?? 0) + 1 }

    /// Waits until Logic stops sending surface updates (≥80 ms of silence).
    private func settle() {
        var last = read { ($0.lcdUpdates, $0.colorUpdates) }
        for _ in 0..<25 {
            pause(0.08)
            let now = read { ($0.lcdUpdates, $0.colorUpdates) }
            if now == last { return }
            last = now
        }
    }

    /// Presses a bank/channel button. Returns true if Logic moved the bank:
    /// a move always brings LCD and colour updates and arrives within ~40 ms
    /// (EXP-MCU-020); a no-op press brings nothing. 0.8 s of silence is the
    /// evidence for "did not move", so a slow Logic is not mistaken for the end.
    private func navigate(_ note: UInt8) -> Bool {
        let before = read { ($0.lcdUpdates, $0.colorUpdates) }
        send(MCU.press(note), transient: false)
        let moved = wait(0.8) { $0.lcdUpdates > before.0 || $0.colorUpdates > before.1 }
        if moved { settle() }
        return moved
    }

    /// Bank Left until nothing moves: Logic clamps the bank at 0.
    private func home() -> Bool {
        waitForSteadyLCD()  // a reverting transient must not look like a move
        var presses = 0
        while navigate(MCU.bankLeftNote) {
            presses += 1
            if presses > 512 { return false }
        }
        bankOffset = 0
        rememberBankSession()
        return true
    }

    private var bankIsKnown: Bool {
        bankOffset != nil && read {
            $0.colorUpdates == colorsAtPositioning && handshakeGeneration == generationAtPositioning
                && $0.row(0) == namesAtPositioning
        }
    }

    /// Brings track `track` (1-based, Logic mixer order) onto the surface and
    /// returns its strip. Channel Right moves by one; Logic clamps the bank at
    /// (strip count − 8), so the target ends on strip 8 at most (EXP-MCU-020).
    private enum Positioned { case strip(Int), failed(Outcome) }

    private func position(track: Int) -> Positioned {
        let index = track - 1
        if bankIsKnown, let o = bankOffset, (o..<(o + MCU.strips)).contains(index) {
            return .strip(index - o)
        }
        guard home() else {
            return .failed(.failure("bank_unknown", "MCUが表示するトラックの範囲を先頭へ戻せませんでした"))
        }
        var offset = 0
        while index - offset >= MCU.strips, navigate(MCU.channelRightNote) { offset += 1 }
        bankOffset = offset
        if index - offset >= MCU.strips, navigate(MCU.bankRightNote) {
            // A different button moved the bank: the earlier silence was a missed press, not the end.
            bankOffset = nil
            return .failed(.failure("bank_unknown", "MCUバンクの末尾を確認できませんでした。もう一度実行してください。"))
        }
        rememberBankSession()
        let strip = index - offset
        guard (0..<MCU.strips).contains(strip), !read({ $0.upperText(strip) }).isEmpty else {
            return .failed(.failure("no_such_track", "コントロールサーフェスに \(track) 番のチャンネルストリップがありません。"))
        }
        return .strip(strip)
    }

    private func withStrip(_ track: Int, expectName: String? = nil, _ body: (Int) -> Outcome) -> Outcome {
        switch position(track: track) {
        case .failed(let outcome): return outcome
        case .strip(let strip):
            guard let expected = expectName?.trimmingCharacters(in: .whitespaces) else { return body(strip) }
            let shown = read { $0.upperText(strip) }
            let requested: JSONValue = ["track": .int(track), "expect_name": .string(expected)]
            guard shown == expected else {
                return .failure("target_mismatch",
                                "トラック \(track) の表示名は「\(shown)」で、期待した「\(expected)」と違います。並べ替え・名前変更・追加・削除があった可能性があります。何も送信していません。",
                                requested: requested, observed: ["track": .int(track), "name": .string(shown),
                                                                 "identity_scope": "mixer_position"])
            }
            var outcome = body(strip)
            // Say what was checked, so the agent can see which strip the write reached.
            if outcome.ok, case .object(var result) = outcome.result ?? .object([:]) {
                result["target"] = ["track": .int(track), "name": .string(shown), "matched_expected_name": .bool(true),
                                    "identity_scope": "mixer_position"]
                outcome.result = .object(result)
            }
            return outcome
        }
    }

    // MARK: - Reads (observation contract: docs/observation-contract.md)

    private func sessionJSON() -> JSONValue {
        read { _ in
            ["logic_pid": .int(handshakePID.map(Int.init)),
             "handshake_generation": .int(handshakeGeneration),
             "handshake_at": .string(handshakeAt.map { ISO8601DateFormatter().string(from: $0) }),
             "bank_offset": .int(bankOffset)]
        }
    }

    /// Completeness, freshness and source of a read. `complete: false` means the
    /// result must not be treated as the whole truth about `scope`.
    private func observation(scope: String, complete: Bool, extra: [String: JSONValue] = [:]) -> JSONValue {
        var o: [String: JSONValue] = [
            "source": .string(BackendKind.mcu.rawValue),
            "scope": .string(scope),
            "complete": .bool(complete),
            "observed_at": .string(ISO8601DateFormatter().string(from: Date())),
            "session": sessionJSON(),
        ]
        for (key, value) in extra { o[key] = value }
        return .object(o)
    }

    private func status() -> Outcome {
        let logic = environment.runningApp()
        let connected = logic != nil && isConnected
        var result: [String: JSONValue] = [
            "daemon": ["pid": .int(Int(getpid()))],
            "logic": logic?.json ?? ["running": false],
            // Which Logic build / macOS this was checked on; unlisted ones are unverified, not blocked.
            "compatibility": CompatibilityProfile.assess(logic: logic),
            "mcu": ["port": .string(Self.portName), "connected": .bool(connected),
                    "handshake_at": .string(read { _ in handshakeAt }.map { ISO8601DateFormatter().string(from: $0) })],
        ]
        if connected {
            result["transport"] = transportJSON()
            // Raw surface LCD, for diagnosing readback problems.
            result["mcu_lcd"] = read { s in [.string(s.row(0)), .string(s.row(1))] }
        }
        return Outcome(ok: true, result: .object(result),
                       observation: observation(scope: "status", complete: connected))
    }

    /// The playhead as Logic's time display shows it at the moment of reading (it moves while playing).
    /// `display` is the text as shown. In BEATS mode it is also split by the display's layout (3-2-2-3
    /// digits: bar, beat, division, tick); that split was checked against one stopped value only
    /// (EXP-MCU-009/024 logs). `null` until Logic has reported all ten digits in this session, and again
    /// after the mode changes until the digits are re-sent. Logic sends only the digits that change, so a
    /// read during an update can mix old and new digits: it is a reading of the display, not an atomic value.
    private func positionJSON() -> JSONValue {
        read { s -> JSONValue in
            guard let chars = s.timecodeCharacters() else { return .null }
            let display = String(chars.map { $0.dot ? "\($0.character)." : String($0.character) }.joined())
            let mode = s.timeDisplayMode
            var o: [String: JSONValue] = ["display": .string(display),
                                          "mode": mode == MCU.beatsNote ? "beats" : mode == MCU.smpteNote ? "smpte" : .null]
            // Both LEDs on (or neither) is a contradiction or a switch in progress: no mode, no split.
            if mode == MCU.beatsNote {
                let digits = chars.map(\.character)
                func group(_ r: Range<Int>) -> JSONValue {
                    Int(String(digits[r]).trimmingCharacters(in: .whitespaces)).map { .int($0) } ?? .null
                }
                o["bar"] = group(0..<3); o["beat"] = group(3..<5); o["division"] = group(5..<7); o["tick"] = group(7..<10)
            }
            return .object(o)
        }
    }

    /// `null` = Logic has not reported the LED in this session. It is never `false`.
    private func transportJSON() -> JSONValue {
        read { s in ["playing": .bool(s.ledIfKnown(MCU.playNote)), "recording": .bool(s.ledIfKnown(MCU.recordNote))] }
    }

    private func state() -> Outcome {
        let scan = scanTracks()
        // With a complete scan, "no strip selected" is a real answer (null). An
        // incomplete scan cannot say, so the field is null there too and
        // observation.complete tells them apart.
        let selected: JSONValue = scan.complete
            ? (scan.tracks.first { $0["selected"] == .bool(true) }?["id"] ?? .null) : .null
        return Outcome(ok: scan.complete,
                       result: ["transport": transportJSON(), "position": positionJSON(), "selected_track": selected,
                                "tracks": .array(scan.tracks)],
                       error: scan.error, message: scan.message,
                       observation: observation(scope: "mixer_strips", complete: scan.complete, extra: scan.extra))
    }

    private struct Scan {
        var tracks: [JSONValue] = []
        var complete = false
        var error: String?
        var message: String?
        var extra: [String: JSONValue] = [:]
    }

    /// Visits every channel strip in Logic's mixer order: home, then Channel
    /// Right until the end is *confirmed* by a second, different button (Bank
    /// Right) also producing no update. A scan that cannot prove it saw every
    /// strip is returned incomplete, never as a shorter or empty success.
    /// Volume comes from the fader position through Logic's own table (exact to
    /// the LCD's 0.1 dB, SA-001) so no fader is touched.
    private func scanTracks() -> Scan {
        var last = Scan()
        for attempt in 1...2 {
            var scan = Scan()
            guard home() else {
                scan.error = "bank_home_failed"
                scan.message = "MCUバンクを先頭に戻せませんでした。Logicがバンクを動かし続けている可能性があります。"
                scan.extra = ["attempts": .int(attempt)]
                last = scan
                continue
            }
            var seen = Set<Int>()
            var steps = 0
            var expectedColours = read { $0.colorUpdates }
            var problem: String?
            while true {
                let viewStart = scan.tracks.count
                for strip in 0..<MCU.strips where !seen.contains(trackID(strip)) {
                    guard !read({ $0.upperText(strip) }).isEmpty else { continue }
                    seen.insert(trackID(strip))
                    scan.tracks.append(trackInfo(strip, readVolume: false))
                }
                if read({ $0.colorUpdates }) != expectedColours {
                    // Logic moved the bank itself while this view was being read: its ids may be wrong.
                    scan.tracks.removeSubrange(viewStart...)
                    problem = "bank_moved_externally"
                    break
                }
                let coloursBefore = read { $0.colorUpdates }
                if navigateRight() {
                    // Logic sends exactly one colour sysex per move (EXP-MCU-020); more means a
                    // second, unrelated move landed together with ours and the offset is lost.
                    if read({ $0.colorUpdates }) != coloursBefore + 1 {
                        problem = "bank_moved_externally"
                        break
                    }
                    steps += 1
                    expectedColours = read { $0.colorUpdates }
                    continue
                }
                if navigate(MCU.bankRightNote) {
                    problem = "end_not_confirmed"
                    break
                }
                break
            }
            if let problem {
                bankOffset = nil
                scan.error = "scan_incomplete"
                scan.message = problem == "bank_moved_externally"
                    ? "走査中にLogicがMCUバンクを動かしたため、一覧を確定できません。"
                    : "一覧の末尾を確認できませんでした。一覧は途中までです。"
                scan.extra = ["attempts": .int(attempt), "problem": .string(problem)]
                last = scan
                continue
            }
            scan.complete = true
            scan.tracks = Self.markNameUniqueness(scan.tracks)
            scan.extra = ["strips": .int(scan.tracks.count), "bank_steps": .int(steps), "attempts": .int(attempt),
                          "end": "channel_right_and_bank_right_silent"]
            rememberBankSession()
            return scan
        }
        return last
    }

    /// Only a complete scan can say a name is unique: an unseen strip could share it. The LCD
    /// shows a shortened name, so two different tracks can look the same here (and count as not unique).
    static func markNameUniqueness(_ tracks: [JSONValue]) -> [JSONValue] {
        var counts: [String: Int] = [:]
        for track in tracks { if case .string(let name)? = track["name"] { counts[name, default: 0] += 1 } }
        return tracks.map { track in
            guard case .object(var object) = track, case .string(let name)? = object["name"],
                  case .object(var identity)? = object["identity"] else { return track }
            identity["name_unique"] = .bool(counts[name] == 1)
            object["identity"] = .object(identity)
            return .object(object)
        }
    }

    private func navigateRight() -> Bool {
        guard navigate(MCU.channelRightNote) else { return false }
        bankOffset = (bankOffset ?? 0) + 1
        return true
    }

    /// Waits until the strip's lower LCD cell shows a pan value again. After a
    /// select Logic shows the track name there for up to ~3 s (EXP-MCU-012,
    /// logicctl run 2026-10-01). An empty cell (e.g. Master) has no pan.
    private func waitForPanDisplay(_ strip: Int) {
        waitForSteadyLCD()
        if wait(3, until: { parseLCDPan($0.lowerText(strip)) != nil || $0.lowerText(strip).isEmpty }),
           read({ $0.lowerText(strip).isEmpty }) {
            // Empty right after a bank move may still be filled in; Master stays empty.
            wait(0.5) { parseLCDPan($0.lowerText(strip)) != nil }
        }
    }

    /// One strip. A value Logic has not reported in this session is `null` and is
    /// listed in `unknown`; a value that does not exist for this strip (Master
    /// has no pan) is `null` and listed in `unavailable`. `null` is never `false`/0.
    private func trackInfo(_ strip: Int, readVolume withVolume: Bool) -> JSONValue {
        waitForPanDisplay(strip)
        var unknown: [JSONValue] = []
        var unavailable: [JSONValue] = []
        var o: [String: JSONValue] = read { s in
            func flag(_ name: String, _ note: UInt8) -> JSONValue {
                guard let value = s.ledIfKnown(note) else { unknown.append(.string(name)); return .null }
                return .bool(value)
            }
            let name = s.upperText(strip)
            let cell = s.lowerText(strip)
            let pan = parseLCDPan(cell)
            if pan == nil { (cell.isEmpty ? { unavailable.append("pan") } : { unknown.append("pan") })() }
            // Logic blinks the mute LED of strips muted implicitly by a solo (also one on another bank).
            let soloActive = s.anySoloActive || s.ledIfKnown(MCU.rudeSoloNote) == true
            var o: [String: JSONValue] = [
                "id": .int(trackID(strip)),
                "mcu_strip": .int(strip + 1),
                "name": .string(name),
                "name_may_be_truncated": .bool(name.count >= 6),
                // `id` is the mixer position, valid only until a track is added, removed or moved.
                // `name_unique` is filled in by a complete scan; a single read cannot know it.
                "identity": ["scope": "mixer_position", "stable_across_reorder": .bool(false), "name_unique": .null],
                "solo": flag("solo", MCU.soloNote(strip)),
                "selected": flag("selected", MCU.selectNote(strip)),
                "rec_armed": flag("rec_armed", MCU.recNote(strip)),
                "pan": pan.map { .number(Double($0) / 64) } ?? .null,
                "pan_raw": .int(pan),
            ]
            if soloActive {
                unknown.append("mute")
                o["mute"] = .null
                o["mute_note"] = "ソロ中はミュートLEDが点滅するため、状態を確定できません"
            } else {
                o["mute"] = flag("mute", MCU.muteNote(strip))
            }
            return o
        }
        let (db, source) = withVolume
            ? readVolume(strip)
            : (read { $0.faders[strip] }.map(FaderCalibration.db(forValue:)), "fader")
        if db == nil { unknown.append("volume_db") }
        o["volume_db"] = .db(db.map { $0.isFinite ? ($0 * 10).rounded() / 10 : $0 })
        o["volume_source"] = .string(source)
        o["unknown"] = .array(unknown)
        o["unavailable"] = .array(unavailable)
        return .object(o)
    }

    /// Exact dB via fader touch: Logic prints the current value on the LCD.
    private func readVolume(_ strip: Int) -> (Double?, String) {
        let before = read { $0.lowerWrites[strip] }
        send([[0x90, MCU.touchNote(strip), 0x7F]])
        wait(0.3) { $0.lowerWrites[strip] > before }
        let (text, fader) = read { ($0.dbText(strip), $0.faders[strip]) }
        send([[0x90, MCU.touchNote(strip), 0x00]])
        if let db = parseLCDDecibels(text) { return (db, "lcd") }
        return (fader.map { (FaderCalibration.db(forValue: $0) * 10).rounded() / 10 }, "fader_estimate")
    }

    // MARK: - Debug

    private func debugMCU(_ messages: [[UInt8]]) -> Outcome {
        let before = read { $0.lcdUpdates }
        send(messages)
        wait(0.4) { $0.lcdUpdates > before }
        pause(0.2)
        return Outcome(ok: true, result: read { s in
            ["sent": .array(messages.map { .string(hex($0)) }),
             "lcd": [.string(s.row(0)), .string(s.row(1))],
             "faders": .array(s.faders.map { .int($0) }),
             "leds_on": .array((0..<128).filter { s.leds[$0] != 0 }.map { .int($0) })]
        })
    }

    // MARK: - Writes

    private func transport(play: Bool) -> Outcome {
        let requested: JSONValue = ["playing": .bool(play)]
        // Logic reports the transport LEDs in its state dump after the handshake. A missing
        // report is unknown, not "off": without evidence nothing is sent or verified.
        guard wait(1.0, until: { $0.ledIfKnown(MCU.playNote) != nil && $0.ledIfKnown(MCU.recordNote) != nil }) else {
            return .failure("readback_unavailable",
                            "再生・録音の状態をLogicから受信していません。状態が不明なため、何も送信していません。",
                            requested: requested)
        }
        let (playing, recording) = read { ($0.led(MCU.playNote), $0.led(MCU.recordNote)) }
        // A second Stop moves the playhead to the start, so never send Stop when already stopped.
        if playing == play && !(recording && !play) {
            return .write(matched: true, requested: requested, observed: ["playing": .bool(playing)],
                          message: "既に要求どおりの状態です。送信していません。")
        }
        send(MCU.press(play ? MCU.playNote : MCU.stopNote))
        let ok = wait(1.0) { $0.led(MCU.playNote) == play }
        return .write(matched: ok, requested: requested, observed: transportJSON())
    }

    private func select(_ strip: Int) -> Outcome {
        let requested: JSONValue = ["selected_track": .int(trackID(strip))]
        func observed() -> JSONValue {
            read { s in ["selected_track": .int((0..<MCU.strips).first { s.led(MCU.selectNote($0)) }.map(trackID))] }
        }
        if read({ $0.led(MCU.selectNote(strip)) }) {
            return .write(matched: true, requested: requested, observed: observed(),
                          message: "既に選択されています。送信していません。")
        }
        send(MCU.press(MCU.selectNote(strip)))
        let ok = wait(0.5) { $0.led(MCU.selectNote(strip)) }
        return .write(matched: ok, requested: requested, observed: observed(),
                      message: "自動録音待機が有効な場合、選択に合わせて録音待機も移動します。")
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
        let requested: JSONValue = ["track": .int(trackID(strip)), kind.key: .bool(on)]
        let note = kind.note(strip)
        // While a solo is active the mute LED blinks for implied mutes, so it is not the mute state.
        let ledTrustworthy = { (s: MCUSurface) in kind == .solo || !s.anySoloActive }
        // Only a reported LED proves "already in that state"; an unreported one is not "off".
        if read({ ledTrustworthy($0) && $0.ledIfKnown(note) == on }) {
            return .write(matched: true, requested: requested,
                          observed: ["track": .int(trackID(strip)), kind.key: .bool(on)],
                          message: "既に要求どおりの状態です。送信していません。")
        }
        var observedState: Bool?
        let session = read { _ in handshakeGeneration }
        for attempt in 0..<2 {
            if attempt > 0, let changed = stillSession(session, before: "repress") { return changed }
            let before = read { $0.lowerWrites[strip] }
            send(MCU.press(note))
            wait(0.5) { $0.lowerWrites[strip] > before }
            // Every piece of evidence is read together with the session it belongs to.
            let (generation, text, trusted) = read { s in (handshakeGeneration, s.lowerText(strip), ledTrustworthy(s)) }
            guard generation == session else { return sessionChangedOutcome() }
            observedState = kind.state(fromLCD: text)
            if observedState == nil, trusted {
                wait(0.3) { $0.led(note) == on }
                let (later, led) = read { s in (handshakeGeneration, s.led(note)) }
                guard later == session else { return sessionChangedOutcome() }
                observedState = led
            }
            // The starting state was unknown (blinking LED) and the toggle went the wrong way.
            if observedState != on && observedState != nil { continue }
            break
        }
        var matched = observedState == on
        if matched, read(ledTrustworthy) {
            wait(0.5) { $0.led(note) == on }
            let (generation, led) = read { s in (handshakeGeneration, s.led(note)) }
            guard generation == session else { return sessionChangedOutcome() }
            matched = led == on
        }
        return .write(matched: matched, requested: requested,
                      observed: ["track": .int(trackID(strip)), kind.key: .bool(observedState)])
    }

    /// After a button was pressed: if Logic re-ran the handshake, the state now shown belongs to another session,
    /// so neither "verified" nor another press is safe. The result is unknown (not a "nothing was sent" refusal).
    private func sessionChangedOutcome() -> Outcome {
        .failure("session_changed",
                 "ボタンを押した後に Logic との接続が切り替わりました。操作の結果は不明です。状態を読み直してください。")
    }

    /// Right before pressing again: nil while still in `session`. A reconnect in the instant between this check
    /// and the send cannot be excluded without holding the lock across the send (a synchronous fake would
    /// deadlock); it is then caught after the wait, and the result is session_changed, never verified.
    private func stillSession(_ session: Int, before point: String) -> Outcome? {
        testHook?("before-\(point)")
        let changed = read({ _ in handshakeGeneration }) != session
        testHook?("after-check-\(point)")
        return changed ? sessionChangedOutcome() : nil
    }

    /// Record-enable through the strip's REC button. Logic shows no text for it, so the REC LED is the only
    /// evidence. A strip that cannot be armed (an output, Master) leaves the LED as it was: verification fails.
    private func arm(_ strip: Int, on: Bool) -> Outcome {
        let requested: JSONValue = ["track": .int(trackID(strip)), "rec_armed": .bool(on)]
        let note = MCU.recNote(strip)
        func observed(_ state: Bool?) -> JSONValue { ["track": .int(trackID(strip)), "rec_armed": .bool(state)] }
        // Only a reported LED proves "already in that state"; an unreported one is not "off".
        if read({ $0.ledIfKnown(note) == on }) {
            return .write(matched: true, requested: requested, observed: observed(on),
                          message: "既に要求どおりの状態です。送信していません。")
        }
        var state: Bool?
        let session = read { _ in handshakeGeneration }
        // The button toggles. With an unknown starting state the first press may go the wrong way: one more try.
        for attempt in 0..<2 {
            if attempt > 0, let changed = stillSession(session, before: "repress") { return changed }
            let before = read { $0.ledUpdates[Int(note)] }
            send(MCU.press(note))
            wait(0.8) { $0.ledUpdates[Int(note)] > before }
            // The evidence and the session it belongs to, read together.
            let (generation, led, updates) = read { s in (handshakeGeneration, s.ledIfKnown(note), s.ledUpdates[Int(note)]) }
            guard generation == session else { return sessionChangedOutcome() }
            state = led
            if state == nil || state == on || updates == before { break }
        }
        let matched = state == on
        return .write(matched: matched, requested: requested, observed: observed(state),
                      message: matched ? nil : "録音待機の LED が要求どおりになりませんでした。出力や Master など、録音待機できないストリップの可能性があります。")
    }

    private func volume(_ strip: Int, db target: Double, tolerance: Double) -> Outcome {
        let requested: JSONValue = ["track": .int(trackID(strip)), "volume_db": .db(target)]
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
            guard let obs = parseLCDDecibels(read { $0.dbText(strip) }) else { break }
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
        let obs = parseLCDDecibels(read { $0.dbText(strip) }) ?? best?.db
        let fader = read { $0.faders[strip] }
        return .write(matched: obs.map { error($0) <= tolerance + 1e-9 } ?? false, requested: requested,
                      observed: ["track": .int(trackID(strip)), "volume_db": .db(obs), "fader_value": .int(fader)],
                      message: obs == nil ? "MCUの表示から音量（dB）を確認できませんでした" : nil)
    }

    private func pan(_ strip: Int, normalized: Double) -> Outcome {
        let target = max(-64, min(63, Int((normalized * 64).rounded())))
        let requested: JSONValue = ["track": .int(trackID(strip)), "pan": .number(normalized), "pan_raw": .int(target)]
        func observed(_ raw: Int?) -> JSONValue {
            ["track": .int(trackID(strip)), "pan": raw.map { .number(Double($0) / 64) } ?? .null, "pan_raw": .int(raw)]
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
            return .failure("readback_unavailable", "MCUの表示からパンの値を確認できませんでした。",
                            requested: requested)
        }
        if now == target {
            return .write(matched: true, requested: requested, observed: observed(now),
                          message: "既に要求どおりの状態です。送信していません。")
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
