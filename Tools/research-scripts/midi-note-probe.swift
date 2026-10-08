// Generic MIDI-note input probe. Research only; no MCU handshake or connections.
//
//   swift Tools/research-scripts/midi-note-probe.swift --bpm 120 --timeout 60
//   # Arm recording in LogicCLI-Test, then send "start\n" through the PTY.
//   # "cancel\n", SIGINT, SIGTERM, or SIGHUP cancels with note-off cleanup.
//
//   swift Tools/research-scripts/midi-note-probe.swift --wait-file /tmp/note-start
//   # The file must initially be absent. Create it after arming Logic.
//
// Stopped region input: prepare a selected test MIDI region and quarter-note
// Step Input length, create this source READY, then switch MIDI In OFF -> ON:
//   swift Tools/research-scripts/midi-note-probe.swift --mode step --step-gap-ms 50 --wait-file /tmp/fresh-step-gate
//   # Create the initially absent gate only after preparation and readback.
// 50 ms spacing was observed to preserve eight sequential notes at 120/80 BPM.
// Zero/20 ms grouped notes in the tested Logic build; throughput is not guaranteed.
// The 250 ms final delivery grace is separate from the measured TX span.
//
// JSON lines on stdout; diagnostics on stderr. This only creates a virtual source
// named logicctl-note-input. CoreMIDI TX success does not verify Logic reception.
// MIDIReceived requires proper host timestamps: zero does NOT mean "now".
import CoreMIDI
import Foundation
import Dispatch
import Darwin

struct ProbeOptions {
    var mode = "realtime"
    var stepGapMs: Double = 50
    var bpm: Double = 120
    var timeout: Double = 60
    var waitFile: String?

    static func parse(_ arguments: [String]) throws -> ProbeOptions {
        var options = ProbeOptions()
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--mode":
                index += 1
                guard index < arguments.count,
                      ["realtime", "step"].contains(arguments[index]) else {
                    throw ProbeError.argument("--mode must be realtime or step")
                }
                options.mode = arguments[index]
            case "--bpm":
                index += 1
                guard index < arguments.count,
                      let bpm = Double(arguments[index]), bpm.isFinite,
                      bpm >= 20, bpm <= 999 else {
                    throw ProbeError.argument("--bpm must be between 20 and 999")
                }
                options.bpm = bpm
            case "--step-gap-ms":
                index += 1
                guard index < arguments.count,
                      let gap = Double(arguments[index]), gap.isFinite,
                      gap >= 0, gap <= 1000 else {
                    throw ProbeError.argument("--step-gap-ms must be between 0 and 1000")
                }
                options.stepGapMs = gap
            case "--timeout":
                index += 1
                guard index < arguments.count,
                      let seconds = Double(arguments[index]), seconds.isFinite,
                      seconds > 0, seconds <= 60 else {
                    throw ProbeError.argument("--timeout must be greater than 0 and at most 60 seconds")
                }
                options.timeout = seconds
            case "--wait-file":
                index += 1
                guard index < arguments.count, !arguments[index].isEmpty else {
                    throw ProbeError.argument("--wait-file requires a path")
                }
                options.waitFile = URL(fileURLWithPath: arguments[index]).standardizedFileURL.path
            default:
                throw ProbeError.argument("unknown argument: \(arguments[index])")
            }
            index += 1
        }
        return options
    }
}

enum ProbeError: Error, CustomStringConvertible {
    case argument(String)
    case midi(String, OSStatus)
    var description: String {
        switch self {
        case .argument(let message): return message
        case .midi(let operation, let status): return "\(operation): OSStatus \(status)"
        }
    }
}

// All mutable state is used on the initial/main dispatch queue. The stdin reader
// only forwards immutable lines to that queue. No CoreMIDI calls occur on it.
final class NoteProbe: @unchecked Sendable {
    let sourceName = "logicctl-note-input"
    let notes: [UInt8] = [60, 62, 64, 67, 64, 62, 60, 55]
    let channel: UInt8 = 0
    let velocity: UInt8 = 90
    let durationBeats: Double = 0.75
    var beatSeconds: Double { 60 / options.bpm }
    var durationSeconds: Double { durationBeats * beatSeconds }
    let options: ProbeOptions
    let iso: ISO8601DateFormatter
    var client = MIDIClientRef()
    var source = MIDIEndpointRef()
    var playing = false
    var finished = false
    var activeNotes = Set<UInt8>()
    var startedAt: UInt64?
    var startedHostAt: UInt64?
    var firstNoteOnHostAt: UInt64?
    var lastNoteOffHostAt: UInt64?
    var timebase = mach_timebase_info_data_t()
    var sentOns = 0
    var sentOffs = 0
    var gateTimeout: DispatchSourceTimer?
    var filePoll: DispatchSourceTimer?
    var signalSources: [DispatchSourceSignal] = []
    var scheduled: [DispatchSourceTimer] = []

