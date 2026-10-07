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

@Test func aReconnectAfterThePressIsAnUnknownResultNotASecondPress() {
    // Review CDEX-022 (1): press, Logic re-runs the handshake, the new session shows REC off. Pressing again and
    // calling it verified would act on another session.
    let (sim, backend) = connected()
    sim.reconnectOnNextRecPress = true
    let outcome = backend.execute(.trackArm(track: 2, on: true))
    #expect(!outcome.verified)
    #expect(outcome.error == "session_changed")
    #expect(recPresses(sim) == 1)
    #expect(!WriteExecutor.notApplied.contains("session_changed"))   // a press was sent: unknown, never "nothing sent"
}

@Test func muteHasTheSameGuardAgainstAReconnectAfterThePress() {
    let (sim, backend) = connected()
    sim.reconnectOnNextMutePress = true
    let outcome = backend.execute(.trackMute(track: 2, on: true))
    #expect(outcome.error == "session_changed")
    #expect(sim.presses.filter { (0x10..<0x18).contains($0) }.count == 1)
}

// Review CDEX-024 (015): a reconnect during the LAST wait of a mute write must not end as verified.
@Test func aReconnectDuringTheFinalWaitOfMuteIsNotVerified() {
    let (sim, backend) = connected()
    var waitsAfterPress = 0
    backend.testHook = { point in
        guard point == "afterWait", sim.presses.contains(where: { (0x10..<0x18).contains($0) }) else { return }
        waitsAfterPress += 1
        if waitsAfterPress == 2 { sim.connect() }          // the new session also shows the strip muted
    }
    let outcome = backend.execute(.trackMute(track: 2, on: true))
    #expect(!outcome.verified)
    #expect(outcome.error == "session_changed")
}

// Review CDEX-024 (015): a reconnect just before the corrective second press stops it.
@Test func aReconnectBeforeTheSecondArmPressStopsIt() {
    let sim = FakeLogicMCU.project(tracks: 4)
    sim.withholdLEDDump = true
    sim.strips[2].rec = true                                // unknown start: the first press goes the wrong way
    let backend = makeBackend(for: sim)
    sim.connect()
    backend.testHook = { point in if point == "before-repress" { sim.connect() } }
    let outcome = backend.execute(.trackArm(track: 3, on: true))
    #expect(outcome.error == "session_changed")
    #expect(recPresses(sim) == 1)
}

// The gap that is not closed: a reconnect between the last check and the send. The press reaches the new
// session, but the result is still session_changed, never verified.
@Test func aReconnectBetweenTheCheckAndTheSendIsStillNotVerified() {
    let sim = FakeLogicMCU.project(tracks: 4)
    sim.withholdLEDDump = true
    sim.strips[2].rec = true
    let backend = makeBackend(for: sim)
    sim.connect()
    backend.testHook = { point in if point == "after-check-repress" { sim.connect() } }
    let outcome = backend.execute(.trackArm(track: 3, on: true))
    #expect(!outcome.verified)
    #expect(outcome.error == "session_changed")
    #expect(recPresses(sim) == 2)
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
// Real Logic blinks the REC LED of an armed track (EXP-REMOTE-006). A reading in the off phase is not "disarmed".
@Test func aBlinkingRecLEDCountsAsArmed() {
    let (sim, backend) = connected()
    sim.blinkRec = true
    let on = backend.execute(.trackArm(track: 2, on: true))
    #expect(on.ok && on.verified)
    #expect(sim.strips[1].rec)
    #expect(recPresses(sim) == 1)                      // no second press that would disarm it again
    sim.blinkTick()
    let again = backend.execute(.trackArm(track: 2, on: true))
    #expect(again.ok && again.verified)
    #expect(recPresses(sim) == 1)                      // armed and blinking: nothing sent
    sim.blinkTick()
    let off = backend.execute(.trackArm(track: 2, on: false))
    #expect(off.ok && off.verified)
    #expect(!sim.strips[1].rec)
    #expect(recPresses(sim) == 2)
}

@Test func aBlinkingArmedTrackReadsAsArmed() {
    let (sim, backend) = connected()
    sim.blinkRec = true
    _ = backend.execute(.trackArm(track: 2, on: true))
    sim.blinkTick()
    #expect(backend.execute(.trackGet(track: 2)).result?["rec_armed"] == .bool(true))
}
#endif
