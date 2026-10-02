import Foundation
@testable import LogicCore

// The target contract (docs/target-contract.md): a track number is a mixer position, so a
// write that names the strip it expects is refused, with nothing sent, when the strip at that
// position is no longer the one the caller read.
#if canImport(Testing)
import Testing

private func tracks(_ outcome: Outcome) -> [JSONValue] {
    if case .array(let items) = outcome.result ?? .null { return items }
    return []
}

private func muteButtonsPressed(_ sim: FakeLogicMCU) -> Int {
    sim.presses.filter { (0x10..<0x18).contains($0) }.count
}

private func connected(tracks count: Int = 10) -> (FakeLogicMCU, MCUBackend) {
    let sim = FakeLogicMCU.project(tracks: count)
    let backend = makeBackend(for: sim)
    sim.connect()
    return (sim, backend)
}

@Test func aMatchingNameLetsTheWriteThroughAndSaysWhatWasChecked() {
    let (sim, backend) = connected()
    _ = backend.execute(.trackList)

    let outcome = backend.execute(.trackMute(track: 3, on: true), expectName: "T03")
    #expect(outcome.ok && outcome.verified)
    #expect(sim.strips[2].mute)
    #expect(outcome.result?["target"]?["name"] == .string("T03"))
    #expect(outcome.result?["target"]?["matched_expected_name"] == .bool(true))
    #expect(outcome.result?["target"]?["identity_scope"] == .string("mixer_position"))
}

@Test func spacesAroundTheExpectedNameAreIgnoredButCaseIsNot() {
    let (sim, backend) = connected()
    withExtendedLifetime(sim) {
        #expect(backend.execute(.trackGet(track: 3), expectName: "  T03 ").ok)
        #expect(backend.execute(.trackGet(track: 3), expectName: "t03").error == "target_mismatch")
    }
}

@Test func aRenamedTrackIsRefusedAndNothingIsSent() {
    let (sim, backend) = connected()
    _ = backend.execute(.trackList)
    sim.rename(2, to: "Vox")
    let pressesBefore = muteButtonsPressed(sim)

    let outcome = backend.execute(.trackMute(track: 3, on: true), expectName: "T03")
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.error == "target_mismatch")
    #expect(outcome.observed?["name"] == .string("Vox"))
    #expect(outcome.requested?["expect_name"] == .string("T03"))
    #expect(muteButtonsPressed(sim) == pressesBefore)
    #expect(!sim.strips[2].mute)
    // The caller can follow the new name explicitly.
    #expect(backend.execute(.trackMute(track: 3, on: true), expectName: "Vox").ok)
}

@Test func swappingTwoTracksIsDetectedAtBothPositions() {
    let (sim, backend) = connected()
    _ = backend.execute(.trackList)
    sim.swapStrips(0, 1)

    for (track, was, now) in [(1, "T01", "T02"), (2, "T02", "T01")] {
        let outcome = backend.execute(.trackMute(track: track, on: true), expectName: was)
        #expect(outcome.error == "target_mismatch")
        #expect(outcome.observed?["name"] == .string(now))
    }
    #expect(muteButtonsPressed(sim) == 0)
    #expect(backend.execute(.trackMute(track: 1, on: true), expectName: "T02").ok)
    #expect(sim.strips[0].name == "T02" && sim.strips[0].mute)
}

@Test func deletingATrackShiftsEveryLaterPositionAndIsDetected() {
    let (sim, backend) = connected()
    _ = backend.execute(.trackList)
    sim.removeStrip(at: 0)  // T05 is now track 4, and track 5 is T06

    #expect(backend.execute(.trackMute(track: 5, on: true), expectName: "T05").error == "target_mismatch")
    #expect(muteButtonsPressed(sim) == 0)
    #expect(backend.execute(.trackMute(track: 4, on: true), expectName: "T05").ok)
    #expect(sim.strips[3].name == "T05" && sim.strips[3].mute)
}

@Test func addingATrackBeforeTheTargetIsDetected() {
    let (sim, backend) = connected()
    _ = backend.execute(.trackList)
    sim.insertStrip(named: "New", at: 0)

    #expect(backend.execute(.trackSolo(track: 5, on: true), expectName: "T05").error == "target_mismatch")
    #expect(!sim.strips.contains { $0.solo })
}

