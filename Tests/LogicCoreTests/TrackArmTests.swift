import Foundation
@testable import LogicCore

// `track arm <n> on|off`: the strip's REC button, verified by the REC LED only (Logic shows no text for it).
// FakeLogicMCU models what Logic is expected to do; this has NOT been checked on the real Logic yet
// (support-matrix: tested, not live).
#if canImport(Testing)
import Testing

private func recPresses(_ sim: FakeLogicMCU) -> Int { sim.presses.filter { $0 < 0x08 }.count }

private func connected(tracks count: Int = 4) -> (FakeLogicMCU, MCUBackend) {
    let sim = FakeLogicMCU.project(tracks: count)
    let backend = makeBackend(for: sim)
    sim.connect()
    return (sim, backend)
}

@Test func armingAndDisarmingAreVerifiedByTheRecLED() {
    let (sim, backend) = connected()
    let on = backend.execute(.trackArm(track: 2, on: true))
    #expect(on.ok && on.verified)
    #expect(sim.strips[1].rec)
    #expect(on.observed?["rec_armed"] == .bool(true))
    let off = backend.execute(.trackArm(track: 2, on: false))
    #expect(off.ok && off.verified)
    #expect(!sim.strips[1].rec)
    #expect(recPresses(sim) == 2)
}

@Test func anAlreadyArmedStripIsAVerifiedNoOpWithoutAPress() {
    let (sim, backend) = connected()
    _ = backend.execute(.trackArm(track: 1, on: true))
    let before = recPresses(sim)
    let again = backend.execute(.trackArm(track: 1, on: true))
    #expect(again.ok && again.verified)
    #expect(recPresses(sim) == before)
}

@Test func aStripThatCannotBeArmedFailsVerificationAndIsPressedOnce() {
    let (sim, backend) = connected(tracks: 4)          // positions 5 and 6 are St Out and Master
    let outcome = backend.execute(.trackArm(track: 5, on: true))
    #expect(!outcome.verified)
    #expect(outcome.error == "verification_failed")
    #expect(!sim.strips[4].rec)
    #expect(recPresses(sim) == 1)                      // no second press when nothing answered
}

@Test func anUnknownStartingStateIsCorrectedWhenTheFirstPressGoesTheWrongWay() {
    let sim = FakeLogicMCU.project(tracks: 4)
    sim.withholdLEDDump = true                         // the REC LEDs are not reported at connection
    sim.strips[2].rec = true                           // the strip is already armed, but nobody knows
    let backend = makeBackend(for: sim)
    sim.connect()
    let outcome = backend.execute(.trackArm(track: 3, on: true))
    #expect(outcome.ok && outcome.verified)
    #expect(sim.strips[2].rec)
    #expect(recPresses(sim) == 2)                      // off, then on again
}

@Test func theExpectedNameGuardsArmLikeEveryTrackCommand() {
    let (sim, backend) = connected()
    _ = backend.execute(.trackList)
    let refused = backend.execute(.trackArm(track: 3, on: true), expectName: "T02")
    #expect(refused.error == "target_mismatch")
    #expect(recPresses(sim) == 0)
    let allowed = backend.execute(.trackArm(track: 3, on: true), expectName: "T03")
    #expect(allowed.ok && allowed.verified)
}

@Test func armIsAWriteThatTheCommandLineAndTheWireAccept() throws {
    let request = try CLIParser.parse(["track", "arm", "3", "on"])
    #expect(request.command == "track.arm")
    #expect(try LogicCommand(request: request) == .trackArm(track: 3, on: true))
    #expect(LogicCommand.trackArm(track: 3, on: true).isWrite)
    #expect(LogicCommand.isWrite(named: "track.arm"))
    #expect(throws: CommandError.self) { try LogicCommand(request: try CLIParser.parse(["track", "arm", "3", "maybe"])) }
    let guarded = try CLIParser.parse(["track", "arm", "3", "off", "--expect-name", "T03"])
    #expect(guarded.args[LogicCommand.expectNameKey] == "T03")
}
#endif
