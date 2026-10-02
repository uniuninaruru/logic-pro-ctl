import Foundation

/// A parsed, validated command. Tracks are 1-based as shown in Logic.
public enum LogicCommand: Equatable {
    case status
    case state
    case transportPlay
    case transportStop
    case trackList
    case trackGet(track: Int)
    case trackSelect(track: Int)
    case trackMute(track: Int, on: Bool)
    case trackSolo(track: Int, on: Bool)
    /// `db` may be -infinity. `tolerance` is the accepted |observed - requested| in dB.
    case trackVolume(track: Int, db: Double, tolerance: Double)
    /// `pan` is normalized: -1 (left) … 0 … +1 (right).
    case trackPan(track: Int, pan: Double)
    case daemonStop
    /// Research aid: send raw MCU messages, return the surface state afterwards.
    case debugMCU(messages: [[UInt8]])

    /// Commands that change Logic. Only these are journaled and accept an idempotency key.
    public var isWrite: Bool {
        switch self {
        case .transportPlay, .transportStop, .trackSelect, .trackMute, .trackSolo, .trackVolume, .trackPan, .debugMCU:
            return true
        case .status, .state, .trackList, .trackGet, .daemonStop:
            return false
        }
    }

    /// `isWrite` by wire name, for code that has a Request but no validated command yet.
    /// A test keeps this in step with `isWrite`.
    public static func isWrite(named name: String) -> Bool {
        !Self.readOnlyNames.contains(name)
    }

    static let readOnlyNames: Set<String> = ["status", "state", "track.list", "track.get", "daemon.stop"]

    /// The wire name used in `Request.command`.
    public var name: String {
        switch self {
        case .status: return "status"
        case .state: return "state"
        case .transportPlay: return "transport.play"
        case .transportStop: return "transport.stop"
        case .trackList: return "track.list"
        case .trackGet: return "track.get"
        case .trackSelect: return "track.select"
        case .trackMute: return "track.mute"
        case .trackSolo: return "track.solo"
        case .trackVolume: return "track.volume"
        case .trackPan: return "track.pan"
        case .daemonStop: return "daemon.stop"
        case .debugMCU: return "debug.mcu"
        }
    }
}

public struct CommandError: Error, Equatable {
    public var code: String
    public var message: String
    public init(_ code: String, _ message: String) {
        self.code = code
        self.message = message
    }
}

extension LogicCommand {
    /// Validates a wire request. Throws `CommandError("invalid_argument" | "unknown_command", …)`.
    public init(request: Request) throws {
        let a = request.args
        func track() throws -> Int {
            guard let s = a["track"], let n = Int(s), n >= 1 else {
                throw CommandError("invalid_argument", "トラック番号は1以上の整数です。指定値: \(a["track"] ?? "未指定")")
            }
            return n
        }
        func onOff() throws -> Bool {
            switch a["state"]?.lowercased() {
            case "on", "true", "1": return true
            case "off", "false", "0": return false
            default: throw CommandError("invalid_argument", "状態は on または off で指定してください。指定値: \(a["state"] ?? "未指定")")
            }
        }
        switch request.command {
        case "status": self = .status
        case "state": self = .state
        case "transport.play": self = .transportPlay
        case "transport.stop": self = .transportStop
        case "track.list": self = .trackList
        case "track.get": self = .trackGet(track: try track())
        case "track.select": self = .trackSelect(track: try track())
        case "track.mute": self = .trackMute(track: try track(), on: try onOff())
        case "track.solo": self = .trackSolo(track: try track(), on: try onOff())
        case "track.volume":
            guard let s = a["db"], let db = parseDB(s) else {
                throw CommandError("invalid_argument", "音量は数値または -inf で指定してください。指定値: \(a["db"] ?? "未指定")")
            }
            guard db <= 6.0 else { throw CommandError("invalid_argument", "音量は6.0 dB以下で指定してください（Logicのフェーダーの上限）") }
            let tol = a["tolerance"].flatMap(Double.init) ?? 0.1
            guard tol >= 0 else { throw CommandError("invalid_argument", "許容差は0以上で指定してください") }
            self = .trackVolume(track: try track(), db: db, tolerance: tol)
        case "track.pan":
            guard let s = a["value"], let v = Double(s), (-1.0...1.0).contains(v) else {
                throw CommandError("invalid_argument", "パンは -1〜1 の数値で指定してください。指定値: \(a["value"] ?? "未指定")")
            }
            self = .trackPan(track: try track(), pan: v)
        case "daemon.stop": self = .daemonStop
        case "debug.mcu":
            // "90 2E 7F; 90 2E 00" — messages separated by ';'
            let messages = (a["messages"] ?? "").split(separator: ";").map {
                $0.split(separator: " ").compactMap { UInt8($0, radix: 16) }
            }.filter { !$0.isEmpty }
            guard !messages.isEmpty else { throw CommandError("invalid_argument", "メッセージは16進数のバイト列です。複数の列は ; で区切ってください") }
            self = .debugMCU(messages: messages)
        default: throw CommandError("unknown_command", "不明なコマンドです: \(request.command)")
        }
    }
}

/// "-6", "-6.0", "+3", "-inf", "-oo" → dB value.
public func parseDB(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespaces).lowercased()
    if ["-inf", "-infinity", "-oo"].contains(t) { return -.infinity }
    guard let d = Double(t), d.isFinite else { return nil }
    return d
}
