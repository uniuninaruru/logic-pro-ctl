import Foundation

/// Mackie Control message numbers as observed with Logic 12.3.1
/// (Research/experiments/EXP-MCU-*). `strip` is 0-based within the bank.
public enum MCU {
    public static let model: UInt8 = 0x14
    public static let sysexHeader: [UInt8] = [0xF0, 0x00, 0x00, 0x66, model]
    public static let strips = 8
    public static let masterFaderChannel = 8

    public static func recNote(_ strip: Int) -> UInt8 { UInt8(0x00 + strip) }
    public static func soloNote(_ strip: Int) -> UInt8 { UInt8(0x08 + strip) }
    public static func muteNote(_ strip: Int) -> UInt8 { UInt8(0x10 + strip) }
    public static func selectNote(_ strip: Int) -> UInt8 { UInt8(0x18 + strip) }
    public static func touchNote(_ strip: Int) -> UInt8 { UInt8(0x68 + strip) }
    public static func vpotCC(_ strip: Int) -> UInt8 { UInt8(0x10 + strip) }
    public static let stopNote: UInt8 = 0x5D
    public static let playNote: UInt8 = 0x5E
    public static let recordNote: UInt8 = 0x5F
    public static let rudeSoloNote: UInt8 = 0x73
    /// Time display mode LEDs. Logic lit BEATS and not SMPTE in the logs of EXP-MCU-009/024.
    public static let smpteNote: UInt8 = 0x71
    public static let beatsNote: UInt8 = 0x72
    /// The 10-digit time display: CC 0x40 is the rightmost digit, 0x49 the leftmost.
    public static let timecodeCCs: ClosedRange<UInt8> = 0x40...0x49

    /// One digit of the time display: the low 6 bits are a character (0x00–0x1F → '@', 'A'…'_';
    /// 0x20–0x3F → ASCII), bit 6 lights the dot after it.
    public static func displayCharacter(_ value: UInt8) -> (character: Character, dot: Bool) {
        let code = value & 0x3F
        return (Character(UnicodeScalar(code < 0x20 ? code + 0x40 : code)), value & 0x40 != 0)
    }
    public static let bankLeftNote: UInt8 = 0x2E
    public static let bankRightNote: UInt8 = 0x2F
    public static let channelLeftNote: UInt8 = 0x30
    public static let channelRightNote: UInt8 = 0x31

    public static func press(_ note: UInt8) -> [[UInt8]] { [[0x90, note, 0x7F], [0x90, note, 0x00]] }
    public static func fader(_ channel: Int, _ value: Int) -> [UInt8] {
        let v = max(0, min(16383, value))
        return [0xE0 | UInt8(channel), UInt8(v & 0x7F), UInt8(v >> 7)]
    }
    /// V-Pot rotation: positive = clockwise. One tick = one Logic pan unit.
    public static func vpot(_ strip: Int, ticks: Int) -> [UInt8] {
        let n = UInt8(min(abs(ticks), 0x3F))
        return [0xB0, vpotCC(strip), ticks < 0 ? 0x40 | n : n]
    }
}

/// Mirror of the surface state Logic believes it is driving: 2×56 LCD,
/// 9 faders, LEDs and V-Pot rings. Not thread-safe; the owner locks.
public struct MCUSurface {
    public enum Event: Equatable {
        case deviceQuery(model: UInt8)
        case versionRequest(model: UInt8)
        case connectionReply(model: UInt8)
        case lcd(offset: Int, text: [UInt8])
        case fader(channel: Int, value: Int)
        case led(note: UInt8, velocity: UInt8)
        case ring(strip: Int, value: UInt8)
        case meter(strip: Int, level: Int)
        case other([UInt8])
    }

    public private(set) var lcd = [UInt8](repeating: 0x20, count: 112)
    public private(set) var faders = [Int?](repeating: nil, count: 9)
    public private(set) var leds = [UInt8](repeating: 0, count: 128)
    /// True once Logic has reported this LED in the current session. An LED that
    /// was never reported is *unknown*, not off (the default value 0 is not evidence).
    public private(set) var ledSeen = [Bool](repeating: false, count: 128)
    public private(set) var rings = [UInt8?](repeating: nil, count: 8)
    /// The time display, leftmost digit first; nil until Logic reports that digit in this session.
    public private(set) var timecode = [UInt8?](repeating: nil, count: 10)
    /// Per-strip counters, bumped on every update touching that strip;
    /// callers snapshot them before a write and wait for them to change.
    public private(set) var lowerWrites = [Int](repeating: 0, count: 8)
    public private(set) var upperWrites = [Int](repeating: 0, count: 8)
    public private(set) var faderUpdates = [Int](repeating: 0, count: 9)
    public private(set) var ledUpdates = [Int](repeating: 0, count: 128)
    public private(set) var lcdUpdates = 0
    /// Count of `14 72` sysex (per-strip colours). Logic sends one whenever
    /// the bank moves and nothing for a no-op bank press (EXP-MCU-020).
    public private(set) var colorUpdates = 0

