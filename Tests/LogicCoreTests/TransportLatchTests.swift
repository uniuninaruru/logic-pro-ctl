import Foundation
@testable import LogicCore

// `transport cycle|click on|off`: the MCU's global Cycle (0x56) and Click (0x59) buttons toggle, and their LEDs
// are the only evidence. FakeLogicMCU models what Logic is expected to do; only the "on" LED of each has been
// seen on the real Logic (EXP-MCU-029 read), the buttons have NOT been pressed there yet (support-matrix: tested).
#if canImport(Testing)
import Testing

private func connected() -> (FakeLogicMCU, MCUBackend) {
    let sim = FakeLogicMCU.project(tracks: 4)
    let backend = makeBackend(for: sim)
    sim.connect()
    return (sim, backend)
}

private func presses(_ sim: FakeLogicMCU, _ note: UInt8) -> Int { sim.presses.filter { $0 == note }.count }

@Test func cycleOnAndOffAreVerifiedByTheCycleLED() {
    let (sim, backend) = connected()
    let on = backend.execute(.transportCycle(on: true))
    #expect(on.ok && on.verified)
    #expect(sim.cycle)
    #expect(on.observed == ["cycle": true])
    let off = backend.execute(.transportCycle(on: false))
    #expect(off.ok && off.verified)
    #expect(!sim.cycle)
    #expect(presses(sim, MCU.cycleNote) == 2)
}

@Test func clickAlreadyOnIsAVerifiedNoOpWithoutAPress() {
    let (sim, backend) = connected()                   // the fake starts with the click on
    let outcome = backend.execute(.transportClick(on: true))
    #expect(outcome.ok && outcome.verified)
    #expect(presses(sim, MCU.clickNote) == 0)
    let off = backend.execute(.transportClick(on: false))
    #expect(off.ok && off.verified)
    #expect(!sim.click)
    #expect(presses(sim, MCU.clickNote) == 1)
}

@Test func anUnreportedLEDSendsNothing() {
    let sim = FakeLogicMCU.project(tracks: 4)
    sim.withholdGlobalLEDs = true
    let backend = makeBackend(for: sim)
    sim.connect()
    let outcome = backend.execute(.transportCycle(on: true))
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.error == "readback_unavailable")
    #expect(sim.presses.isEmpty)
    #expect(!sim.cycle)
}

@Test func aButtonLogicIgnoresFailsVerificationAfterOnePress() {
    let (sim, backend) = connected()
    sim.ignoreGlobalButtons = true
    let outcome = backend.execute(.transportCycle(on: true))
    #expect(!outcome.verified)
    #expect(outcome.error == "verification_failed")
    #expect(outcome.observed == ["cycle": false])
    #expect(presses(sim, MCU.cycleNote) == 1)          // a toggle is never pressed a second time
}

@Test func theCycleAndClickCommandsParse() throws {
    #expect(try LogicCommand(request: CLIParser.parse(["transport", "cycle", "on"])) == .transportCycle(on: true))
    #expect(try LogicCommand(request: CLIParser.parse(["transport", "click", "off", "--json"])) == .transportClick(on: false))
    #expect(throws: CommandError.self) { try CLIParser.parse(["transport", "cycle"]) }
    #expect(throws: CommandError.self) { try LogicCommand(request: CLIParser.parse(["transport", "click", "maybe"])) }
    #expect(LogicCommand.transportCycle(on: true).isWrite && LogicCommand.isWrite(named: "transport.click"))
    #expect(LogicCommand.transportClick(on: true).trackNumber == nil)
}

@Test func cycleIsRefusedWhenTwoUnitsShareThePort() {
    let sim = FakeLogicMCU.project(tracks: 4)
    sim.secondUnit = true
    let backend = makeBackend(for: sim)
    sim.connect()
    #expect(backend.execute(.transportCycle(on: true)).error == "surface_conflict")
    #expect(sim.presses.isEmpty)
}
#endif
