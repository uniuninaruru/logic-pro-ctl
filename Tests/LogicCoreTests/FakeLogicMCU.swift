import Foundation
@testable import LogicCore

/// A stand-in for Logic's Mackie Control surface, built from what the real
/// Logic 12.3.1 does (EXP-MCU-001…020): a handshake and state dump, bank
/// clamping, silence for a no-op press, one colour sysex per bank move.
/// It answers synchronously inside `handle`, so tests are deterministic.
final class FakeLogicMCU {
    struct Strip {
        var name: String
        var mute = false
        var solo = false
        var rec = false
        var fader = 12441
        var pan = 0
        var hasPan = true
    }

    var strips: [Strip]
    var offset = 0
    var selected = 0
    var playing = false
    var recording = false
    weak var backend: MCUBackend?

    // Fault injection ---------------------------------------------------
    /// Swallow this many Channel Right presses (a lost MIDI message).
    var dropChannelRight = 0
    var dropAllChannelRight = false
    /// Answer every Bank Left, even at the start (Logic never settles).
    var alwaysMoveOnBankLeft = false
    /// On this navigation press, send the colour sysex twice (a second,
    /// unrelated bank move landed together with ours).
    var duplicateColourOnNavigation: Int?
    var alwaysDuplicateColour = false
    /// Do not send LED states in the state dump.
    var withholdLEDDump = false
    var withholdTransportLEDs = false

    // Observations ------------------------------------------------------
    private(set) var presses: [UInt8] = []
    private var navigations = 0

    init(names: [String]) {
        strips = names.enumerated().map { index, name in
            var strip = Strip(name: name)
            strip.hasPan = name != "Master"
            _ = index
            return strip
        }
    }

    static func project(tracks: Int) -> FakeLogicMCU {
        let names = (1...tracks).map { String(format: "T%02d", $0) } + ["St Out", "Master"]
        return FakeLogicMCU(names: names)
    }

    var maxOffset: Int { max(0, strips.count - MCU.strips) }

    // Changes a person (or another agent) makes in Logic's mixer ----------
    /// A rename redraws only that name cell, as Logic does for a strip that is on the surface.
    func rename(_ index: Int, to name: String) {
        strips[index].name = name
        let slot = index - offset
        if (0..<MCU.strips).contains(slot) { send(lcd(slot * 7, cell(name))) }
    }

    /// Reordering, adding or deleting tracks changes what every later position shows. Logic
    /// refreshes the whole view, as it does for a bank move (assumed; see docs/target-contract.md).
    func swapStrips(_ a: Int, _ b: Int) {
        strips.swapAt(a, b)
        refreshView()
    }

    func removeStrip(at index: Int) {
        strips.remove(at: index)
        refreshView()
    }

    func insertStrip(named name: String, at index: Int) {
        strips.insert(Strip(name: name), at: index)
        refreshView()
    }

    private func refreshView() {
        offset = min(offset, maxOffset)
        send(viewMessages(includeLEDs: true))
    }

    // Logic → backend ----------------------------------------------------
    private func send(_ bytes: [UInt8]) { backend?.ingest(bytes) }

    private func cell(_ text: String) -> String { text.padding(toLength: 7, withPad: " ", startingAt: 0) }

    private func lcd(_ offset: Int, _ text: String) -> [UInt8] {
        MCU.sysexHeader + [0x12, UInt8(offset)] + Array(text.utf8) + [0xF7]
    }

    private func strip(at slot: Int) -> Strip? {
        let index = offset + slot
        return index < strips.count ? strips[index] : nil
    }

    private func led(_ note: UInt8, _ on: Bool) -> [UInt8] { [0x90, note, on ? 0x7F : 0x00] }

    private func colourSysex() -> [UInt8] {
        MCU.sysexHeader + [0x72] + [UInt8](repeating: 4, count: 8) + [0xF7]
    }

    private func viewMessages(includeLEDs: Bool) -> [UInt8] {
        var out: [UInt8] = []
        out += lcd(0, (0..<MCU.strips).map { cell(strip(at: $0)?.name ?? "") }.joined())
        out += lcd(56, (0..<MCU.strips).map { slot -> String in
            guard let s = strip(at: slot) else { return cell("") }
            return cell(s.hasPan ? String(s.pan) : "")
        }.joined())
        for slot in 0..<MCU.strips {
            let value = strip(at: slot)?.fader ?? 0
            out += [0xE0 | UInt8(slot), UInt8(value & 0x7F), UInt8(value >> 7)]
        }
        if includeLEDs {
            for slot in 0..<MCU.strips {
                let s = strip(at: slot)
                out += led(MCU.recNote(slot), s?.rec ?? false)
                out += led(MCU.soloNote(slot), s?.solo ?? false)
                out += led(MCU.muteNote(slot), s?.mute ?? false)
                out += led(MCU.selectNote(slot), s != nil && offset + slot == selected)
            }
        }
        out += colourSysex()
        return out
    }

