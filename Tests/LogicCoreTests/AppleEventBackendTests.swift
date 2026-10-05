import Carbon
import Foundation
@testable import LogicCore

#if canImport(Testing)
import Testing

private func aeTestApp(pid: Int32 = 12345, version: String? = "12.3.1", build: String? = "6682") -> LogicAppInfo {
    LogicAppInfo(pid: pid, bundleID: "test.logic", name: "Test Logic",
                 version: version, build: build, path: "/test/Logic.app")
}

private final class AEFakeSender: AppleEventTransportSending {
    var reply = AppleEventSendResult(sendStatus: 0, replyError: 0, replyReceived: true)
    var commands: [(Int16, Int32)] = []
    var onSend: (() -> Void)?

    func send(commandID: Int16, target: LogicAppInfo) -> AppleEventSendResult {
        commands.append((commandID, target.pid))
        onSend?()
        return reply
    }
}

private final class AEFakeReadback: TransportReadback {
    var snapshot: TransportSnapshot?
    var afterWait: TransportSnapshot?
    var prepareFailure: Outcome?
    var prepares = 0
    var onPrepare: (() -> Void)?
    var waits: [(Bool, Bool?, TimeInterval)] = []
    var onWait: ((Bool, Bool?, TimeInterval) -> TransportSnapshot?)?

    init(playing: Bool = false, recording: Bool = false) {
        snapshot = TransportSnapshot(playing: playing, recording: recording)
        afterWait = snapshot
    }

    func prepareTransportReadback() -> Outcome? {
        prepares += 1
        onPrepare?()
        return prepareFailure
    }

    func transportSnapshot() -> TransportSnapshot? { snapshot }

    func waitForTransport(playing: Bool, recording: Bool?, timeout: TimeInterval) -> TransportSnapshot? {
        waits.append((playing, recording, timeout))
        if let onWait { snapshot = onWait(playing, recording, timeout) }
        else { snapshot = afterWait }
        return snapshot
    }
}

@Test func aePlayRequiresBothAcknowledgmentAndReadback() {
    let readback = AEFakeReadback()
    readback.afterWait = TransportSnapshot(playing: true, recording: false)
    let sender = AEFakeSender()
    let backend = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }, verificationTimeout: 0.25)
    let outcome = backend.execute(.transportPlay)
    #expect(outcome.ok && outcome.verified)
    #expect(outcome.requested == ["playing": true])
    #expect(outcome.observed == ["playing": true, "recording": false])
    #expect(sender.commands.count == 1)
    #expect(sender.commands.first?.0 == 3)
    #expect(sender.commands.first?.1 == 12345)
    #expect(readback.waits.first?.0 == true)
    #expect(readback.waits.first?.1 == nil)
    #expect(readback.waits.first?.2 == 0.25)
    #expect(outcome.result?["sent"] == true)
    #expect(outcome.result?["appleevent_send_status"] == 0)
    #expect(outcome.result?["appleevent_reply_error"] == 0)
}

@Test func aeAcknowledgmentWithoutStateChangeFails() {
    let readback = AEFakeReadback()
    let sender = AEFakeSender()
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportPlay)
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.error == "verification_failed")
    #expect(outcome.observed?["playing"] == false)
    #expect(sender.commands.count == 1)
    #expect(readback.waits.count == 1)
}

@Test func aeMissingRunningLogicDoesNotPrepareOrSend() {
    let readback = AEFakeReadback()
    let sender = AEFakeSender()
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { nil }).execute(.transportPlay)
    #expect(outcome.error == "logic_not_running")
    #expect(!outcome.ok && !outcome.verified)
    #expect(readback.prepares == 0)
    #expect(sender.commands.isEmpty)
    #expect(outcome.result?["sent"] == false)
    #expect(outcome.result?["appleevent_send_status"] == .null)
}

@Test func aeUnsupportedVersionsDoNotSend() {
    let profiles: [(String?, String?)] = [("12.3.2", "6682"), ("12.3.1", "6683"),
                                         (nil, "6682"), ("12.3.1", nil), (nil, nil)]
    for (version, build) in profiles {
        let readback = AEFakeReadback()
        let sender = AEFakeSender()
        let app = aeTestApp(version: version, build: build)
        let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                                 appProvider: { app }).execute(.transportPlay)
        #expect(outcome.error == "unsupported_logic_version")
        #expect(!outcome.ok && !outcome.verified)
        #expect(!AppleEventTransportBackend.supports(app))
        #expect(readback.prepares == 0 && sender.commands.isEmpty)
        #expect(outcome.result?["logic_version"] == .string(version))
        #expect(outcome.result?["logic_build"] == .string(build))
    }
}