    init(_ options: ProbeOptions) {
        self.options = options
        iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func log(_ event: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = event
        record["utc"] = iso.string(from: Date())
        record["verified"] = false
        if let start = startedAt {
            record["elapsed_seconds"] = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else {
            FileHandle.standardError.write(Data("could not serialize probe log\n".utf8))
            return
        }
        FileHandle.standardOutput.write(data + Data([0x0a]))
    }

    func run() throws -> Never {
        guard mach_timebase_info(&timebase) == KERN_SUCCESS,
              timebase.numer > 0, timebase.denom > 0 else {
            throw ProbeError.argument("mach_timebase_info failed")
        }
        for number in [SIGINT, SIGTERM, SIGHUP] {
            Darwin.signal(number, SIG_IGN)
            let signalSource = DispatchSource.makeSignalSource(signal: number, queue: .main)
            signalSource.setEventHandler { [weak self] in
                self?.finish("interrupted", code: 128 + number, fields: ["signal": number])
            }
            signalSources.append(signalSource)
            signalSource.resume()
        }
        if let path = options.waitFile, FileManager.default.fileExists(atPath: path) {
            throw ProbeError.argument("wait-file already exists; use a fresh absent gate file")
        }
        // Avoid an ambiguous duplicate virtual source from an earlier probe.
        for index in 0..<MIDIGetNumberOfSources() {
            var name: Unmanaged<CFString>?
            let endpoint = MIDIGetSource(index)
            if MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr,
               let existing = name?.takeRetainedValue(), existing as String == sourceName {
                throw ProbeError.argument("source \(sourceName) already exists")
            }
        }
        var status = MIDIClientCreateWithBlock("logicctl-note-probe" as CFString, &client) { _ in }
        guard status == noErr else { throw ProbeError.midi("MIDIClientCreateWithBlock", status) }
        status = MIDISourceCreate(client, sourceName as CFString, &source)
        guard status == noErr else { throw ProbeError.midi("MIDISourceCreate", status) }

        let timeout = DispatchSource.makeTimerSource(queue: .main)
        timeout.schedule(deadline: .now() + options.timeout)
        timeout.setEventHandler { [weak self] in self?.finish("gate_timeout", code: 2) }
        gateTimeout = timeout
        timeout.resume()

        log("ready", ["source_name": sourceName, "source_ref": source,
                       "gate": options.waitFile == nil ? "stdin line: start or cancel" : "fresh file existence",
                       "wait_file": options.waitFile as Any? ?? NSNull(),
                       "gate_timeout_seconds": options.timeout, "mode": options.mode,
                       "bpm": options.mode == "realtime" ? options.bpm as Any : NSNull(),
                       "bpm_scope": "realtime mode only",
                       "channel": Int(channel), "velocity": Int(velocity),
                       "notes": notes.map(Int.init),
                       "beat_seconds": options.mode == "realtime" ? beatSeconds as Any : NSNull(),
                       "note_duration_seconds": options.mode == "realtime" ? durationSeconds as Any : NSNull(),
                       "duration_beats": options.mode == "realtime" ? durationBeats as Any : NSNull(),
                       "step_gap_ms": options.mode == "step" ? options.stepGapMs as Any : NSNull(),
                       "planned_tx_span_seconds": options.mode == "step" ? Double(notes.count - 1) * options.stepGapMs / 1000 : Double(notes.count - 1) * beatSeconds + durationSeconds,
                       "total_seconds": options.mode == "realtime" ? Double(notes.count) * beatSeconds : Double(notes.count - 1) * options.stepGapMs / 1000 + 0.25,
                       "note_duration_control": options.mode == "realtime" ? "sender timestamps" : "Logic Step Input Note Length",
                       "scheduler": options.mode == "realtime" ? "strict DispatchSourceTimer, zero leeway, shared base" : "immediate note pairs; strict timer gap; final 0.25s delivery grace",
                       "packet_timestamp_mode": "mach_absolute_time sampled before MIDIReceived",
                       "mach_timebase_numer": timebase.numer, "mach_timebase_denom": timebase.denom,
                       "destination_created": false, "port_connections_created": false])

        if let path = options.waitFile {
            let poll = DispatchSource.makeTimerSource(queue: .main)
            poll.schedule(deadline: .now(), repeating: .milliseconds(50))
            poll.setEventHandler { [weak self] in
                if FileManager.default.fileExists(atPath: path) { self?.start("wait_file") }
            }
            filePoll = poll
            poll.resume()
        } else {
            Thread.detachNewThread { [self] in
                while let line = readLine() {
                    let command = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    DispatchQueue.main.async { [self] in
                        if command == "start" { start("stdin") }
                        else if command == "cancel" || command == "quit" { finish("cancelled", code: 2) }
                        else { log("ignored_gate_line") }
                    }
                }
                DispatchQueue.main.async { [self] in
                    if !playing && !finished { finish("stdin_eof_before_start", code: 2) }
                }
            }
        }
        dispatchMain()
    }

    func start(_ gate: String) {
        guard !playing && !finished else { return }
        playing = true
        gateTimeout?.cancel()
        filePoll?.cancel()
        startedAt = DispatchTime.now().uptimeNanoseconds
        startedHostAt = mach_absolute_time()
        log("started", ["gate": gate, "mode": options.mode])
        if options.mode == "step" {
            sendStepPair(0)
            return
        }
        let base = DispatchTime.now()
        for (index, note) in notes.enumerated() {
            let offset = Double(index) * beatSeconds
            schedule(base + offset) { [self] in
                activeNotes.insert(note) // Retain for cleanup even if TX status is uncertain.
                if transmit(note, on: true, index: index, planned: offset, cleanup: false) {
                    sentOns += 1
                } else {
                    finish("tx_error", code: 1)
                }
            }
            schedule(base + offset + durationSeconds) { [self] in
                if transmit(note, on: false, index: index, planned: offset + durationSeconds, cleanup: false) {
                    activeNotes.remove(note)
                    sentOffs += 1
                } else {
                    finish("tx_error", code: 1)
                }
            }
        }
        schedule(base + Double(notes.count) * beatSeconds) { [self] in
            finish("completed", code: 0)
        }
    }

    func sendStepPair(_ index: Int) {
        guard playing && !finished && index < notes.count else { return }
        let note = notes[index]
        activeNotes.insert(note)
        guard transmit(note, on: true, index: index, planned: nil, cleanup: false) else {
            finish("tx_error", code: 1)
            return
        }
        sentOns += 1
        guard transmit(note, on: false, index: index, planned: nil, cleanup: false) else {
            finish("tx_error", code: 1)
            return
        }
        activeNotes.remove(note)
        sentOffs += 1
        if index + 1 < notes.count {
            schedule(.now() + options.stepGapMs / 1000) { [self] in sendStepPair(index + 1) }
        } else {
            // Receiver delivery grace begins after the final pair.
            schedule(.now() + 0.25) { [self] in finish("completed", code: 0) }
        }
    }

    func schedule(_ deadline: DispatchTime, action: @escaping @Sendable () -> Void) {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: .main)
        timer.schedule(deadline: deadline, leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.playing && !self.finished else { return }
            action()
        }
        scheduled.append(timer)
        timer.resume()
    }

    @discardableResult
    func transmit(_ note: UInt8, on: Bool, index: Int?, planned: Double?, cleanup: Bool) -> Bool {
        guard source != 0 else { return false }
        let bytes: [UInt8] = [(on ? 0x90 : 0x80) | channel, note, on ? velocity : 0]
        let hostTimestamp = mach_absolute_time()
        var list = MIDIPacketList()
        let packet = MIDIPacketListInit(&list)
        let added = bytes.withUnsafeBufferPointer { buffer in
            MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, hostTimestamp,
                             buffer.count, buffer.baseAddress!)
        }
        let callPre = DispatchTime.now().uptimeNanoseconds
        let status: OSStatus = added == nil ? -1 : MIDIReceived(source, &list)
        let callPost = DispatchTime.now().uptimeNanoseconds
        if status == noErr && !cleanup {
            if on && firstNoteOnHostAt == nil { firstNoteOnHostAt = hostTimestamp }
            if !on { lastNoteOffHostAt = hostTimestamp }
        }
        var fields: [String: Any] = ["direction": "TX", "kind": on ? "note_on" : "note_off",
                                     "bytes": bytes.map(Int.init), "note": Int(note),
                                     "channel": Int(channel), "velocity": on ? Int(velocity) : 0,
                                     "os_status": status, "cleanup": cleanup,
                                     "packet_host_timestamp": hostTimestamp,
                                     "call_pre_monotonic_ns": callPre, "call_post_monotonic_ns": callPost,
                                     "call_duration_ms": Double(callPost - callPre) / 1_000_000]
        if let hostStart = startedHostAt {
            fields["packet_timestamp_elapsed_seconds"] = Double(hostTimestamp - hostStart)
                * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        }
        if let start = startedAt {
            fields["call_pre_elapsed_seconds"] = Double(callPre - start) / 1_000_000_000
            fields["call_post_elapsed_seconds"] = Double(callPost - start) / 1_000_000_000
        }
        if let index = index { fields["note_index"] = index }
        if let planned = planned { fields["planned_offset_seconds"] = planned }
        log("tx", fields)
        return status == noErr
    }