@Test func aBankShiftWithoutAColourSignalIsStillNoticed() {
    // Real Logic (EXP-MCU-023): deleting a track while the bank sat at its end redrew the names
    // one strip over and clamped the bank, with no colour sysex. The old offset must not be trusted.
    let sim = FakeLogicMCU.project(tracks: 11)  // 13 strips: the last bank starts at strip 6
    let backend = makeBackend(for: sim)
    sim.connect()
    #expect(backend.execute(.trackGet(track: 13), expectName: "Master").ok)  // bank offset 5
    sim.removeStrip(at: 5, colourSignal: false)  // T06 is gone: 12 strips, the bank clamps to offset 4

    // Track 8 is now T09; the old offset 5 would have read the cell that shows T08.
    let eighth = backend.execute(.trackGet(track: 8), expectName: "T09")
    #expect(eighth.ok)
    #expect(eighth.result?["name"] == .string("T09"))
    #expect(backend.execute(.trackGet(track: 8), expectName: "T08").error == "target_mismatch")
    // And a track number past the end is no track, not the last cell of a stale view.
    #expect(backend.execute(.trackGet(track: 13)).error == "no_such_track")
}

@Test func theCheckAlsoWorksAfterTheBankHasToBeMovedToReachTheTarget() {
    let (sim, backend) = connected()  // 12 strips: track 11 is only on the second bank view
    _ = backend.execute(.trackList)
    sim.rename(10, to: "Bus 1")
    #expect(backend.execute(.trackMute(track: 11, on: true), expectName: "St Out").error == "target_mismatch")
    #expect(backend.execute(.trackMute(track: 11, on: true), expectName: "Bus 1").ok)
}

@Test func everyTrackCommandIsGuardedAndSendsNothingOnAMismatch() {
    let commands: [LogicCommand] = [
        .trackSelect(track: 2), .trackMute(track: 2, on: true), .trackSolo(track: 2, on: true),
        .trackVolume(track: 2, db: -6, tolerance: 0.1), .trackPan(track: 2, pan: 0.5), .trackGet(track: 2),
    ]
    for command in commands {
        let (sim, backend) = connected()
        let before = sim.strips
        let outcome = backend.execute(command, expectName: "Wrong")
        #expect(outcome.error == "target_mismatch", "\(command)")
        #expect(sim.strips.map(\.fader) == before.map(\.fader), "\(command)")
        #expect(sim.strips.map(\.mute) == before.map(\.mute), "\(command)")
        #expect(sim.strips.map(\.solo) == before.map(\.solo), "\(command)")
        #expect(sim.selected == 0, "\(command)")
    }
}

@Test func aGuardedReadReturnsNoDataForTheWrongStrip() {
    let (sim, backend) = connected()
    withExtendedLifetime(sim) {
        let outcome = backend.execute(.trackGet(track: 4), expectName: "T05")
        #expect(outcome.error == "target_mismatch")
        #expect(outcome.result == nil)
    }
}

@Test func aNameCheckForACommandWithoutATrackIsRefusedBeforeAnythingIsSent() {
    let (sim, backend) = connected()
    let outcome = backend.execute(.transportPlay, expectName: "T01")
    #expect(outcome.error == "invalid_argument")
    #expect(!sim.presses.contains(MCU.playNote))
}

@Test func theSurfaceShowsOnlySevenCharactersSoLongerNamesLookTheSame() {
    // Two different tracks whose names differ only after the 7th character look identical on the
    // surface: the list says so (name_unique: false) and --expect-name cannot tell them apart.
    let sim = FakeLogicMCU(names: ["Guitar L", "Guitar R", "Master"])
    let backend = makeBackend(for: sim)
    sim.connect()
    let list = tracks(backend.execute(.trackList))
    #expect(list.map { $0["name"] } == [.string("Guitar"), .string("Guitar"), .string("Master")])
    #expect(list.map { $0["identity"]?["name_unique"] } == [.bool(false), .bool(false), .bool(true)])
}

@Test func theListMarksDisplayedNamesThatAreNotUnique() {
    let sim = FakeLogicMCU(names: ["Gtr", "Gtr", "Bass", "Master"])
    let backend = makeBackend(for: sim)
    sim.connect()
    let list = tracks(backend.execute(.trackList))

    #expect(list.map { $0["identity"]?["name_unique"] } == [.bool(false), .bool(false), .bool(true), .bool(true)])
    #expect(list.allSatisfy { $0["identity"]?["scope"] == .string("mixer_position") })
    #expect(list.allSatisfy { $0["identity"]?["stable_across_reorder"] == .bool(false) })
}

