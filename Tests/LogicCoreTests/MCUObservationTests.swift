import Foundation
@testable import LogicCore

// Failure tests for the observation contract (docs/observation-contract.md):
// an unreported value is unknown, never false; a scan that cannot prove it saw
// everything is never an empty or shorter success; old session data is never served.
#if canImport(Testing)
import Testing

private func tracks(_ outcome: Outcome) -> [JSONValue] {
    if case .array(let items) = outcome.result ?? .null { return items }
    return []
}

private func extra(_ outcome: Outcome, _ key: String) -> JSONValue? { outcome.observation?[key] }

@Test func completeScanListsEveryStripAndProvesTheEnd() {
    let sim = FakeLogicMCU.project(tracks: 10)  // 10 tracks + St Out + Master = 12 strips
    let backend = makeBackend(for: sim)
    sim.connect()

    let outcome = backend.execute(.trackList)
    #expect(outcome.ok)
    #expect(tracks(outcome).map { $0["id"] } == (1...12).map { JSONValue.int($0) })
    #expect(tracks(outcome).last?["name"] == .string("Master"))
    #expect(extra(outcome, "complete") == .bool(true))
    #expect(extra(outcome, "end") == .string("channel_right_and_bank_right_silent"))
    #expect(extra(outcome, "bank_steps") == .int(4))
    // Master has no pan: unavailable, not unknown.
    #expect(tracks(outcome).last?["unavailable"] == .array([.string("pan")]))
    #expect(tracks(outcome).first?["unknown"] == .array([]))
}

@Test func bankThatCannotBeHomedIsAnErrorNotAnEmptyList() {
    let sim = FakeLogicMCU.project(tracks: 10)
    sim.alwaysMoveOnBankLeft = true
    let backend = makeBackend(for: sim)
    sim.connect()

    let outcome = backend.execute(.trackList)
    #expect(!outcome.ok)
    #expect(outcome.error == "bank_home_failed")
    #expect(extra(outcome, "complete") == .bool(false))

    let state = backend.execute(.state)
    #expect(!state.ok)  // never "ok with no tracks"
    #expect(state.result?["selected_track"] == .null)
}

@Test func droppedChannelRightIsNotTakenForTheEndOfTheList() {
    let sim = FakeLogicMCU.project(tracks: 10)
    sim.dropChannelRight = 1  // one lost press during the first attempt
    let backend = makeBackend(for: sim)
    sim.connect()

    let outcome = backend.execute(.trackList)
    #expect(outcome.ok)
    #expect(tracks(outcome).count == 12)
    #expect(extra(outcome, "attempts") == .int(2))  // the first attempt noticed and started over
}

@Test func brokenChannelRightYieldsAnIncompleteResultNotAShorterSuccess() {
    let sim = FakeLogicMCU.project(tracks: 10)
    sim.dropAllChannelRight = true
    let backend = makeBackend(for: sim)
    sim.connect()

    let outcome = backend.execute(.trackList)
    #expect(!outcome.ok)
    #expect(outcome.error == "scan_incomplete")
    #expect(extra(outcome, "complete") == .bool(false))
    #expect(extra(outcome, "problem") == .string("end_not_confirmed"))
    #expect(tracks(outcome).count == 8)  // only what was really seen
}

@Test func anUnrelatedBankMoveDuringAStepIsDetected() {
    let sim = FakeLogicMCU.project(tracks: 10)
    sim.duplicateColourOnNavigation = 3  // two bank moves landed together once
    let backend = makeBackend(for: sim)
    sim.connect()

    let outcome = backend.execute(.trackList)
    #expect(outcome.ok)
    #expect(extra(outcome, "attempts") == .int(2))
    // ids still match the strips they were read from
    for (index, track) in tracks(outcome).enumerated() {
        #expect(track["id"] == .int(index + 1))
    }

    let bad = FakeLogicMCU.project(tracks: 10)
    bad.alwaysDuplicateColour = true
    let badBackend = makeBackend(for: bad)
    bad.connect()
    let failed = badBackend.execute(.trackList)
    #expect(!failed.ok)
    #expect(failed.error == "scan_incomplete")
    #expect(extra(failed, "problem") == .string("bank_moved_externally"))
}