    func finish(_ reason: String, code: Int32, fields: [String: Any] = [:]) {
        guard !finished else { return }
        finished = true
        gateTimeout?.cancel()
        filePoll?.cancel()
        scheduled.forEach { $0.cancel() }
        for note in activeNotes.sorted() {
            if transmit(note, on: false, index: nil, planned: nil, cleanup: true) {
                activeNotes.remove(note)
            }
        }
        let endpointStatus: OSStatus = source == 0 ? noErr : MIDIEndpointDispose(source)
        source = 0
        let clientStatus: OSStatus = client == 0 ? noErr : MIDIClientDispose(client)
        client = 0
        let cleanupFailed = !activeNotes.isEmpty || endpointStatus != noErr || clientStatus != noErr
        let finalCode: Int32 = code == 0 && cleanupFailed ? 1 : code
        var result = fields
        result["reason"] = reason
        result["note_on_successes"] = sentOns
        result["note_off_successes"] = sentOffs
        result["unconfirmed_cleanup_notes"] = activeNotes.sorted().map(Int.init)
        result["endpoint_dispose_status"] = endpointStatus
        result["client_dispose_status"] = clientStatus
        result["exit_code"] = finalCode
        if let first = firstNoteOnHostAt, let last = lastNoteOffHostAt, last >= first {
            result["tx_span_seconds"] = Double(last - first)
                * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        }
        log("finished", result)
        if finalCode != 0 {
            FileHandle.standardError.write(Data("midi-note-probe: \(reason)\n".utf8))
        }
        Darwin.exit(finalCode)
    }
}