@Test func aeUnavailableReadbackBlocksAllWrites() {
    let readback = AEFakeReadback()
    readback.prepareFailure = .failure("readback_unavailable", "no handshake")
    let sender = AEFakeSender()
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportPlay)
    #expect(outcome.error == "readback_unavailable")
    #expect(!outcome.ok && !outcome.verified)
    #expect(readback.prepares == 1)
    #expect(sender.commands.isEmpty && readback.waits.isEmpty)
    #expect(outcome.requested == ["playing": true])
    #expect(outcome.result?["sent"] == false)
}

@Test func aeUnknownInitialLEDStateCannotBecomeVerifiedNoOp() {
    let readback = AEFakeReadback()
    readback.snapshot = nil
    let sender = AEFakeSender()
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportStop)
    #expect(outcome.error == "readback_unavailable")
    #expect(!outcome.ok && !outcome.verified)
    #expect(sender.commands.isEmpty)
}

@Test func aeAlreadyPlayingAndStoppedAvoidRedundantEvents() {
    for play in [false, true] {
        let readback = AEFakeReadback(playing: play)
        let sender = AEFakeSender()
        let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                                 appProvider: { aeTestApp() }).execute(play ? .transportPlay : .transportStop)
        #expect(outcome.ok && outcome.verified)
        #expect(outcome.result?["sent"] == false)
        #expect(outcome.result?["appleevent_send_status"] == .null)
        #expect(outcome.result?["appleevent_reply_error"] == .null)
        #expect(sender.commands.isEmpty && readback.waits.isEmpty)
    }
}

@Test func aeStopMustAlsoEndRecording() {
    let readback = AEFakeReadback(playing: false, recording: true)
    readback.afterWait = TransportSnapshot(playing: false, recording: false)
    let sender = AEFakeSender()
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportStop)
    #expect(outcome.ok && outcome.verified)
    #expect(sender.commands.count == 1 && sender.commands.first?.0 == 5)
    #expect(readback.waits.first?.1 == false)
    #expect(outcome.requested == ["playing": false, "recording": false])
}

@Test func aeStopWithRecordingStillOnFailsVerification() {
    let readback = AEFakeReadback(playing: true, recording: true)
    readback.afterWait = TransportSnapshot(playing: false, recording: true)
    let sender = AEFakeSender()
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportStop)
    #expect(outcome.error == "verification_failed")
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.observed?["recording"] == true)
}

@Test func aeSendErrorsRemainFailuresEvenIfReadbackMatches() {
    let cases: [(Int32, String)] = [(-1743, "appleevent_permission_denied"), (-1712, "appleevent_timeout"),
                                  (-1708, "appleevent_not_handled"), (-38, "no_project"),
                                  (-600, "appleevent_send_failed")]
    for (status, code) in cases {
        let readback = AEFakeReadback()
        readback.afterWait = TransportSnapshot(playing: true, recording: false)
        let sender = AEFakeSender()
        sender.reply = AppleEventSendResult(sendStatus: status, replyError: nil, replyReceived: false)
        let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                                 appProvider: { aeTestApp() }).execute(.transportPlay)
        #expect(outcome.error == code)
        #expect(!outcome.ok && !outcome.verified)
        #expect(readback.waits.count == 1 && sender.commands.count == 1)
        #expect(outcome.observed?["playing"] == true)
        #expect(outcome.result?["appleevent_send_status"] == .int(Int(status)))
        #expect(outcome.result?["appleevent_reply_error"] == .null)
    }
}

@Test func aeReplyErrorsRemainSeparateFromSuccessfulDelivery() {
    let cases: [(Int32, String)] = [(-1743, "appleevent_permission_denied"), (-1712, "appleevent_timeout"),
                                  (-1708, "appleevent_not_handled"), (-38, "no_project"),
                                  (-1701, "appleevent_reply_failed")]
    for (replyError, code) in cases {
        let readback = AEFakeReadback()
        readback.afterWait = TransportSnapshot(playing: true, recording: false)
        let sender = AEFakeSender()
        sender.reply = AppleEventSendResult(sendStatus: 0, replyError: replyError, replyReceived: true)
        let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                                 appProvider: { aeTestApp() }).execute(.transportPlay)
        #expect(outcome.error == code)
        #expect(!outcome.ok && !outcome.verified)
        #expect(outcome.result?["appleevent_send_status"] == 0)
        #expect(outcome.result?["appleevent_reply_error"] == .int(Int(replyError)))
        #expect(readback.waits.count == 1)
    }
}