    private var pending: [UInt8] = []
    private var inSysex = false
    private var runningStatus: UInt8?
    private var transportSessionBaseline = (play: 0, record: 0)

    public init() {}

    /// Feeds raw MIDI 1.0 bytes (may split messages arbitrarily).
    public mutating func feed(_ bytes: [UInt8]) -> [Event] {
        var events: [Event] = []
        for b in bytes {
            if b >= 0xF8 { continue }  // realtime
            if b == 0xF0 {
                pending = [b]
                inSysex = true
                continue
            }
            if inSysex {
                pending.append(b)
                if b == 0xF7 {
                    events.append(apply(pending))
                    pending = []
                    inSysex = false
                }
                continue
            }
            if b & 0x80 != 0 {
                pending = [b]
                runningStatus = b < 0xF0 ? b : nil
                if Self.length(of: b) == 1 {
                    events.append(apply(pending))
                    pending = []
                }
                continue
            }
            if pending.isEmpty, let rs = runningStatus { pending = [rs] }
            guard let status = pending.first else { continue }
            pending.append(b)
            if pending.count == Self.length(of: status) {
                events.append(apply(pending))
                pending = []
            }
        }
        return events
    }

    private static func length(of status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0: return 3
        case 0xC0, 0xD0: return 2
        default:
            switch status {
            case 0xF1, 0xF3: return 2
            case 0xF2: return 3
            default: return 1
            }
        }
    }

    /// Applies one complete message.
    public mutating func apply(_ m: [UInt8]) -> Event {
        guard let s = m.first else { return .other(m) }
        switch s & 0xF0 {
        case 0xE0 where m.count == 3:
            let ch = Int(s & 0x0F)
            let v = Int(m[1]) | Int(m[2]) << 7
            if ch < faders.count {
                faders[ch] = v
                faderUpdates[ch] += 1
            }
            return .fader(channel: ch, value: v)
        case 0x90 where m.count == 3:
            leds[Int(m[1] & 0x7F)] = m[2]
            ledSeen[Int(m[1] & 0x7F)] = true
            ledUpdates[Int(m[1] & 0x7F)] += 1
            return .led(note: m[1], velocity: m[2])
        case 0xB0 where m.count == 3 && (0x30...0x37).contains(m[1]):
            let strip = Int(m[1] - 0x30)
            rings[strip] = m[2]
            return .ring(strip: strip, value: m[2])
        case 0xB0 where m.count == 3 && MCU.timecodeCCs.contains(m[1]):
            timecode[9 - Int(m[1] - MCU.timecodeCCs.lowerBound)] = m[2]
            return .other(m)
        case 0xD0 where m.count == 2:
            return .meter(strip: Int(m[1] >> 4), level: Int(m[1] & 0x0F))
        default:
            break
        }
        guard s == 0xF0, m.count >= 7, Array(m[1...3]) == [0x00, 0x00, 0x66] else { return .other(m) }
        let model = m[4]
        switch m[5] {
        case 0x00:
            // Logic probes several models; only our own query starts a new session.
            if model == MCU.model { discardSessionData() }
            return .deviceQuery(model: model)
        case 0x13: return .versionRequest(model: model)
        case 0x02: return .connectionReply(model: model)
        case 0x72 where model == MCU.model:
            colorUpdates += 1
            return .other(m)
        case 0x12 where model == MCU.model && m.count >= 8:
            let offset = Int(m[6])
            let text = Array(m[7..<(m.count - 1)])
            writeLCD(offset: offset, text: text)
            return .lcd(offset: offset, text: text)
        default:
            return .other(m)
        }
    }

    private mutating func writeLCD(offset: Int, text: [UInt8]) {
        for (i, c) in text.enumerated() where offset + i < lcd.count {
            lcd[offset + i] = c
        }
        lcdUpdates += 1
        let end = offset + text.count
        for strip in 0..<MCU.strips {
            let upper = strip * 7
            if offset < upper + 7 && end > upper { upperWrites[strip] += 1 }
            let lower = 56 + strip * 7
            if offset < lower + 7 && end > lower { lowerWrites[strip] += 1 }
        }
    }

    /// Clears everything, counters included (ports re-plugged, nothing in flight).
    public mutating func reset() { self = MCUSurface() }

    /// Logic re-runs the handshake and then re-sends the whole surface. Names,
    /// faders, LEDs and V-Pot rings read before that belong to the previous
    /// session (possibly another project) and must not be used as evidence.
    /// Counters keep counting so callers comparing with an earlier snapshot,
    /// and the baselines taken at the handshake, stay valid.
    mutating func discardSessionData() {
        transportSessionBaseline = (ledUpdates[Int(MCU.playNote)], ledUpdates[Int(MCU.recordNote)])
        lcd = [UInt8](repeating: 0x20, count: lcd.count)
        faders = [Int?](repeating: nil, count: faders.count)
        leds = [UInt8](repeating: 0, count: leds.count)
        ledSeen = [Bool](repeating: false, count: ledSeen.count)
        rings = [UInt8?](repeating: nil, count: rings.count)
        timecode = [UInt8?](repeating: nil, count: timecode.count)
    }

    /// The ten characters of the time display, or nil until every digit was reported in this session.
    /// Logic sends all ten in its state dump and then only the digits that change.
    public func timecodeCharacters() -> [(character: Character, dot: Bool)]? {
        guard timecode.allSatisfy({ $0 != nil }) else { return nil }
        return timecode.map { MCU.displayCharacter($0!) }
    }

    public func row(_ r: Int) -> String {
        String(decoding: lcd[(r * 56)..<((r + 1) * 56)], as: UTF8.self)
    }

    /// 7-character LCD cell of a strip, trimmed. Logic shows at most 6
    /// characters of a track name in the upper row.
    public func upperText(_ strip: Int) -> String {
        String(decoding: lcd[(strip * 7)..<(strip * 7 + 7)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    /// The dB text Logic prints on a touched fader. It is 8 characters wide and Logic
    /// shifts it left so it fits the row, so the last strip's text starts one column
    /// before its cell (column 104, not 105; EXP-MCU-021). Read it from there.
    public func dbText(_ strip: Int) -> String {
        let start = min(56 + strip * 7, 104)
        return String(decoding: lcd[start..<(start + 7)], as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }

    public func lowerText(_ strip: Int) -> String {
        String(decoding: lcd[(56 + strip * 7)..<(56 + strip * 7 + 7)], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }

    public func led(_ note: UInt8) -> Bool { leds[Int(note)] != 0 }

    /// LED state, or nil if Logic has not reported it in this session.
    public func ledIfKnown(_ note: UInt8) -> Bool? { ledSeen[Int(note)] ? leds[Int(note)] != 0 : nil }

    /// `feed` applies the whole packet batch before returning its events. A
    /// handshake may precede valid feedback in that same batch, so recover
    /// counters at that event boundary rather than discarding later updates.
    func feedbackCounters(atEvent index: Int, in events: [Event]) -> (lcd: Int, play: Int, record: Int) {
        var counts = (lcd: lcdUpdates, play: ledUpdates[Int(MCU.playNote)],
                      record: ledUpdates[Int(MCU.recordNote)])
        for event in events.dropFirst(index + 1) {
            switch event {
            case .lcd: counts.lcd -= 1
            case .led(let note, _) where note & 0x7f == MCU.playNote: counts.play -= 1
            case .led(let note, _) where note & 0x7f == MCU.recordNote: counts.record -= 1
            default: break
            }
        }
        return counts
    }

    /// Defaults are unknown until Logic has actually sent both transport LEDs.
    /// Baselines let the owner require new feedback after a reconnect.
    public func transportSnapshot(sincePlayUpdate: Int = 0, sinceRecordUpdate: Int = 0) -> TransportSnapshot? {
        guard ledUpdates[Int(MCU.playNote)] > max(sincePlayUpdate, transportSessionBaseline.play),
              ledUpdates[Int(MCU.recordNote)] > max(sinceRecordUpdate, transportSessionBaseline.record) else { return nil }
        return TransportSnapshot(playing: led(MCU.playNote), recording: led(MCU.recordNote))
    }
    public var anySoloActive: Bool { (0..<MCU.strips).contains { led(MCU.soloNote($0)) } }
}

/// Parses an LCD cell such as "-3.7 dB", "+0.0 dB ", "-67.6 d", "-oo dB".
public func parseLCDDecibels(_ text: String) -> Double? {
    // A number token followed by a unit token cut to 7 columns ("dB" or "d").
    let parts = text.split(separator: " ")
    guard parts.count == 2, parts[1].hasPrefix("d") else { return nil }
    if parts[0] == "-oo" { return -.infinity }
    return Double(parts[0])
}

/// Parses an LCD cell holding a Logic pan value (-64…63), e.g. "-20", "0".
public func parseLCDPan(_ text: String) -> Int? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard let v = Int(t), (-64...63).contains(v) else { return nil }
    return v
}