if CommandLine.arguments.dropFirst().contains("--help") {
    let usage: [String: Any] = ["usage": "swift Tools/research-scripts/midi-note-probe.swift [--mode realtime|step] [--step-gap-ms 0..1000] [--bpm 20..999] [--timeout 1..60] [--wait-file absent-path]",
                                 "stdin_gate": "start or cancel followed by newline",
                                 "source": "logicctl-note-input", "notes": [60, 62, 64, 67, 64, 62, 60, 55],
                                 "default_mode": "realtime", "default_step_gap_ms": 50,
                                 "step": "immediate pairs; configurable strict timer gap; Logic Note Length; final 0.25s grace",
                                 "default_bpm": 120, "channel": 0, "velocity": 90,
                                 "duration_beats": 0.75, "beat_seconds_formula": "60 / bpm"]
    let data = try JSONSerialization.data(withJSONObject: usage, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data([0x0a]))
    Darwin.exit(0)
}

var probe: NoteProbe?
do {
    let options = try ProbeOptions.parse(Array(CommandLine.arguments.dropFirst()))
    let instance = NoteProbe(options)
    probe = instance
    try instance.run()
} catch {
    FileHandle.standardError.write(Data("midi-note-probe: \(error)\n".utf8))
    if let instance = probe {
        instance.log("error", ["message": String(describing: error)])
        instance.finish("setup_error", code: 1)
    }
    Darwin.exit(1)
}