@Test func ledsLogicNeverReportedAreNullAndListedAsUnknown() {
    let sim = FakeLogicMCU.project(tracks: 3)
    sim.withholdLEDDump = true
    let backend = makeBackend(for: sim)
    sim.connect()

    let get = backend.execute(.trackGet(track: 1))
    #expect(get.ok)
    for key in ["mute", "solo", "selected", "rec_armed"] {
        #expect(get.result?[key] == .null, "\(key) must be null, not false")
    }
    #expect(get.result?["unknown"] == .array(["solo", "selected", "rec_armed", "mute"]))
    #expect(extra(get, "complete") == .bool(false))

    let status = backend.execute(.status)
    #expect(status.result?["transport"]?["playing"] == .null)
    #expect(status.result?["transport"]?["recording"] == .null)
}

@Test func muteOffIsNotClaimedAsAnAlreadySatisfiedNoOpWithoutEvidence() {
    for actuallyMuted in [true, false] {
        let sim = FakeLogicMCU.project(tracks: 3)
        sim.withholdLEDDump = true
        sim.strips[0].mute = actuallyMuted
        let backend = makeBackend(for: sim)
        sim.connect()

        let outcome = backend.execute(.trackMute(track: 1, on: false))
        #expect(outcome.ok && outcome.verified)
        #expect(outcome.message?.contains("既に") != true)  // it did not skip on the strength of a default
        #expect(!sim.strips[0].mute)  // and the end state really is "off"
        #expect(sim.presses.filter { $0 == MCU.muteNote(0) }.count == (actuallyMuted ? 1 : 2))
    }
}

@Test func transportIsNotSentWhileItsStateIsUnknown() {
    let sim = FakeLogicMCU.project(tracks: 3)
    sim.withholdTransportLEDs = true
    let backend = makeBackend(for: sim)
    sim.connect()

    for command in [LogicCommand.transportStop, .transportPlay] {
        let outcome = backend.execute(command)
        #expect(!outcome.ok && !outcome.verified)
        #expect(outcome.error == "readback_unavailable")
    }
    #expect(!sim.presses.contains(MCU.stopNote) && !sim.presses.contains(MCU.playNote))
}

@Test func stopWhenReportedStoppedIsAVerifiedNoOpAndSendsNothing() {
    let sim = FakeLogicMCU.project(tracks: 3)
    let backend = makeBackend(for: sim)
    sim.connect()

    let outcome = backend.execute(.transportStop)
    #expect(outcome.ok && outcome.verified)
    #expect(!sim.presses.contains(MCU.stopNote))  // a second Stop would rewind
}

@Test func aReconnectWithoutADumpNeverServesTheOldSession() {
    let sim = FakeLogicMCU.project(tracks: 3)
    let backend = makeBackend(for: sim)
    sim.connect()
    #expect(backend.execute(.trackGet(track: 1)).ok)

    sim.connect(withholdDump: true)  // Logic asks again (project changed), then goes quiet
    let outcome = backend.execute(.trackGet(track: 1))
    #expect(!outcome.ok)
    #expect(outcome.error == "surface_not_connected")
    #expect(outcome.result == nil)  // no name, no volume from the previous session
}

@Test func volumeIsReadFromTheShiftedTextOnTheLastStrip() {
    // Track 9 sits on the last of the eight strips when the bank is at offset 1.
    let sim = FakeLogicMCU.project(tracks: 10)
    let backend = makeBackend(for: sim)
    sim.connect()

    for track in 1...12 {
        for db in [-6.0, -3.7, 0.0] {
            let outcome = backend.execute(.trackVolume(track: track, db: db, tolerance: 0.1))
            #expect(outcome.ok && outcome.verified, "track \(track) at \(db) dB: \(outcome.error ?? "-")")
        }
    }
    // every position of the bank was exercised, including the last strip
    #expect(sim.presses.contains(MCU.channelRightNote))
    #expect(backend.execute(.trackGet(track: 9)).result?["volume_db"] == .number(0))
}

@Test func handshakeForgetsWhichLEDsWereReported() {
    var surface = MCUSurface()
    _ = surface.feed([0x90, MCU.muteNote(0), 0x00])
    #expect(surface.ledIfKnown(MCU.muteNote(0)) == false)
    #expect(surface.ledIfKnown(MCU.muteNote(1)) == nil)
    _ = surface.feed(MCU.sysexHeader + [0x00, 0xF7])
    #expect(surface.ledIfKnown(MCU.muteNote(0)) == nil)
}
#endif
