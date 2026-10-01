import Carbon
import Foundation

/// A transport state actually received from Logic, rather than a decoder's defaults.
public struct TransportSnapshot: Equatable, Sendable {
    public var playing: Bool
    public var recording: Bool

    public init(playing: Bool, recording: Bool) {
        self.playing = playing
        self.recording = recording
    }

    public var json: JSONValue {
        ["playing": .bool(playing), "recording": .bool(recording)]
    }
}

/// Readback only. Implementations must reject initial LED defaults and state
/// from a stopped or replaced Logic process, including during a wait.
public protocol TransportReadback: AnyObject {
    /// Returns a failure when a trustworthy connection cannot be established.
    func prepareTransportReadback() -> Outcome?
    func transportSnapshot() -> TransportSnapshot?
    /// Waits for the desired state. On timeout, returns the last trustworthy state,
    /// including a mismatch; returns nil when readback is no longer available.
    func waitForTransport(playing: Bool, recording: Bool?, timeout: TimeInterval) -> TransportSnapshot?
}

/// AESendMessage's transport status and Logic's reply error are separate evidence.
public struct AppleEventSendResult: Equatable, Sendable {
    public var sendStatus: Int32
    public var replyError: Int32?
    public var replyReceived: Bool
    public var replyValid: Bool
    public var sent: Bool

    public init(sendStatus: Int32, replyError: Int32?, replyReceived: Bool,
                replyValid: Bool = true, sent: Bool = true) {
        self.sendStatus = sendStatus
        self.replyError = replyError
        self.replyReceived = replyReceived
        self.replyValid = replyValid
        self.sent = sent
    }

    public var succeeded: Bool {
        sent && sendStatus == noErr && replyReceived && replyValid && (replyError == nil || replyError == noErr)
    }
}

public protocol AppleEventTransportSending: AnyObject {
    func send(commandID: Int16, target: LogicAppInfo) -> AppleEventSendResult
}

/// Sends the statically resolved and experimentally verified transport event.
/// This sender never launches Logic, retries, or sends a fallback MCU command.
public final class NativeAppleEventTransportSender: AppleEventTransportSending {
    static let eventClass: AEEventClass = 0x61556556 // aUeV
    static let eventID: AEEventID = 0x53707432 // Spt2
    static let modeKeyword: AEKeyword = 0x73506D6F // sPmo
    static let commandKeyword: AEKeyword = 0x73506B63 // sPkc
    static let sendMode = AESendMode(kAEWaitReply | kAENeverInteract | kAEDontRecord)
    static let timeoutTicks = 5 * 60

    public init() {}

    /// Kept separate from sending so tests can inspect the real descriptor safely.
    static func event(commandID: Int16, targetPID: Int32) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: eventClass, eventID: eventID,
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: targetPID),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(int32: 6), forKeyword: modeKeyword)
        event.setParam(NSAppleEventDescriptor(int32: -Int32(commandID)), forKeyword: commandKeyword)
        return event
    }

    public func send(commandID: Int16, target: LogicAppInfo) -> AppleEventSendResult {
        // Limit the native sender itself to the two commands validated for this profile.
        guard (commandID == 3 || commandID == 5), AppleEventTransportBackend.supports(target) else {
            return AppleEventSendResult(sendStatus: Int32(paramErr), replyError: nil,
                                        replyReceived: false, sent: false)
        }
        let descriptor = Self.event(commandID: commandID, targetPID: target.pid)
        guard let event = descriptor.aeDesc else {
            return AppleEventSendResult(sendStatus: Int32(paramErr), replyError: nil,
                                        replyReceived: false, sent: false)
        }
        var rawReply = AEDesc(descriptorType: typeNull, dataHandle: nil)
        let status = AESendMessage(event, &rawReply, Self.sendMode, Self.timeoutTicks)
        let received = rawReply.descriptorType == typeAppleEvent
        // The descriptor takes ownership of rawReply, including error-path descriptors.
        let reply = NSAppleEventDescriptor(aeDescNoCopy: &rawReply)
        let errorDescriptor = received ? reply.paramDescriptor(forKeyword: keyErrorNumber) : nil
        let decodedError = errorDescriptor?.coerce(toDescriptorType: typeSInt32)?.int32Value
        return AppleEventSendResult(sendStatus: status, replyError: decodedError,
                                    replyReceived: received,
                                    replyValid: errorDescriptor == nil || decodedError != nil)
    }
}

/// AppleEvent writes with independent MCU state verification.
public final class AppleEventTransportBackend: LogicBackend {
    public let kind = BackendKind.appleEvent
    public static let supportedVersion = "12.3.1"
    public static let supportedBuild = "6682"

    public static func supports(_ app: LogicAppInfo) -> Bool {
        app.version == supportedVersion && app.build == supportedBuild
    }

    private let readback: TransportReadback
    private let sender: AppleEventTransportSending
    private let appProvider: () -> LogicAppInfo?
    private let verificationTimeout: TimeInterval

    public init(readback: TransportReadback,
                sender: AppleEventTransportSending = NativeAppleEventTransportSender(),
                appProvider: @escaping () -> LogicAppInfo? = LogicApp.running,
                verificationTimeout: TimeInterval = 2.0) {
        self.readback = readback
        self.sender = sender
        self.appProvider = appProvider
        self.verificationTimeout = verificationTimeout.isFinite ? max(0, verificationTimeout) : 2.0
    }

