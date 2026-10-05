import Foundation
@testable import LogicCore

// The playhead in `state`, read from Logic's MCU time display (CC 0x40…0x49) and the BEATS/SMPTE LEDs.
// The bytes in the first test are copied from a real Logic 12.3.1 log (EXP-MCU-024, stopped at 1 3 2 29);
// everything else is the fake surface.
#if canImport(Testing)
import Testing

private func position(_ outcome: Outcome) -> JSONValue? { outcome.result?["position"] }

@Test func theTimeDisplayFromARealLogicLogDecodes() {
    var surface = MCUSurface()
    let real: [[UInt8]] = [[0xB0, 0x49, 0x20], [0xB0, 0x48, 0x20], [0xB0, 0x47, 0x31], [0xB0, 0x46, 0x20],
                           [0xB0, 0x45, 0x33], [0xB0, 0x44, 0x20], [0xB0, 0x43, 0x32], [0xB0, 0x42, 0x20],
                           [0xB0, 0x41, 0x32], [0xB0, 0x40, 0x39]]
    for m in real.dropLast() { _ = surface.apply(m) }
    #expect(surface.timecodeCharacters() == nil)                 // nine of ten digits: not yet known
    _ = surface.apply(real.last!)
    #expect(String(surface.timecodeCharacters()!.map(\.character)) == "  1 3 2 29")
}

@Test func characterCodesLettersAndDotsDecode() {
    #expect(MCU.displayCharacter(0x31) == ("1", false))
    #expect(MCU.displayCharacter(0x20) == (" ", false))
    #expect(MCU.displayCharacter(0x10) == ("P", false))          // the assignment display showed "PN" this way
    #expect(MCU.displayCharacter(0x71) == ("1", true))           // bit 6 = the dot after the digit
}

@Test func stateCarriesTheBeatsPositionSplitIntoItsFields() {
    let sim = FakeLogicMCU.project(tracks: 2)
    let backend = makeBackend(for: sim)
    sim.connect()
    let p = position(backend.execute(.state))
    #expect(p?["display"] == "  1 3 2 29")
    #expect(p?["mode"] == "beats")
    #expect(p?["bar"] == 1 && p?["beat"] == 3 && p?["division"] == 2 && p?["tick"] == 29)
}

@Test func onlyChangedDigitsArriveAndThePositionFollows() {
    let sim = FakeLogicMCU.project(tracks: 2)
    let backend = makeBackend(for: sim)
    sim.connect()
    sim.moveTime(to: " 12 4 1  1")
    let p = position(backend.execute(.state))
    #expect(p?["display"] == " 12 4 1  1")
    #expect(p?["bar"] == 12 && p?["beat"] == 4 && p?["division"] == 1 && p?["tick"] == 1)
}

@Test func withoutTheDisplayThePositionIsNullNotZero() {
    let sim = FakeLogicMCU.project(tracks: 2)
    sim.timeDisplay = nil
    let backend = makeBackend(for: sim)
    sim.connect()
    #expect(position(backend.execute(.state)) == .null)
}

@Test func smpteModeGivesTheTextButNoBeatFields() {
    let sim = FakeLogicMCU.project(tracks: 2)
    sim.timeDisplay = " 0100 0100"
    sim.timeModeBeats = false
    let backend = makeBackend(for: sim)
    sim.connect()
    let p = position(backend.execute(.state))
    #expect(p?["mode"] == "smpte")
    #expect(p?["display"] != nil && p?["bar"] == nil)
}

@Test func aModeSwitchForgetsTheDigitsUntilTheyAreSentAgain() {
    // Review CDEX-022 (2): BEATS digits must not be reported as SMPTE after only the LEDs changed.
    let sim = FakeLogicMCU.project(tracks: 2)
    let backend = makeBackend(for: sim)
    sim.connect()
    sim.setTimeLEDs(beats: false, smpte: true)
    #expect(position(backend.execute(.state)) == .null)
    sim.resendTime(" 0100 0100")
    let p = position(backend.execute(.state))
    #expect(p?["mode"] == "smpte" && p?["display"] == " 0100 0100" && p?["bar"] == nil)
}

@Test func bothModeLEDsOnGiveNoModeAndNoSplit() {
    // Review CDEX-022 (3): a contradiction (or a switch in progress) is not read as BEATS.
    let sim = FakeLogicMCU.project(tracks: 2)
    let backend = makeBackend(for: sim)
    sim.connect()
    sim.setTimeLEDs(beats: true, smpte: true)
    let p = position(backend.execute(.state))
    #expect(p?["mode"] == .null)
    #expect(p?["bar"] == nil)
    #expect(p?["display"] == "  1 3 2 29")      // no known mode changed, so the digits stay
}

@Test func aNewHandshakeForgetsTheOldDisplay() {
    let sim = FakeLogicMCU.project(tracks: 2)
    let backend = makeBackend(for: sim)
    sim.connect()
    #expect(position(backend.execute(.state)) != .null)
    sim.timeDisplay = nil
    sim.connect()                                               // Logic reconnects and this time sends no display
    #expect(position(backend.execute(.state)) == .null)
}
#endif
