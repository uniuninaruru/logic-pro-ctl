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
                throw CommandError("invalid_argument", "track must be an integer >= 1, got \(a["track"] ?? "nothing")")
            }
            return n
        }
        func onOff() throws -> Bool {
            switch a["state"]?.lowercased() {
            case "on", "true", "1": return true
            case "off", "false", "0": return false
            default: throw CommandError("invalid_argument", "state must be on or off, got \(a["state"] ?? "nothing")")
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
                throw CommandError("invalid_argument", "db must be a number or -inf, got \(a["db"] ?? "nothing")")
            }
            guard db <= 6.0 else { throw CommandError("invalid_argument", "db must be <= 6.0 (Logic's fader maximum)") }
            let tol = a["tolerance"].flatMap(Double.init) ?? 0.1
            guard tol >= 0 else { throw CommandError("invalid_argument", "tolerance must be >= 0") }
            self = .trackVolume(track: try track(), db: db, tolerance: tol)
        case "track.pan":
            guard let s = a["value"], let v = Double(s), (-1.0...1.0).contains(v) else {
                throw CommandError("invalid_argument", "pan must be a number in -1…1, got \(a["value"] ?? "nothing")")
            }
            self = .trackPan(track: try track(), pan: v)
        case "daemon.stop": self = .daemonStop
        default: throw CommandError("unknown_command", "unknown command \(request.command)")
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
