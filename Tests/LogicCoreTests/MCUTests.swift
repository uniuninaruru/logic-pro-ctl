import Foundation
@testable import LogicCore

#if canImport(Testing)
import Testing

/// Golden packets: Logic 12.3.1's first 150 messages after the logicctl-mcu
/// port appeared (Research/raw/20261001-133000-mcu-auto, EXP-MCU auto run).
func fixture(_ name: String) throws -> [[UInt8]] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)")
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
        $0.split(separator: " ").compactMap { UInt8($0, radix: 16) }
    }
}

@Test func goldenConnectDump() throws {
    var s = MCUSurface()
    var events: [MCUSurface.Event] = []
    for m in try fixture("mcu_connect_dump.hex") { events += s.feed(m) }
    #expect(events.contains(.deviceQuery(model: 0x14)))
    #expect(events.contains(.versionRequest(model: 0x14)))
    #expect(s.upperText(0) == "Piano")
    #expect(s.upperText(1) == "Audio")
    #expect(s.upperText(2) == "Bass")
    #expect(s.upperText(3) == "Synth")
    #expect(s.upperText(4) == "St Out")
    #expect(s.faders[0] == 12443)
    #expect(s.led(MCU.recNote(0)))
    #expect(s.led(MCU.selectNote(0)))
    #expect(!s.led(MCU.muteNote(0)))
}

@Test func lcdDiffUpdatesArePatchedIntoBuffer() {
    var s = MCUSurface()
    // "-56.9 dB" at offset 56, then Logic sends only "4.7" at offset 58 (EXP-MCU-009).
    _ = s.feed([0xF0, 0, 0, 0x66, 0x14, 0x12, 56] + Array("-56.9 dB".utf8) + [0xF7])
    _ = s.feed([0xF0, 0, 0, 0x66, 0x14, 0x12, 58] + Array("4.7".utf8) + [0xF7])
    #expect(s.lowerText(0) == "-54.7 d")
    #expect(parseLCDDecibels(s.lowerText(0)) == -54.7)
    #expect(s.lowerWrites[0] == 2)
    #expect(s.lowerWrites[1] == 1)  // "-56.9 dB" spilled one column into strip 2
}

@Test func messagesSplitAcrossChunks() {
    var s = MCUSurface()
    var events = s.feed([0xF0, 0, 0, 0x66])
    events += s.feed([0x14, 0x00, 0xF7, 0xE0, 0x1B])
    events += s.feed([0x61, 0x90, 0x10, 0x7F])
    #expect(events == [.deviceQuery(model: 0x14), .fader(channel: 0, value: 12443), .led(note: 0x10, velocity: 0x7F)])
}

@Test func runningStatusMeters() {
    var s = MCUSurface()
    let events = s.feed([0xD0, 0x4C, 0x4B])
    #expect(events == [.meter(strip: 4, level: 12), .meter(strip: 4, level: 11)])
}

@Test func lcdParsers() {
    #expect(parseLCDDecibels("-3.7 dB") == -3.7)
    #expect(parseLCDDecibels("+0.0 dB") == 0)
    #expect(parseLCDDecibels("-67.6 d") == -67.6)
    #expect(parseLCDDecibels("-oo dB") == -.infinity)
    #expect(parseLCDDecibels("0") == nil)
    #expect(parseLCDDecibels("Muted") == nil)
    #expect(parseLCDPan("-20") == -20)
    #expect(parseLCDPan("0") == 0)
    #expect(parseLCDPan("Pan") == nil)
    #expect(parseLCDPan("-3.7 dB") == nil)
}

@Test func messageBuilders() {
    #expect(MCU.fader(0, 11000) == [0xE0, 0x78, 0x55])
    #expect(MCU.vpot(0, ticks: -1) == [0xB0, 0x10, 0x41])
    #expect(MCU.vpot(0, ticks: 20) == [0xB0, 0x10, 0x14])
    #expect(MCU.press(MCU.muteNote(1)) == [[0x90, 0x11, 0x7F], [0x90, 0x11, 0x00]])
}

@Test func faderCalibration() {
    #expect(FaderCalibration.value(forDB: 0) == 12441)
    #expect(FaderCalibration.value(forDB: 6) == 14843)
    #expect(FaderCalibration.value(forDB: -.infinity) == 0)
    #expect(FaderCalibration.db(forValue: 0) == -.infinity)
    #expect((FaderCalibration.db(forValue: 10969) * 10).rounded() / 10 == -3.7)  // EXP-MCU-008 LCD
    #expect((FaderCalibration.db(forValue: 7154) * 10).rounded() / 10 == -12.1)  // EXP-MCU-009 LCD
    let values = stride(from: -60.0, through: 6.0, by: 0.5).map(FaderCalibration.value(forDB:))
    #expect(values == values.sorted())
}
#endif
