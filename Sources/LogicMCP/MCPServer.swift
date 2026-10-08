import Foundation
import LogicCore

/// A synchronous, newline-JSON MCP session. The stdio owner calls this serially.
/// Execution is injected; discovery and validation never contact Logic.
public final class MCPServer {
    public static let protocolVersion = "2025-11-25"
    private let execute: ([String]) throws -> JSONValue
    private var initializeReplied = false
    private var initialized = false
    private static let safeInteger = 9_007_199_254_740_991.0

    public init(execute: @escaping ([String]) throws -> JSONValue) {
        self.execute = execute
    }

    public func handleLine(_ line: String) -> String? {
        let reply: JSONValue?
        do {
            reply = handle(try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)))
        } catch {
            reply = Self.failure(id: .null, code: -32700, message: "Parse error")
        }
        guard let reply else { return nil }
        // All replies are JSON values. An invalid executor result cannot leak non-JSON numbers.
        return (try? Self.json(reply)) ?? (try? Self.json(Self.failure(
            id: reply["id"] ?? .null, code: -32603, message: "Response could not be encoded")))
    }

    public func handle(_ message: JSONValue) -> JSONValue? {
        guard case .object(let envelope) = message,
              envelope["jsonrpc"] == .string("2.0"),
              case .string(let method)? = envelope["method"], !method.isEmpty else {
            return Self.failure(id: Self.validID(message["id"]) ?? .null,
                                code: -32600, message: "Invalid request")
        }
        // A notification never invokes the executor, even if it names a write tool.
        guard let rawID = envelope["id"] else {
            if method == "notifications/initialized", initializeReplied,
               (try? Self.params(envelope["params"], allowed: [])) != nil {
                initialized = true
            }
            return nil
        }
        guard let id = Self.validID(rawID) else {
            return Self.failure(id: .null, code: -32600, message: "ID must be a string or a safe integer")
        }
        do {
            if method == "ping" {
                _ = try Self.params(envelope["params"], allowed: [])
                return Self.success(id: id, result: [:])
            }
            if method == "initialize" {
                guard !initializeReplied else {
                    return Self.failure(id: id, code: -32600, message: "Session already initialized")
                }
                let params = try Self.params(envelope["params"], allowed: ["protocolVersion", "capabilities", "clientInfo"])
                _ = try Self.string(params, "protocolVersion")
                guard case .object? = params["capabilities"], case .object(let client)? = params["clientInfo"] else {
                    throw InvalidParams("initialize requires capabilities and clientInfo objects")
                }
                _ = try Self.string(client, "name")
                _ = try Self.string(client, "version")
                initializeReplied = true
                return Self.success(id: id, result: [
                    "protocolVersion": .string(Self.protocolVersion),
                    "capabilities": ["tools": ["listChanged": false],
                                     "resources": ["subscribe": false, "listChanged": false]],
                    "serverInfo": ["name": "logicctl", "version": "0.1.0"],
                ])
            }
            guard initialized else {
                return Self.failure(id: id, code: -32000, message: "Initialize and send notifications/initialized first")
            }
            switch method {
            case "tools/list":
                _ = try Self.params(envelope["params"], allowed: [])
                return Self.success(id: id, result: ["tools": .array(Self.tools)])
            case "tools/call":
                let params = try Self.params(envelope["params"], allowed: ["name", "arguments"])
                let name = try Self.string(params, "name")
                guard Self.toolNames.contains(name) else { throw InvalidParams("Unknown tool: \(name)") }
                let arguments: [String: JSONValue]
                if let supplied = params["arguments"] {
                    guard case .object(let object) = supplied else { throw InvalidParams("arguments must be an object") }
                    arguments = object
                } else { arguments = [:] }
                let argv: [String]
                do {
                    argv = try Self.argv(tool: name, arguments: arguments)
                } catch {
                    return Self.success(id: id, result: Self.toolError(Self.errorMessage(error)))
                }
                do {
                    let response = try execute(argv)
                    guard case .object = response, case .bool(let ok)? = response["ok"] else {
                        return Self.failure(id: id, code: -32603, message: "Executor did not return a CLI response object with ok")
                    }
                    return Self.success(id: id, result: [
                        "content": [["type": "text", "text": .string(try Self.json(response))]],
                        "structuredContent": response, "isError": .bool(!ok),
                    ])
                } catch {
                    return Self.success(id: id, result: Self.toolError(Self.errorMessage(error)))
                }
            case "resources/list":
                _ = try Self.params(envelope["params"], allowed: [])
                return Self.success(id: id, result: ["resources": .array(Self.resources)])
            case "resources/templates/list":
                _ = try Self.params(envelope["params"], allowed: [])
                return Self.success(id: id, result: ["resourceTemplates": [[
                    "uriTemplate": "logicctl://tracks/{track}", "name": "track",
                    "description": "Read one current 1-based mixer strip; preserves observation metadata.",
                    "mimeType": "application/json",
                ]]])
            case "resources/read":
                let params = try Self.params(envelope["params"], allowed: ["uri"])
                let uri = try Self.string(params, "uri")
                guard let argv = Self.resourceArgv(uri) else {
                    return Self.failure(id: id, code: -32002, message: "Resource not found: \(uri)")
                }
                do {
                    let response = try execute(argv)
                    guard case .object = response, case .bool(let ok)? = response["ok"] else {
                        return Self.failure(id: id, code: -32603, message: "Executor did not return a CLI response object with ok")
                    }
                    guard ok else {
                        return Self.failure(id: id, code: -32001, message: "Logic resource read failed", data: response)
                    }
                    return Self.success(id: id, result: ["contents": [[
                        "uri": .string(uri), "mimeType": "application/json", "text": .string(try Self.json(response)),
                    ]]])
                } catch {
                    return Self.failure(id: id, code: -32001, message: Self.errorMessage(error))
                }
            default:
                return Self.failure(id: id, code: -32601, message: "Method not found: \(method)")
            }
        } catch {
            return Self.failure(id: id, code: -32602, message: Self.errorMessage(error))
        }
    }

    private struct InvalidParams: Error { let message: String; init(_ message: String) { self.message = message } }
    private static func errorMessage(_ error: Error) -> String {
        if let error = error as? InvalidParams { return error.message }
        if let error = error as? CommandError { return error.message }
        return String(describing: error)
    }
    private static func validID(_ value: JSONValue?) -> JSONValue? {
        switch value {
        case .string?: return value
        case .number(let n)? where n.isFinite && n.rounded(.towardZero) == n && abs(n) <= safeInteger: return value
        default: return nil
        }
    }
    private static func success(id: JSONValue, result: JSONValue) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }
    private static func failure(id: JSONValue, code: Int, message: String, data: JSONValue? = nil) -> JSONValue {
        var error: [String: JSONValue] = ["code": .number(Double(code)), "message": .string(message)]
        if let data { error["data"] = data }
        return ["jsonrpc": "2.0", "id": id, "error": .object(error)]
    }
    private static func toolError(_ message: String) -> JSONValue {
        ["content": [["type": "text", "text": .string(message)]], "isError": true]
    }
    private static func json(_ value: JSONValue) throws -> String {
        String(decoding: try JSONEncoder.logicctl.encode(value), as: UTF8.self)
    }
    private static func params(_ value: JSONValue?, allowed: Set<String>) throws -> [String: JSONValue] {
        guard let value else { return [:] }
        guard case .object(let object) = value else { throw InvalidParams("params must be an object") }
        if let metadata = object["_meta"] {
            guard case .object = metadata else { throw InvalidParams("_meta must be an object") }
        }
        try keys(object, allowed: allowed.union(["_meta"]))
        return object
    }
    private static func keys(_ object: [String: JSONValue], allowed: Set<String>) throws {
        if let key = Set(object.keys).subtracting(allowed).sorted().first { throw InvalidParams("Unexpected argument: \(key)") }
    }
    private static func string(_ object: [String: JSONValue], _ key: String) throws -> String {
        guard case .string(let string)? = object[key], !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InvalidParams("\(key) must be a nonempty string")
        }
        return string
    }
    private static func integer(_ object: [String: JSONValue], _ key: String, maximum: Double = safeInteger) throws -> Int {
        guard case .number(let number)? = object[key], number.isFinite, number >= 1, number <= maximum,
              let integer = Int(exactly: number) else { throw InvalidParams("\(key) must be a positive integer at most \(maximum)") }
        return integer
    }
    private static func number(_ object: [String: JSONValue], _ key: String) throws -> Double {
        guard case .number(let number)? = object[key], number.isFinite else { throw InvalidParams("\(key) must be a finite number") }
        return number
    }
    private static func state(_ object: [String: JSONValue]) throws -> String {
        guard case .bool(let state)? = object["state"] else { throw InvalidParams("state must be a boolean") }
        return state ? "on" : "off"
    }

    private static let toolNames: Set<String> = ["logic_read", "logic_transport", "logic_track", "logic_mixer"]
    private static func argv(tool: String, arguments a: [String: JSONValue]) throws -> [String] {
        let action = try string(a, "action")
        var allowed: Set<String> = ["action", "expect_session", "deadline_ms"]
        var words: [String]
        switch (tool, action) {
        case ("logic_read", "status"), ("logic_read", "state"):
            words = [action]
        case ("logic_read", "list"):
            words = ["track", "list"]
        case ("logic_read", "get"):
            allowed.formUnion(["track", "expect_name"])
            words = ["track", "get", String(try integer(a, "track"))]
        case ("logic_transport", "play"), ("logic_transport", "stop"):
            allowed.formUnion(["backend", "idempotency_key"])
            words = ["transport", action]
        case ("logic_transport", "cycle"), ("logic_transport", "click"):
            allowed.formUnion(["state", "backend", "idempotency_key"])
            words = ["transport", action, try state(a)]
        case ("logic_track", "select"):
            allowed.formUnion(["track", "expect_name", "idempotency_key"])
            words = ["track", action, String(try integer(a, "track"))]
        case ("logic_track", "mute"), ("logic_track", "solo"), ("logic_track", "arm"):
            allowed.formUnion(["track", "state", "expect_name", "idempotency_key"])
            words = ["track", action, String(try integer(a, "track")), try state(a)]
        case ("logic_mixer", "volume"):
            allowed.formUnion(["track", "db", "tolerance", "expect_name", "idempotency_key"])
            let db: String
            if a["db"] == .string("-inf") { db = "-inf" } else { db = String(try number(a, "db")) }
            words = ["track", "volume", String(try integer(a, "track")), db]
            if a["tolerance"] != nil { words += ["--tolerance", String(try number(a, "tolerance"))] }
        case ("logic_mixer", "pan"):
            allowed.formUnion(["track", "value", "expect_name", "idempotency_key"])
            words = ["track", "pan", String(try integer(a, "track")), String(try number(a, "value"))]
        default: throw InvalidParams("Unsupported action \(action) for \(tool)")
        }
        try keys(a, allowed: allowed)
        if a["backend"] != nil { words += ["--backend", try string(a, "backend")] }
        if a["expect_session"] != nil { words += ["--expect-session", String(try integer(a, "expect_session"))] }
        if a["expect_name"] != nil { words += ["--expect-name", try string(a, "expect_name")] }
        if a["deadline_ms"] != nil { words += ["--deadline-ms", String(try integer(a, "deadline_ms", maximum: 30_000))] }
        if a["idempotency_key"] != nil { words += ["--idempotency-key", try string(a, "idempotency_key")] }
        _ = try LogicCommand(request: CLIParser.parse(words))
        return words
    }

    private static func resourceArgv(_ uri: String) -> [String]? {
        switch uri {
        case "logicctl://status": return ["status"]
        case "logicctl://state": return ["state"]
        case "logicctl://tracks": return ["track", "list"]
        default:
            let prefix = "logicctl://tracks/"
            guard uri.hasPrefix(prefix) else { return nil }
            let suffix = String(uri.dropFirst(prefix.count))
            guard !suffix.isEmpty, suffix.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let track = Int(suffix), track > 0, suffix == String(track), Double(track) <= safeInteger else { return nil }
            return ["track", "get", suffix]
        }
    }

    private static let resources: [JSONValue] = [
        ["uri": "logicctl://status", "name": "status", "mimeType": "application/json"],
        ["uri": "logicctl://state", "name": "state", "mimeType": "application/json"],
        ["uri": "logicctl://tracks", "name": "tracks", "mimeType": "application/json"],
    ]
    private static func enumeration(_ values: [String]) -> JSONValue {
        ["type": "string", "enum": .array(values.map(JSONValue.string))]
    }
    private static func branch(_ actions: [String], required: [String] = [], forbidden: [String] = [],
                               properties: [String: JSONValue] = [:]) -> JSONValue {
        var properties = properties; properties["action"] = enumeration(actions)
        var result: [String: JSONValue] = ["properties": .object(properties)]
        if !required.isEmpty { result["required"] = .array(required.map(JSONValue.string)) }
        if !forbidden.isEmpty { result["not"] = ["anyOf": .array(forbidden.map { ["required": [.string($0)]] })] }
        return .object(result)
    }
    private static func tool(_ name: String, _ description: String, properties: [String: JSONValue],
                             required: [String] = ["action"], branches: [JSONValue], write: Bool) -> JSONValue {
        var properties = properties
        properties["expect_session"] = ["type": "integer", "minimum": 1, "maximum": .number(safeInteger)]
        properties["deadline_ms"] = ["type": "integer", "minimum": 1, "maximum": 30_000]
        if write { properties["idempotency_key"] = ["type": "string", "pattern": "^[A-Za-z0-9._:-]{1,128}$"] }
        return ["name": .string(name), "description": .string(description),
                "inputSchema": ["type": "object", "additionalProperties": false, "properties": .object(properties),
                                "required": .array(required.map(JSONValue.string)), "oneOf": .array(branches)],
                "annotations": ["readOnlyHint": .bool(!write), "destructiveHint": .bool(write),
                                "idempotentHint": false, "openWorldHint": false]]
    }
    private static let tools: [JSONValue] = {
        let track: JSONValue = ["type": "integer", "minimum": 1, "maximum": .number(safeInteger)]
        let name: JSONValue = ["type": "string", "minLength": 1, "description": "Exact name from track readback."]
        return [
            tool("logic_read", "Read CLI status, state, track list or one mixer strip; preserves observation metadata.",
                 properties: ["action": enumeration(["status", "state", "list", "get"]), "track": track, "expect_name": name],
                 branches: [branch(["status", "state", "list"], forbidden: ["track", "expect_name"]), branch(["get"], required: ["track"])], write: false),
            tool("logic_transport", "Set play/stop, cycle or click. Backend/readback limits and verified=false are preserved.",
                 properties: ["action": enumeration(["play", "stop", "cycle", "click"]), "state": ["type": "boolean"],
                              "backend": enumeration(["mcu", "appleevent"])],
                 branches: [branch(["play", "stop"], forbidden: ["state"]),
                            branch(["cycle", "click"], required: ["state"], properties: ["backend": enumeration(["mcu"])])], write: true),
            tool("logic_track", "Select or set mute, solo or record-arm on a current 1-based mixer strip, with CLI write guards.",
                 properties: ["action": enumeration(["select", "mute", "solo", "arm"]), "track": track,
                              "state": ["type": "boolean"], "expect_name": name], required: ["action", "track"],
                 branches: [branch(["select"], forbidden: ["state"]), branch(["mute", "solo", "arm"], required: ["state"])], write: true),
            tool("logic_mixer", "Set strip volume in dB or normalized pan; tolerance applies to volume only. Full CLI readback is returned.",
                 properties: ["action": enumeration(["volume", "pan"]), "track": track, "expect_name": name,
                              "db": ["oneOf": [["type": "number", "maximum": 6], ["const": "-inf"]]],
                              "value": ["type": "number", "minimum": -1, "maximum": 1],
                              "tolerance": ["type": "number", "minimum": 0]], required: ["action", "track"],
                 branches: [branch(["volume"], required: ["db"], forbidden: ["value"]),
                            branch(["pan"], required: ["value"], forbidden: ["db", "tolerance"])], write: true),
        ]
    }()
}
