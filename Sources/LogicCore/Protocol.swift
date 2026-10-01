import Foundation

/// Default Unix domain socket path shared by logicctl and logicd.
public let defaultSocketPath = NSString(string: "~/Library/Application Support/logicctl/logicd.sock")
    .expandingTildeInPath

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

/// Response returned by logicd. `verified` is true only when the
/// backend read the state back after writing it (verify-after-write).
public struct Response: Codable, Equatable {
    public var id: String
    public var ok: Bool
    public var backend: String?
    public var verified: Bool
    public var result: [String: String]?
    public var error: String?

    public init(id: String, ok: Bool, backend: String? = nil, verified: Bool = false,
                result: [String: String]? = nil, error: String? = nil) {
        self.id = id
        self.ok = ok
        self.backend = backend
        self.verified = verified
        self.result = result
        self.error = error
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