@Test func aeMissingReplyCannotClaimAcknowledgment() {
    let readback = AEFakeReadback()
    readback.afterWait = TransportSnapshot(playing: true, recording: false)
    let sender = AEFakeSender()
    sender.reply = AppleEventSendResult(sendStatus: 0, replyError: nil, replyReceived: false)
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportPlay)
    #expect(outcome.error == "appleevent_invalid_reply")
    #expect(!outcome.verified)
    #expect(outcome.result?["appleevent_reply_error"] == .null)
    #expect(readback.waits.count == 1)
}

@Test func aeMalformedReplyErrorCannotClaimAcknowledgment() {
    let readback = AEFakeReadback()
    readback.afterWait = TransportSnapshot(playing: true, recording: false)
    let sender = AEFakeSender()
    sender.reply = AppleEventSendResult(sendStatus: 0, replyError: nil, replyReceived: true, replyValid: false)
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportPlay)
    #expect(outcome.error == "appleevent_invalid_reply")
    #expect(!outcome.ok && !outcome.verified)
    #expect(readback.waits.count == 1)
}

@Test func aeValidReplyMayOmitErrorNumberWithoutInventingZero() {
    let readback = AEFakeReadback()
    readback.afterWait = TransportSnapshot(playing: true, recording: false)
    let sender = AEFakeSender()
    sender.reply = AppleEventSendResult(sendStatus: 0, replyError: nil, replyReceived: true)
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportPlay)
    #expect(outcome.ok && outcome.verified)
    #expect(outcome.result?["appleevent_reply_error"] == .null)
    #expect(outcome.result?["appleevent_reply_received"] == true)
}

@Test func aeReadbackLostAfterSuccessfulSendIsUnverified() {
    let readback = AEFakeReadback()
    readback.afterWait = nil
    let sender = AEFakeSender()
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportPlay)
    #expect(outcome.error == "readback_unavailable")
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.observed == nil)
    #expect(outcome.result?["sent"] == true)
}

/// A disconnected readback can retain a matching cache without making that
/// cache trustworthy for this write. `nil` from the wait must remain decisive.
private final class AENilWaitCachedReadback: TransportReadback {
    var cached = TransportSnapshot(playing: false, recording: false)
    var waits = 0

    func prepareTransportReadback() -> Outcome? { nil }
    func transportSnapshot() -> TransportSnapshot? { cached }
    func waitForTransport(playing: Bool, recording: Bool?, timeout: TimeInterval) -> TransportSnapshot? {
        waits += 1
        return nil
    }
}

@Test func aeUnavailableWaitCannotFallBackToMatchingCachedSnapshot() {
    let readback = AENilWaitCachedReadback()
    let sender = AEFakeSender()
    sender.onSend = { readback.cached = TransportSnapshot(playing: true, recording: false) }
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }).execute(.transportPlay)
    #expect(readback.transportSnapshot()?.playing == true)
    #expect(readback.waits == 1 && sender.commands.count == 1)
    #expect(outcome.error == "readback_unavailable")
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.observed == nil)
    #expect(outcome.result?["sent"] == true)
}

@Test func aeUnsupportedCommandsNeverPrepareOrSend() {
    let readback = AEFakeReadback()
    let sender = AEFakeSender()
    let commands: [LogicCommand] = [.status, .state, .trackList, .trackMute(track: 1, on: true),
                                    .daemonStop, .debugMCU(messages: [[0x90, 0x5E, 0x7F]])]
    let backend = AppleEventTransportBackend(readback: readback, sender: sender, appProvider: { aeTestApp() })
    for command in commands {
        let outcome = backend.execute(command)
        #expect(outcome.error == "unsupported_backend_command")
        #expect(!outcome.ok && !outcome.verified)
    }
    #expect(readback.prepares == 0 && sender.commands.isEmpty)
}

@Test func aeRestartBetweenPreflightAndSendNeverRetargets() {
    let readback = AEFakeReadback()
    let sender = AEFakeSender()
    var calls = 0
    let backend = AppleEventTransportBackend(readback: readback, sender: sender, appProvider: {
        calls += 1
        return aeTestApp(pid: calls == 1 ? 12345 : 23456)
    })
    let outcome = backend.execute(.transportPlay)
    #expect(outcome.error == "logic_instance_changed")
    #expect(!outcome.ok && !outcome.verified)
    #expect(sender.commands.isEmpty && readback.waits.isEmpty)
}

