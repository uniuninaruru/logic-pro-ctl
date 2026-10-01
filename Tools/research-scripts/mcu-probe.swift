// MCU probe: creates a virtual MIDI port pair for Logic's "Logic Control"
// (Mackie Control) surface and logs traffic in both directions.
//
//   swift Tools/research-scripts/mcu-probe.swift [fifo-path] > log.txt
//
// Ports (as seen from Logic):
//   source      "logicctl-mcu" — Logic's Control Surface *input*
//   destination "logicctl-mcu" — Logic's Control Surface *output*
//
// Lines written to fifo-path (hex bytes, e.g. "90 5E 7F") are sent to Logic.
// Lines starting with '#' are logged as experiment markers.
// MCU_AUTO=1 answers Logic's Mackie Control handshake automatically.
// Output: one line per message,
//   <ISO8601 ms> dir=RX|TX bytes=<hex> [decode]
// RX = Logic → probe, TX = probe → Logic. Research only; no product code.
import CoreMIDI
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
func log(_ s: String) { print("\(iso.string(from: Date())) \(s)") }
func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02X", $0) }.joined(separator: " ") }

/// Minimal MCU decode, enough to correlate messages with UI actions.
/// Field meanings follow the public Mackie Control spec and are NOT
/// verified against Logic yet.
func decode(_ b: [UInt8]) -> String {
    guard let s = b.first else { return "" }
    switch s & 0xF0 {
    case 0xE0 where b.count >= 3:
        let v = Int(b[1]) | Int(b[2]) << 7
        return "pitchbend ch=\(s & 0x0F) value14=\(v)"
    case 0x90 where b.count >= 3:
        return "note \(b[1]) vel=\(b[2])"
    case 0xB0 where b.count >= 3:
        return "cc \(b[1]) val=\(b[2])"
    case 0xD0 where b.count >= 2:
        return "chanpressure \(b[1])"
    default: break
    }
    if s == 0xF0, b.count > 6, b[1...3] == [0x00, 0x00, 0x66] {
        let cmd = b[5]
        if cmd == 0x12, b.count > 8 {
            let text = String(decoding: b[7..<(b.count - 1)], as: UTF8.self)
            return "sysex model=\(String(format: "%02X", b[4])) lcd offset=\(b[6]) text=\"\(text)\""
        }
        return "sysex model=\(String(format: "%02X", b[4])) cmd=\(String(format: "%02X", cmd))"
    }
    return ""
}

/// Splits a MIDI 1.0 byte stream into messages (handles running status loosely).
func split(_ bytes: [UInt8]) -> [[UInt8]] {
    var out: [[UInt8]] = []
    var i = 0
    while i < bytes.count {
        let s = bytes[i]
        if s == 0xF0 {
            var j = i
            while j < bytes.count && bytes[j] != 0xF7 { j += 1 }
            out.append(Array(bytes[i...min(j, bytes.count - 1)]))
            i = j + 1
            continue
        }
        let len: Int
        switch s & 0xF0 {
        case 0xC0, 0xD0: len = 2
        case 0x80, 0x90, 0xA0, 0xB0, 0xE0: len = 3
        default: len = 1
        }
        out.append(Array(bytes[i..<min(i + len, bytes.count)]))
        i += len
    }
    return out
}

var client = MIDIClientRef()
var source = MIDIEndpointRef()
var dest = MIDIEndpointRef()
let name = "logicctl-mcu" as CFString

var status = MIDIClientCreateWithBlock("mcu-probe" as CFString, &client) { _ in }
guard status == noErr else { log("error MIDIClientCreate \(status)"); exit(1) }
status = MIDISourceCreate(client, name, &source)
guard status == noErr else { log("error MIDISourceCreate \(status)"); exit(1) }
status = MIDIDestinationCreateWithBlock(client, name, &dest) { list, _ in
    var packet = list.pointee.packet
    for _ in 0..<list.pointee.numPackets {
        let bytes = withUnsafeBytes(of: packet.data) { Array($0.prefix(Int(packet.length))) }
        for m in split(bytes) {
            log("dir=RX bytes=\(hex(m)) \(decode(m))")
            if autoHandshake { DispatchQueue.main.async { handshake(m) } }
        }
        packet = MIDIPacketNext(&packet).pointee
    }
}
guard status == noErr else { log("error MIDIDestinationCreate \(status)"); exit(1) }
log("ready source=logicctl-mcu destination=logicctl-mcu")

func send(_ bytes: [UInt8]) {
    var list = MIDIPacketList()
    let packet = MIDIPacketListInit(&list)
    _ = MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, bytes)
    MIDIReceived(source, &list)
    log("dir=TX bytes=\(hex(bytes)) \(decode(bytes))")
}

/// MCU_AUTO=1: answer as a Mackie Control (model 0x14) using the public
/// handshake: query(00) → connection query(01), version request(13) →
/// version reply(14), connection reply(02) → confirmation(03).
let autoHandshake = ProcessInfo.processInfo.environment["MCU_AUTO"] == "1"
let serial: [UInt8] = Array("LCTL001".utf8)
func handshake(_ m: [UInt8]) {
    guard m.count >= 7, m[0] == 0xF0, m[1...4] == [0x00, 0x00, 0x66, 0x14] else { return }
    switch m[5] {
    case 0x00: send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x01] + serial + [0x01, 0x02, 0x03, 0x04, 0xF7])
    case 0x13: send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x14] + Array("V1.02".utf8) + [0xF7])
    case 0x02: send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x03] + serial + [0xF7])
    default: break
    }
}

if CommandLine.arguments.count > 1 {
    let path = CommandLine.arguments[1]
    Thread.detachNewThread {
        while true {
            // Opening a FIFO blocks until a writer appears; reopen after EOF.
            guard let fh = FileHandle(forReadingAtPath: path) else { sleep(1); continue }
            let text = String(decoding: fh.readDataToEndOfFile(), as: UTF8.self)
            for line in text.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("#") { log("marker \(l.dropFirst().trimmingCharacters(in: .whitespaces))"); continue }
                let bytes = l.split(separator: " ").compactMap { UInt8($0, radix: 16) }
                if !bytes.isEmpty { send(bytes) }
            }
        }
    }
}

signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }
RunLoop.main.run()
