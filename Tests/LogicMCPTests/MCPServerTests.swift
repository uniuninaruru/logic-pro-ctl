import Foundation
import LogicCore
import XCTest
@testable import LogicMCP

final class MCPServerTests: XCTestCase {
    private final class FakeExecutor {
        var calls: [[String]] = []
        var response: JSONValue = ["id": "cli-1", "ok": true, "command": "state", "verified": false,
                                   "observation": ["freshness": "partial"], "execution": ["state": "completed"]]
        var failure: Error?
        func execute(_ argv: [String]) throws -> JSONValue {
            calls.append(argv)
            if let failure { throw failure }
            return response
        }
    }
    private func request(_ method: String, _ params: JSONValue = [:], id: JSONValue = 1) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "method": .string(method), "params": params]
    }
    private func start(_ fake: FakeExecutor) throws -> MCPServer {
        let server = MCPServer(execute: fake.execute)
        let result = server.handle(request("initialize", ["protocolVersion": "2025-11-25", "capabilities": [:],
                                                        "clientInfo": ["name": "tests", "version": "1"]]))
        XCTAssertEqual(result?["result"]?["protocolVersion"], "2025-11-25")
        XCTAssertNil(server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        return server
    }
    private func call(_ server: MCPServer, _ tool: String, _ arguments: JSONValue, id: JSONValue = 2) -> JSONValue? {
        server.handle(request("tools/call", ["name": .string(tool), "arguments": arguments], id: id))
    }
    private func text(_ result: JSONValue?) throws -> JSONValue {
        guard case .array(let content)? = result?["content"], let first = content.first,
              case .string(let value)? = first["text"] else { throw TestError.failed }
        return try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))
    }
    private enum TestError: Error { case failed }

    func testLifecycleNegotiationAndNotificationSafety() throws {
        let fake = FakeExecutor(); let server = MCPServer(execute: fake.execute)
        XCTAssertNotNil(call(server, "logic_transport", ["action": "play"])?["error"])
        XCTAssertEqual(server.handle(request("ping", id: "ping"))?["id"], "ping")
        XCTAssertNil(server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        let initialization = request("initialize", ["protocolVersion": "2024-11-05", "capabilities": [:],
                                                    "clientInfo": ["name": "test", "version": "1"]], id: "init")
        XCTAssertEqual(server.handle(initialization)?["result"]?["protocolVersion"], "2025-11-25")
        XCTAssertNotNil(server.handle(request("tools/list"))?["error"])
        XCTAssertNil(server.handle(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        XCTAssertNil(server.handle(["jsonrpc": "2.0", "method": "tools/call",
                                    "params": ["name": "logic_transport", "arguments": ["action": "play"]]]))
        XCTAssertNotNil(server.handle(initialization)?["error"])
        XCTAssertEqual(fake.calls, [])
    }

    func testDiscoveryIsCompactAndDoesNotExecute() throws {
        let fake = FakeExecutor(); let server = try start(fake)
        guard case .array(let tools)? = server.handle(request("tools/list"))?["result"]?["tools"] else {
            return XCTFail("Expected tools")
        }
        XCTAssertEqual(tools.compactMap { $0["name"] }, ["logic_read", "logic_transport", "logic_track", "logic_mixer"])
        for tool in tools { XCTAssertEqual(tool["inputSchema"]?["additionalProperties"], false) }
        XCTAssertEqual(tools[0]["annotations"]?["readOnlyHint"], true)
        XCTAssertEqual(tools[1]["annotations"]?["destructiveHint"], true)
        XCTAssertEqual(tools[1]["annotations"]?["idempotentHint"], false)
        XCTAssertEqual(tools[3]["inputSchema"]?["properties"]?["deadline_ms"]?["maximum"], 30_000)
        guard case .array(let resources)? = server.handle(request("resources/list"))?["result"]?["resources"] else {
            return XCTFail("Expected resources")
        }
        XCTAssertEqual(resources.compactMap { $0["uri"] }, ["logicctl://status", "logicctl://state", "logicctl://tracks"])
        XCTAssertNotNil(server.handle(request("resources/templates/list"))?["result"])
        XCTAssertEqual(fake.calls, [])
    }

    func testToolArgvGuardsAndFullResponsePreservation() throws {
        let fake = FakeExecutor(); let server = try start(fake)
        fake.response = ["id": "cli-write", "ok": false, "command": "track.volume", "verified": false,
                         "error": "verification_failed", "backend": "mcu", "readback_backend": "mcu",
                         "requested": ["db": -6], "observed": ["db": -3],
                         "observation": ["session": ["handshake_generation": 7]],
                         "execution": ["state": "unknown", "replayed": false]]
        let reply = call(server, "logic_mixer", ["action": "volume", "track": 3, "db": -6,
                                                "tolerance": 0.2, "expect_name": "Studio Grand", "expect_session": 7,
                                                "deadline_ms": 2500, "idempotency_key": "mix-1"], id: "write")
        XCTAssertEqual(fake.calls, [["track", "volume", "3", "-6.0", "--tolerance", "0.2", "--expect-session", "7",
                                    "--expect-name", "Studio Grand", "--deadline-ms", "2500", "--idempotency-key", "mix-1"]])
        XCTAssertEqual(reply?["id"], "write")
        XCTAssertEqual(reply?["result"]?["structuredContent"], fake.response)
        XCTAssertEqual(reply?["result"]?["isError"], true)
        XCTAssertEqual(try text(reply?["result"]), fake.response)
    }

    func testAllToolRoutesAndUnverifiedSuccess() throws {
        let fake = FakeExecutor(); let server = try start(fake)
        let cases: [(String, JSONValue, [String])] = [
            ("logic_read", ["action": "status"], ["status"]),
            ("logic_read", ["action": "state"], ["state"]),
            ("logic_read", ["action": "list"], ["track", "list"]),
            ("logic_read", ["action": "get", "track": 2, "expect_name": "Bass"], ["track", "get", "2", "--expect-name", "Bass"]),
            ("logic_transport", ["action": "play", "backend": "appleevent"], ["transport", "play", "--backend", "appleevent"]),
            ("logic_transport", ["action": "stop", "backend": "mcu"], ["transport", "stop", "--backend", "mcu"]),
            ("logic_transport", ["action": "cycle", "state": false], ["transport", "cycle", "off"]),
            ("logic_transport", ["action": "click", "state": true], ["transport", "click", "on"]),
            ("logic_track", ["action": "select", "track": 2], ["track", "select", "2"]),
            ("logic_track", ["action": "mute", "track": 2, "state": false], ["track", "mute", "2", "off"]),
            ("logic_track", ["action": "solo", "track": 2, "state": true], ["track", "solo", "2", "on"]),
            ("logic_track", ["action": "arm", "track": 2, "state": true], ["track", "arm", "2", "on"]),
            ("logic_mixer", ["action": "volume", "track": 2, "db": "-inf"], ["track", "volume", "2", "-inf"]),
            ("logic_mixer", ["action": "pan", "track": 2, "value": -0.25], ["track", "pan", "2", "-0.25"]),
        ]
        for (tool, arguments, argv) in cases {
            let reply = call(server, tool, arguments)
            XCTAssertEqual(reply?["result"]?["isError"], false)
            XCTAssertEqual(reply?["result"]?["structuredContent"]?["verified"], false)
            XCTAssertEqual(fake.calls.last, argv)
        }
        XCTAssertEqual(fake.calls.count, cases.count)
    }

    func testInvalidToolArgumentsNeverExecute() throws {
        let fake = FakeExecutor(); let server = try start(fake)
        let invalid: [(String, JSONValue)] = [
            ("logic_read", ["action": "status", "track": 1]),
            ("logic_read", ["action": "status", "expect_name": "x"]),
            ("logic_read", ["action": "list", "idempotency_key": "x"]),
            ("logic_read", ["action": "get", "track": 1.5]),
            ("logic_track", ["action": "select", "track": 0]),
            ("logic_track", ["action": "select", "track": true]),
            ("logic_track", ["action": "select", "track": 1, "state": false]),
            ("logic_track", ["action": "mute", "track": 1, "state": "on"]),
            ("logic_track", ["action": "arm", "track": 1]),
            ("logic_track", ["action": "select", "track": 1, "expect_name": "  "]),
            ("logic_transport", ["action": "play", "state": true]),
            ("logic_transport", ["action": "record"]),
            ("logic_transport", ["action": "cycle", "state": true, "backend": "appleevent"]),
            ("logic_transport", ["action": "play", "backend": "native-ipc"]),
            ("logic_transport", ["action": "play", "expect_session": 0]),
            ("logic_transport", ["action": "play", "deadline_ms": 30_001]),
            ("logic_transport", ["action": "play", "deadline_ms": 1.5]),
            ("logic_transport", ["action": "play", "idempotency_key": "has spaces"]),
            ("logic_mixer", ["action": "volume", "track": 1, "db": 7]),
            ("logic_mixer", ["action": "volume", "track": 1, "db": "-oo"]),
            ("logic_mixer", ["action": "volume", "track": 1, "db": 0, "tolerance": -1]),
            ("logic_mixer", ["action": "pan", "track": 1, "value": 2]),
            ("logic_mixer", ["action": "pan", "track": 1, "value": 0, "db": 0]),
            ("logic_mixer", ["action": "pan", "track": 1, "value": 0, "tolerance": 0.1]),
            ("logic_mixer", ["action": "pan", "track": 1, "value": .number(.nan)]),
            ("logic_mixer", ["action": "volume", "track": 1, "db": .number(.infinity)]),
            ("logic_read", ["action": "state", "other": false]),
        ]
        for (tool, arguments) in invalid {
            XCTAssertEqual(call(server, tool, arguments)?["result"]?["isError"], true, "\(tool): \(arguments)")
        }
        XCTAssertEqual(fake.calls, [])
    }

    func testResourcesPreserveResponseAndSurfaceFailures() throws {
        let fake = FakeExecutor(); let server = try start(fake)
        for (uri, argv) in [("logicctl://status", ["status"]), ("logicctl://state", ["state"]),
                            ("logicctl://tracks", ["track", "list"]), ("logicctl://tracks/3", ["track", "get", "3"])] {
            let reply = server.handle(request("resources/read", ["uri": .string(uri)]))
            XCTAssertEqual(fake.calls.last, argv)
            guard case .array(let contents)? = reply?["result"]?["contents"], case .string(let raw)? = contents.first?["text"] else {
                return XCTFail("Expected resource contents")
            }
            XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)), fake.response)
        }
        fake.response = ["ok": false, "verified": false, "error": "session_changed", "observation": ["partial": true]]
        let failure = server.handle(request("resources/read", ["uri": "logicctl://state"]))
        XCTAssertEqual(failure?["error"]?["data"], fake.response)
        XCTAssertNil(failure?["result"])
        let count = fake.calls.count
        for uri in ["logicctl://tracks/0", "logicctl://tracks/1.5", "logicctl://tracks/01", "logicctl://tracks/3?x=1", "logicctl://debug"] {
            XCTAssertEqual(server.handle(request("resources/read", ["uri": .string(uri)]))?["error"]?["code"], -32002)
        }
        XCTAssertEqual(fake.calls.count, count)
    }

    func testProtocolErrorsAndExecutorFailures() throws {
        let fake = FakeExecutor(); let server = try start(fake)
        XCTAssertEqual(server.handle(.array([]))?["error"]?["code"], -32600)
        for id in [JSONValue.null, .bool(true), .number(1.5), .number(.infinity)] {
            XCTAssertEqual(server.handle(request("tools/list", id: id))?["error"]?["code"], -32600)
        }
        XCTAssertEqual(server.handle(request("unknown"))?["error"]?["code"], -32601)
        XCTAssertEqual(call(server, "debug", [:])?["error"]?["code"], -32602)
        XCTAssertEqual(server.handle(request("tools/call", ["name": "logic_read", "arguments": []]))?["error"]?["code"], -32602)
        XCTAssertEqual(server.handle(request("tools/list", ["cursor": "unknown"]))?["error"]?["code"], -32602)
        XCTAssertEqual(fake.calls.count, 0)
        fake.failure = TestError.failed
        XCTAssertEqual(call(server, "logic_read", ["action": "state"])?["result"]?["isError"], true)
        XCTAssertNotNil(server.handle(request("resources/read", ["uri": "logicctl://status"]))?["error"])
        fake.failure = nil; fake.response = ["verified": true]
        XCTAssertEqual(call(server, "logic_read", ["action": "state"])?["error"]?["code"], -32603)
        XCTAssertEqual(fake.calls.count, 3)
    }

    func testLineFramingParseErrorAndNotification() throws {
        let fake = FakeExecutor(); let server = try start(fake)
        let error = try XCTUnwrap(server.handleLine("{"))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data(error.utf8))["error"]?["code"], -32700)
        XCTAssertNil(server.handleLine("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/cancelled\"}"))
        let line = try XCTUnwrap(server.handleLine("{\"jsonrpc\":\"2.0\",\"id\":\"x\",\"method\":\"ping\"}"))
        XCTAssertFalse(line.contains("\n"))
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))["id"], "x")
        XCTAssertEqual(fake.calls, [])
    }
}