@Test func aNameCheckCannotTellTwoTracksWithTheSameDisplayedNameApart() {
    // The documented limit: swapping two identically named tracks is invisible to --expect-name,
    // and the list says so beforehand (name_unique: false).
    let sim = FakeLogicMCU(names: ["Gtr", "Gtr", "Bass", "Master"])
    let backend = makeBackend(for: sim)
    sim.connect()
    #expect(tracks(backend.execute(.trackList))[0]["identity"]?["name_unique"] == .bool(false))
    #expect(backend.execute(.trackMute(track: 2, on: true), expectName: "Gtr").ok)
}

@Test func uniquenessIsUnknownWhenTheScanIsIncompleteOrIsASingleRead() {
    let sim = FakeLogicMCU.project(tracks: 10)
    sim.dropAllChannelRight = true
    let backend = makeBackend(for: sim)
    sim.connect()
    let partial = backend.execute(.trackList)
    #expect(partial.observation?["complete"] == .bool(false))
    #expect(tracks(partial).allSatisfy { $0["identity"]?["name_unique"] == .null })

    let (otherSim, other) = connected()
    withExtendedLifetime(otherSim) {
        #expect(other.execute(.trackGet(track: 2)).result?["identity"]?["name_unique"] == .null)
    }
}

@Test func theNameArgumentIsValidatedWhereARequestBecomesACommand() throws {
    func command(_ name: String, _ args: [String: String]) throws -> LogicCommand {
        try LogicCommand(request: Request(command: name, args: args))
    }
    let ok = try command("track.mute", ["track": "3", "state": "on", "expect_name": "T03"])
    #expect(ok == .trackMute(track: 3, on: true))
    #expect(ok.trackNumber == 3)
    #expect(LogicCommand.transportPlay.trackNumber == nil && LogicCommand.trackList.trackNumber == nil)

    for bad in [("transport.play", [LogicCommand.expectNameKey: "x"]),
                ("track.list", [LogicCommand.expectNameKey: "x"]),
                ("track.mute", ["track": "3", "state": "on", LogicCommand.expectNameKey: "  "])] {
        #expect(throws: CommandError.self) { _ = try command(bad.0, bad.1) }
    }
}

@Test func theCommandLineAcceptsTheNameOnlyForTrackCommands() throws {
    let request = try CLIParser.parse(["track", "volume", "3", "-6", "--expect-name", "Drums", "--idempotency-key", "k1"])
    #expect(request.args[LogicCommand.expectNameKey] == "Drums")
    #expect(request.args["track"] == "3")

    let usage = [["track", "list", "--expect-name", "x"], ["transport", "play", "--expect-name", "x"],
                 ["track", "mute", "1", "on", "--expect-name", "   "], ["track", "mute", "1", "on", "--expect-name"],
                 ["track", "mute", "1", "on", "--expect-name", "a", "--expect-name", "b"]]
    for argv in usage {
        #expect(throws: CommandError.self) { _ = try CLIParser.parse(argv) }
    }
}

@Test func theExpectedNameIsPartOfWhatAKeyedRetryMeans() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    func run(_ name: String, _ body: @escaping () -> RoutedOutcome) -> ExecutionResult {
        let request = Request(command: "track.mute", args: ["track": "3", "state": "on", "expect_name": name],
                              idempotencyKey: "k1")
        return executor.execute(try! LogicCommand(request: request), request: request,
                                options: ExecutionOptions(request: request), run: body)
    }
    let first = run("T03") { RoutedOutcome(backend: "mcu", readbackBackend: nil, outcome: .failure("target_mismatch", "x")) }
    #expect(first.execution["state"] == .string("not_applied"))  // nothing reached Logic: the key stays usable
    let retried = run("T03") { RoutedOutcome(backend: "mcu", readbackBackend: nil, outcome: Outcome(ok: true, verified: true)) }
    #expect(retried.execution["state"] == .string("completed"))
    let other = run("Other") { RoutedOutcome(backend: "mcu", readbackBackend: nil, outcome: Outcome(ok: true, verified: true)) }
    #expect(other.routed.outcome.error == "idempotency_key_conflict")  // another expectation is another request
}
#endif
