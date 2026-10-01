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

@Test func colourSysexCountsAsBankMove() {
    var s = MCUSurface()
    // Sent by Logic on every bank move, never for a no-op press (EXP-MCU-020).
    _ = s.feed([0xF0, 0, 0, 0x66, 0x14, 0x72, 4, 2, 2, 4, 4, 4, 4, 4, 0xF7])
    #expect(s.colorUpdates == 1)
    #expect(s.lcdUpdates == 0)
}

@Test func handshakeDiscardsPreviousSessionState() throws {
    var s = MCUSurface()
    for m in try fixture("mcu_connect_dump.hex") { _ = s.feed(m) }
    #expect(s.upperText(0) == "Piano")
    #expect(s.faders[0] != nil)
    #expect(s.led(MCU.recNote(0)))
    let before = (lcd: s.lcdUpdates, colour: s.colorUpdates)

    // Logic probes several models; a query for another one must not touch our state.
    _ = s.feed([0xF0, 0x00, 0x00, 0x66, 0x10, 0x00, 0xF7])
    #expect(s.upperText(0) == "Piano")

    // Our model is queried again (Logic or the project changed): old data is dropped.
    _ = s.feed(MCU.sysexHeader + [0x00, 0xF7])
    #expect(s.upperText(0).isEmpty)
    #expect(s.lowerText(0).isEmpty)
    #expect(s.faders.allSatisfy { $0 == nil })
    #expect(s.rings.allSatisfy { $0 == nil })
    #expect(!s.led(MCU.recNote(0)) && !s.led(MCU.selectNote(0)))
    // Counters keep counting, so earlier snapshots and baselines stay comparable.
    #expect(s.lcdUpdates == before.lcd && s.colorUpdates == before.colour)

    // The new dump fills the surface again.
    _ = s.feed(MCU.sysexHeader + [0x12, 0] + Array("Vox".utf8) + [0xF7])
    #expect(s.upperText(0) == "Vox")
    #expect(s.lcdUpdates == before.lcd + 1)
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

@Test func transportDefaultsAreUnknownUntilBothLEDsArrive() {
    var surface = MCUSurface()
    #expect(surface.transportSnapshot() == nil)
    _ = surface.feed([0x90, MCU.playNote, 0])
    #expect(surface.transportSnapshot() == nil)
    _ = surface.feed([0x90, MCU.recordNote, 0])
    #expect(surface.transportSnapshot() == TransportSnapshot(playing: false, recording: false))
    // A new session cannot reuse those off LEDs as evidence.
    #expect(surface.transportSnapshot(sincePlayUpdate: 1, sinceRecordUpdate: 1) == nil)
    _ = surface.feed([0x90, MCU.playNote, 0x7f, 0x90, MCU.recordNote, 0])
    #expect(surface.transportSnapshot(sincePlayUpdate: 1, sinceRecordUpdate: 1) == TransportSnapshot(playing: true, recording: false))
    surface.reset()
    #expect(surface.transportSnapshot() == nil)
}

@Test func handshakeKeepsLaterFeedbackInTheSameBatch() {
    var surface = MCUSurface()
    let query = MCU.sysexHeader + [0x00, 0xf7]
    let lcd = MCU.sysexHeader + [0x12, 0] + Array("Piano".utf8) + [0xf7]
    let off = [UInt8(0x90), MCU.playNote, 0, 0x90, MCU.recordNote, 0]
    _ = surface.feed(lcd + off) // A previous session's cache.
    let events = surface.feed(query + lcd + off)
    let baseline = surface.feedbackCounters(atEvent: 0, in: events)
    #expect(baseline.lcd == 1)
    #expect(baseline.play == 1 && baseline.record == 1)
    #expect(surface.lcdUpdates > baseline.lcd)
    #expect(surface.transportSnapshot(sincePlayUpdate: baseline.play, sinceRecordUpdate: baseline.record)
            == TransportSnapshot(playing: false, recording: false))

    // If the last handshake has no following feedback, earlier updates do
    // not qualify, including those earlier in the same packet batch.
    let next = surface.feed(lcd + off + query)
    let latest = surface.feedbackCounters(atEvent: next.count - 1, in: next)
    #expect(surface.lcdUpdates == latest.lcd)
    #expect(surface.transportSnapshot(sincePlayUpdate: latest.play, sinceRecordUpdate: latest.record) == nil)
}

@Test func transportSnapshotRejectsPreviousSessionLEDsAfterAQuery() {
    var surface = MCUSurface()
    _ = surface.feed([0x90, MCU.playNote, 0x7f, 0x90, MCU.recordNote, 0])
    #expect(surface.transportSnapshot() == TransportSnapshot(playing: true, recording: false))
    _ = surface.feed([0xf0, 0, 0, 0x66, 0x15, 0, 0xf7]) // Another model.
    #expect(surface.transportSnapshot() == TransportSnapshot(playing: true, recording: false))
    _ = surface.feed(MCU.sysexHeader + [0, 0xf7])
    #expect(surface.transportSnapshot() == nil) // Old counters do not validate cleared off LEDs.
    _ = surface.feed([0x90, MCU.playNote, 0])
    #expect(surface.transportSnapshot() == nil)
    _ = surface.feed([0x90, MCU.recordNote, 0])
    #expect(surface.transportSnapshot() == TransportSnapshot(playing: false, recording: false))
}
#endif
