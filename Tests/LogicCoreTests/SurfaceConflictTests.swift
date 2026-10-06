import Foundation
@testable import LogicCore

// Two Mackie Control units on the one port (Logic had "Mackie Control #2" configured, EXP-MCU-029): both write
// the LCD, and with every strip already shown across the units no bank move happens, so a scan used to
// report a wrong list as complete. Everything but status (and the raw debug tool) is now refused.
#if canImport(Testing)
import Testing

private func twoUnits(tracks: Int = 12) -> (FakeLogicMCU, MCUBackend) {
    let sim = FakeLogicMCU.project(tracks: tracks)
    sim.secondUnit = true
    let backend = makeBackend(for: sim)
    sim.connect()
    return (sim, backend)
}

@Test func twoDifferentDisplaysInTheDumpAreReportedByStatus() {
    let (sim, backend) = twoUnits()
    let status = withExtendedLifetime(sim) { backend.execute(.status) }
    #expect(status.ok)
    #expect(status.result?["mcu"]?["surface_conflict"] == .bool(true))
}

@Test func aScanIsRefusedWithoutPressingAnythingWhenTwoUnitsShareThePort() {
    let (sim, backend) = twoUnits()
    for command in [LogicCommand.state, .trackList, .trackGet(track: 1)] {
        let outcome = backend.execute(command)
        #expect(!outcome.ok)
        #expect(outcome.error == "surface_conflict")
    }
    #expect(sim.presses.isEmpty)                       // no bank navigation, no reads that move anything
}

@Test func writesAreRefusedBeforeAnyPressWhenTwoUnitsShareThePort() {
    let (sim, backend) = twoUnits()
    let arm = backend.execute(.trackArm(track: 2, on: true), expectName: "T02")
    #expect(!arm.ok && !arm.verified)
    #expect(arm.error == "surface_conflict")
    let play = backend.execute(.transportPlay)
    #expect(play.error == "surface_conflict")
    #expect(sim.presses.isEmpty)
    #expect(!sim.strips[1].rec && !sim.playing)
}

@Test func theRawDebugToolStillWorksForDiagnosis() {
    let (sim, backend) = twoUnits()      // the fake must outlive every send (the transmit hook is unowned)
    let outcome = withExtendedLifetime(sim) { backend.execute(.debugMCU(messages: [[0x90, 0x68, 0x7F], [0x90, 0x68, 0x00]])) }
    #expect(outcome.ok)
}

@Test func oneUnitWritesTheSameDisplayAndIsNotAConflict() {
    let sim = FakeLogicMCU.project(tracks: 12)
    let backend = makeBackend(for: sim)
    sim.connect()
    #expect(backend.execute(.status).result?["mcu"]?["surface_conflict"] == .bool(false))
    let list = backend.execute(.trackList)
    #expect(list.ok)
    #expect(list.observation?["strips"] == .int(14))
}

@Test func aLaterDumpFromOneUnitClearsTheConflict() {
    let (sim, backend) = twoUnits()
    #expect(backend.execute(.trackList).error == "surface_conflict")
    sim.secondUnit = false                             // the extra unit was removed in Logic
    Thread.sleep(forTimeInterval: 0.1)                 // past the 1 s dump window (scaled by 0.02 in tests)
    sim.connect()
    let list = backend.execute(.trackList)
    #expect(list.ok)
    #expect(list.observation?["strips"] == .int(14))
}
#endif