@Test func aeRestartDuringPreparationCannotVerifyAlreadySatisfiedNoOp() {
    let readback = AEFakeReadback(playing: true)
    let sender = AEFakeSender()
    var currentApp = aeTestApp(pid: 12345)
    readback.onPrepare = { currentApp = aeTestApp(pid: 23456) }
    let outcome = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { currentApp }).execute(.transportPlay)
    #expect(readback.prepares == 1)
    #expect(outcome.error == "logic_instance_changed")
    #expect(!outcome.ok && !outcome.verified)
    #expect(outcome.result?["sent"] == false)
    #expect(outcome.result?["target_pid"] == 23456)
    #expect(sender.commands.isEmpty && readback.waits.isEmpty)
}

@Test func aeAppExitBetweenPreflightAndSendBlocksWrite() {
    let readback = AEFakeReadback()
    let sender = AEFakeSender()
    var calls = 0
    let backend = AppleEventTransportBackend(readback: readback, sender: sender, appProvider: {
        calls += 1
        return calls == 1 ? aeTestApp() : nil
    })
    let outcome = backend.execute(.transportPlay)
    #expect(outcome.error == "logic_not_running")
    #expect(sender.commands.isEmpty)
}

/// Unlike an immediately returning fake, this readback exercises waiting for
/// asynchronous feedback without sending MIDI or AppleEvents to any application.
private final class AEAsyncReadback: TransportReadback, @unchecked Sendable {
    private let condition = NSCondition()
    private var snapshot = TransportSnapshot(playing: false, recording: false)

    func prepareTransportReadback() -> Outcome? { nil }
    func transportSnapshot() -> TransportSnapshot? {
        condition.lock()
        defer { condition.unlock() }
        return snapshot
    }
    func receive(_ value: TransportSnapshot) {
        condition.lock()
        snapshot = value
        condition.broadcast()
        condition.unlock()
    }
    func waitForTransport(playing: Bool, recording: Bool?, timeout: TimeInterval) -> TransportSnapshot? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while snapshot.playing != playing || (recording != nil && snapshot.recording != recording) {
            if !condition.wait(until: deadline) { break }
        }
        return snapshot
    }
}

@Test func aeWaitObservesAsynchronousFeedback() {
    let readback = AEAsyncReadback()
    let sender = AEFakeSender()
    // Verify delayed feedback, allowing scheduling headroom when the suite runs under load.
    // The condition wakes as soon as feedback arrives; this does not change the production timeout.
    let backend = AppleEventTransportBackend(readback: readback, sender: sender,
                                             appProvider: { aeTestApp() }, verificationTimeout: 5)
    sender.onSend = {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) {
            readback.receive(TransportSnapshot(playing: true, recording: false))
        }
    }
    let outcome = backend.execute(.transportPlay)
    #expect(outcome.ok && outcome.verified)
    #expect(sender.commands.count == 1)
}

@Test func aeNativeDescriptorUsesLongIntegersAndExactPID() throws {
    for (commandID, value) in [(Int16(3), Int32(-3)), (Int16(5), Int32(-5))] {
        let event = NativeAppleEventTransportSender.event(commandID: commandID, targetPID: 12345)
        let mode = try #require(event.paramDescriptor(forKeyword: NativeAppleEventTransportSender.modeKeyword))
        let command = try #require(event.paramDescriptor(forKeyword: NativeAppleEventTransportSender.commandKeyword))
        let target = try #require(event.attributeDescriptor(forKeyword: keyAddressAttr))
        #expect(event.attributeDescriptor(forKeyword: keyEventClassAttr)?.typeCodeValue == NativeAppleEventTransportSender.eventClass)
        #expect(event.attributeDescriptor(forKeyword: keyEventIDAttr)?.typeCodeValue == NativeAppleEventTransportSender.eventID)
        #expect(mode.descriptorType == typeSInt32 && mode.int32Value == 6)
        #expect(command.descriptorType == typeSInt32 && command.int32Value == value)
        #expect(target.descriptorType == typeKernelProcessID)
        let pid = target.data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        #expect(pid == 12345)
        #expect(NativeAppleEventTransportSender.timeoutTicks == 300)
        #expect(NativeAppleEventTransportSender.sendMode == AESendMode(kAEWaitReply | kAENeverInteract | kAEDontRecord))
    }
}

@Test func aeNativeSenderRejectsUnvalidatedCallsWithoutSending() {
    let sender = NativeAppleEventTransportSender()
    for (command, target) in [(Int16(7), aeTestApp()), (Int16(3), aeTestApp(version: "12.4"))] {
        let result = sender.send(commandID: command, target: target)
        #expect(!result.sent && !result.succeeded)
        #expect(result.replyError == nil && !result.replyReceived)
    }
}
#endif
