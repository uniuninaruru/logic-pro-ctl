import Foundation

/// Default Unix domain socket path shared by logicctl and logicd.
/// Overridden by the LOGICCTL_SOCKET environment variable.
public var defaultSocketPath: String {
    if let path = ProcessInfo.processInfo.environment["LOGICCTL_SOCKET"], !path.isEmpty { return path }
    return NSString(string: "~/Library/Application Support/logicctl/logicd.sock").expandingTildeInPath
}

/// Request sent from logicctl to logicd (one JSON object per line).
public struct Request: Codable, Equatable {
    public var id: String
    public var command: String
    public var args: [String: String]

    public init(id: String = UUID().uuidString, command: String, args: [String: String] = [:]) {
        self.id = id
        self.command = command
        self.args = args
    }
}

/// Response returned by logicd (one JSON object per line).
///
/// `verified` is true only when the backend read the state back after
/// writing it and the readback matched `requested`. A write whose readback
/// does not match returns `ok: false, error: "verification_failed"`.
public struct Response: Codable, Equatable {
    public var id: String
    public var ok: Bool
    public var command: String
    public var backend: String?
    public var verified: Bool
    public var requested: JSONValue?
    public var observed: JSONValue?
    public var result: JSONValue?
    public var error: String?
    public var message: String?

    public init(id: String, ok: Bool, command: String, backend: String? = nil, verified: Bool = false,
                requested: JSONValue? = nil, observed: JSONValue? = nil, result: JSONValue? = nil,
                error: String? = nil, message: String? = nil) {
        self.id = id
        self.ok = ok
        self.command = command
        self.backend = backend
        self.verified = verified
        self.requested = requested
        self.observed = observed
        self.result = result
        self.error = error
        self.message = message
    }
}

/// Control paths, in the order logicd prefers them.
public enum BackendKind: String, Codable, CaseIterable {
    case nativeIPC = "native-ipc"
    case logicRemote = "logic-remote"
    case mcu = "mcu"
    case scripter = "scripter"
    case accessibility = "accessibility"
    case cgEvent = "cgevent"
}

public extension JSONEncoder {
    /// Encoder used for everything written to stdout or the socket.
    static var logicctl: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
