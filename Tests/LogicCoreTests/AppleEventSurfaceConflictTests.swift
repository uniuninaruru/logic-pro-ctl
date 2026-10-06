import Foundation
@testable import LogicCore

#if canImport(Testing)
import Testing

private final class ConflictAEFakeSender: AppleEventTransportSending {
    var commands: [Int16] = []
    var onSend: (() -> Void)?
    func send(commandID: Int16, target: LogicAppInfo) -> AppleEventSendResult {
        commands.append(commandID)
        onSend?()
        return AppleEventSendResult(sendStatus: 0, replyError: 0, replyReceived: true)
    }
}

private func conflictAEApp() -> LogicAppInfo {
    LogicAppInfo(pid: 4242, bundleID: "test.logic", name: "Test Logic",
                 version: "12.3.1", build: "6682", path: nil)
}

@Test func aeKnownSurfaceConflictBlocksWriteAndAlreadyMatchingNoOp() {
    for alreadyPlaying in [false, true] {
        let sim = FakeLogicMCU.project(tracks: 12)
        sim.secondUnit = true
        sim.playing = alreadyPlaying
        let readback = makeBackend(for: sim)
        sim.connect()
        let sender = ConflictAEFakeSender()
        sender.onSend = { readback.ingest([0x90, MCU.playNote, 0x7F]) }
        let backend = AppleEventTransportBackend(readback: readback, sender: sender,
                                                appProvider: conflictAEApp, verificationTimeout: 0)
        let outcome = backend.execute(.transportPlay)
        #expect(outcome.error == "surface_conflict")
        #expect(!outcome.ok && !outcome.verified)
        #expect(outcome.result?["sent"] == .bool(false))
        #expect(sender.commands.isEmpty)
        #expect(sim.presses.isEmpty)
        #expect(readback.transportSnapshot() == nil)
        withExtendedLifetime(sim) {}
    }
}

@Test func aeConflictArrivingAfterSendCannotVerifyFromAmbiguousLEDs() {
    let sim = FakeLogicMCU.project(tracks: 12)
    let readback = makeBackend(for: sim)
    sim.connect()
    let sender = ConflictAEFakeSender()
    sender.onSend = {
        // Two different complete LCD dumps in the same session: do not rely on a
        // new handshake to invalidate readback. These have the live dump length.
        for name in ["FIRST", "SECOND"] {
            let row = Array(name.padding(toLength: 56, withPad: " ", startingAt: 0).utf8)
            readback.ingest(MCU.sysexHeader + [0x12, 0] + row + Array(repeating: 0x20, count: 55) + [0xF7])
        }
        readback.ingest([0x90, MCU.playNote, 0x7F])
    }
    let backend = AppleEventTransportBackend(readback: readback, sender: sender,
                                            appProvider: conflictAEApp, verificationTimeout: 0)
    let outcome = backend.execute(.transportPlay)
    #expect(sender.commands == [3])
    #expect(outcome.result?["sent"] == .bool(true))
    #expect(outcome.error == "readback_unavailable")
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.observed == nil)
    #expect(readback.transportSnapshot() == nil)
    #expect(sim.presses.isEmpty)
    withExtendedLifetime(sim) {}
}
#endif