    public func execute(_ command: LogicCommand) -> Outcome {
        let play: Bool
        switch command {
        case .transportPlay: play = true
        case .transportStop: play = false
        default:
            return .failure("unsupported_backend_command", "appleevent 経路は transport.play と transport.stop で使えます。")
        }
        let requested: JSONValue = play ? ["playing": true] : ["playing": false, "recording": false]
        guard let target = appProvider() else {
            return failure("logic_not_running", "Logic Proを起動してください。", requested: requested)
        }
        guard Self.supports(target) else {
            return failure("unsupported_logic_version",
                           "AppleEventによる再生・停止に対応するのは Logic \(Self.supportedVersion) / build \(Self.supportedBuild) です。",
                           requested: requested, target: target)
        }
        if var unavailable = readback.prepareTransportReadback() {
            unavailable.ok = false
            unavailable.verified = false
            unavailable.requested = requested
            unavailable.result = metadata(target: target)
            return unavailable
        }
        guard let before = readback.transportSnapshot() else {
            return failure("readback_unavailable", "Logicの再生・録音状態を確認できないため、送信していません。",
                           requested: requested, target: target)
        }
        // Connecting readback may take time. Never send to a replacement process.
        guard let currentTarget = appProvider() else {
            return failure("logic_not_running", "送信前にLogic Proが終了しました。",
                           requested: requested, target: target, observed: before)
        }
        guard currentTarget.pid == target.pid else {
            return failure("logic_instance_changed", "状態の確認中にLogic Proが再起動したため、送信していません。",
                           requested: requested, target: currentTarget, observed: before)
        }
        // Avoid a redundant Stop, which can also move Logic's playhead to the start.
        if matches(before, playing: play) {
            return .write(matched: true, requested: requested, observed: before.json,
                          result: metadata(target: currentTarget), message: "既に要求どおりの状態です。送信していません。")
        }
        let commandID: Int16 = play ? 3 : 5
        let sent = sender.send(commandID: commandID, target: currentTarget)
        // A send timeout or error can occur after Logic handled the command.
        // Always observe the bounded final state, without retrying the write.
        let observed = readback.waitForTransport(playing: play, recording: play ? nil : false,
                                                timeout: verificationTimeout)
        let result = metadata(target: currentTarget, commandID: commandID, send: sent)
        if !sent.succeeded {
            let (code, message) = sendFailure(sent)
            return Outcome(ok: false, requested: requested, observed: observed?.json,
                           result: result, error: code, message: message)
        }
        guard let observed else {
            return Outcome(ok: false, requested: requested, result: result,
                           error: "readback_unavailable", message: "AppleEventの応答は成功しましたが、再生・録音状態を確認できませんでした。")
        }
        return .write(matched: matches(observed, playing: play), requested: requested,
                      observed: observed.json, result: result,
                      message: matches(observed, playing: play) ? nil : "AppleEventの応答は成功しましたが、Logicの再生・録音状態が要求と一致しませんでした。")
    }

    private func matches(_ snapshot: TransportSnapshot, playing: Bool) -> Bool {
        snapshot.playing == playing && (playing || !snapshot.recording)
    }

    private func metadata(target: LogicAppInfo? = nil, commandID: Int16? = nil,
                          send: AppleEventSendResult? = nil) -> JSONValue {
        ["sent": .bool(send?.sent ?? false), "event_class": "aUeV", "event_id": "Spt2",
         "command_id": .int(commandID.map(Int.init)), "target_pid": .int(target.map { Int($0.pid) }),
         "logic_version": .string(target?.version), "logic_build": .string(target?.build),
         "appleevent_send_status": .int(send.map { Int($0.sendStatus) }),
         "appleevent_reply_error": .int(send?.replyError.map(Int.init)),
         "appleevent_reply_received": send.map { .bool($0.replyReceived) } ?? .null]
    }

    private func failure(_ code: String, _ message: String, requested: JSONValue,
                         target: LogicAppInfo? = nil, observed: TransportSnapshot? = nil) -> Outcome {
        Outcome(ok: false, requested: requested, observed: observed?.json,
                result: metadata(target: target), error: code, message: message)
    }

    private func sendFailure(_ result: AppleEventSendResult) -> (String, String) {
        let error = result.sendStatus != noErr ? result.sendStatus : result.replyError
        switch error {
        case -1743: return ("appleevent_permission_denied", "macOSのオートメーション権限により、Logic Proへの操作が拒否されました。")
        case -1712: return ("appleevent_timeout", "AppleEventが時間内に応答しませんでした。再実行の前に observed の状態を確認してください。")
        case -1708: return ("appleevent_not_handled", "Logic ProがこのAppleEventを処理しませんでした。")
        case -38: return ("no_project", "AppleEventが操作できる現在のプロジェクトがありません。")
        default:
            if result.sendStatus != noErr {
                return ("appleevent_send_failed", "AppleEventの送信に失敗しました。状態コード: \(result.sendStatus)")
            }
            if !result.replyReceived || !result.replyValid {
                return ("appleevent_invalid_reply", "有効なAppleEvent応答がなく、処理の受付を確認できませんでした。")
            }
            return ("appleevent_reply_failed", "Logic ProからAppleEventエラーが返りました。コード: \(result.replyError.map(String.init) ?? "不明")")
        }
    }
}