    private func transportLEDs() -> [UInt8] {
        led(MCU.stopNote, !playing) + led(MCU.playNote, playing) + led(MCU.recordNote, recording)
    }

    /// Logic (re)connects: device query, then the state dump.
    func connect(withholdDump: Bool = false) {
        send(MCU.sysexHeader + [0x00, 0xF7])
        guard !withholdDump else { return }
        send(viewMessages(includeLEDs: !withholdLEDDump))
        if !withholdLEDDump && !withholdTransportLEDs { send(transportLEDs() + led(MCU.rudeSoloNote, false)) }
    }

    // backend → Logic ------------------------------------------------------
    func handle(_ message: [UInt8]) {
        guard message.count == 3 else { return }
        if message[0] == 0x90 && message[2] == 0x7F { press(message[1]) }
        if message[0] == 0x90, (0x68..<0x70).contains(message[1]) {
            let slot = Int(message[1] - 0x68)
            if message[2] == 0x7F, strip(at: slot) != nil { printDB(slot) }
        }
        if message[0] & 0xF0 == 0xE0, Int(message[0] & 0x0F) < MCU.strips {
            // Fader move: Logic echoes the value and prints it in dB.
            let slot = Int(message[0] & 0x0F)
            guard strip(at: slot) != nil else { return }
            strips[offset + slot].fader = Int(message[1]) | Int(message[2]) << 7
            send([0xE0 | UInt8(slot), message[1], message[2]])
            printDB(slot)
        }
    }

    /// Logic's dB text is 8 characters and is shifted left to fit the row, so the
    /// last strip's text starts one column before its cell (real Logic, EXP-MCU-021).
    private func printDB(_ slot: Int) {
        guard let s = strip(at: slot) else { return }
        let db = FaderCalibration.db(forValue: s.fader)
        let text = db.isInfinite ? "-oo dB " : String(format: "%+.1f dB ", db)
        send(lcd(min(56 + slot * 7, 104), text))
    }

    private func press(_ note: UInt8) {
        presses.append(note)
        switch note {
        case MCU.bankLeftNote, MCU.bankRightNote, MCU.channelLeftNote, MCU.channelRightNote:
            navigate(note)
        case MCU.playNote:
            playing = true
            send(transportLEDs())
        case MCU.stopNote:
            playing = false
            recording = false
            send(transportLEDs())
        case 0x10..<0x18:
            let index = offset + Int(note - 0x10)
            guard index < strips.count else { return }
            strips[index].mute.toggle()
            send(lcd(56 + Int(note - 0x10) * 7, cell(strips[index].mute ? "Muted" : "--")))
            send(led(note, strips[index].mute))
        case 0x18..<0x20:
            let index = offset + Int(note - 0x18)
            guard index < strips.count else { return }
            selected = index
            send((0..<MCU.strips).flatMap { led(MCU.selectNote($0), offset + $0 == selected) })
        default:
            break
        }
    }

    private func navigate(_ note: UInt8) {
        navigations += 1
        let before = offset
        switch note {
        case MCU.bankLeftNote: offset = max(0, offset - MCU.strips)
        case MCU.bankRightNote: offset = min(maxOffset, offset + MCU.strips)
        case MCU.channelLeftNote: offset = max(0, offset - 1)
        default:
            if dropAllChannelRight { return }
            if dropChannelRight > 0 { dropChannelRight -= 1; return }
            offset = min(maxOffset, offset + 1)
        }
        let churn = note == MCU.bankLeftNote && alwaysMoveOnBankLeft
        guard offset != before || churn else { return }  // a no-op press brings nothing
        send(viewMessages(includeLEDs: true))
        if alwaysDuplicateColour || duplicateColourOnNavigation == navigations { send(colourSysex()) }
    }
}

/// Backend wired to a fake Logic, with time shrunk so waits take milliseconds.
func makeBackend(for sim: FakeLogicMCU, pid: Int32 = 4242) -> MCUBackend {
    let app = LogicAppInfo(pid: pid, bundleID: "test.logic", name: "Logic", version: "12.3.1", build: "6682", path: nil)
    let backend = MCUBackend(
        environment: MCUEnvironment(transmit: { [unowned sim] in sim.handle($0) },
                                    runningApp: { app }, timeScale: 0.02),
        log: { _ in })
    sim.backend = backend
    return backend
}
