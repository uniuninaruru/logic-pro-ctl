import Darwin
import Foundation
import LogicCore
import XCTest
@testable import LogicMCP

final class CLIExecutorTests: XCTestCase {
    private func response(command: String = "status", ok: Bool = true, verified: Bool = false,
                          extra: String = "") -> String {
        "{\"id\":\"fake-cli\",\"command\":\"\(command)\",\"ok\":\(ok),\"verified\":\(verified)\(extra)}"
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func emit(_ json: String, exitCode: Int = 0) -> String {
        "printf '%s\\n' \(shellQuote(json))\nexit \(exitCode)"
    }

    private func withCLI(_ script: String, _ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("logicmcp executor \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let executable = folder.appendingPathComponent("fake logicctl")
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try body(executable)
    }

    private func assertUnknown(_ value: JSONValue, error: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value["ok"], false, file: file, line: line)
        XCTAssertEqual(value["verified"], false, file: file, line: line)
        XCTAssertEqual(value["error"], .string(error), file: file, line: line)
        XCTAssertEqual(value["execution"]?["state"], "unknown", file: file, line: line)
        XCTAssertEqual(value["execution"]?["retried"], false, file: file, line: line)
    }

    func testPreservesUnverifiedSuccessAndUnknownFields() throws {
        let json = response(extra: ",\"observation\":{\"complete\":false},\"future_field\":{\"x\":7}")
        let expected = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        try withCLI(emit(json)) { executable in
            XCTAssertEqual(try CLIExecutor(executableURL: executable).execute(["status"]), expected)
        }
    }

    func testPreservesRealCLIErrorWithNonzeroExitAndExecutionMetadata() throws {
        let json = response(command: "track.pan", ok: false,
                            extra: ",\"error\":\"target_mismatch\",\"observed\":{\"name\":\"Other\"},\"execution\":{\"state\":\"rejected\"}")
        let expected = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        try withCLI(emit(json, exitCode: 1)) { executable in
            XCTAssertEqual(try CLIExecutor(executableURL: executable).execute(["track", "pan", "1", "0"]), expected)
        }
    }

    func testArgumentsArePassedLiterallyWithoutShellEvaluation() throws {
        let name = "A;$(printf unexpected) with spaces"
        let json = response(command: "track.volume", verified: true)
        let script = "[ \"$#\" -eq 6 ] && [ \"$1\" = track ] && [ \"$4\" = -6 ] && [ \"$6\" = \(shellQuote(name)) ] || exit 99\n" + emit(json)
        try withCLI(script) { executable in
            let value = try CLIExecutor(executableURL: executable).execute(["track", "volume", "1", "-6", "--expect-name", name])
            XCTAssertEqual(value["ok"], true)
            XCTAssertEqual(value["verified"], true)
        }
    }

    func testEnvironmentIsInheritedAndChildStderrIsSeparate() throws {
        let keys = ["LOGICD_PATH", "LOGICCTL_SOCKET"]
        let old = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, getenv(key).map { String(cString: $0) })
        })
        defer {
            for key in keys {
                if let value = old[key] ?? nil { setenv(key, value, 1) }
                else { unsetenv(key) }
            }
        }
        setenv("LOGICD_PATH", "/synthetic/daemon", 1)
        setenv("LOGICCTL_SOCKET", "/synthetic/socket", 1)
        let script = "[ \"$LOGICD_PATH\" = /synthetic/daemon ] && [ \"$LOGICCTL_SOCKET\" = /synthetic/socket ] || exit 99\nprintf 'fake CLI diagnostic\\n' >&2\n" + emit(response())
        try withCLI(script) { executable in
            XCTAssertEqual(try CLIExecutor(executableURL: executable).execute(["status"])["ok"], true)
        }
    }

    func testRejectsMalformedMissingFieldsNoisyAndMultipleJSONResponses() throws {
        let valid = response()
        for text in ["not JSON", "[]", "{\"ok\":true}", "log line\n" + valid, valid + "\n" + valid] {
            try withCLI(emit(text)) { executable in
                assertUnknown(try CLIExecutor(executableURL: executable).execute(["status"]), error: "cli_response_malformed")
            }
        }
    }

    func testRejectsWrongCommand() throws {
        try withCLI(emit(response(command: "state"))) { executable in
            assertUnknown(try CLIExecutor(executableURL: executable).execute(["status"]), error: "cli_response_mismatch")
        }
    }

    func testRejectsExitStatusContradictingResponse() throws {
        for (ok, exitCode) in [(true, 1), (false, 0)] {
            try withCLI(emit(response(ok: ok), exitCode: exitCode)) { executable in
                assertUnknown(try CLIExecutor(executableURL: executable).execute(["status"]), error: "cli_exit_mismatch")
            }
        }
    }

    func testDrainsMoreThanAPipeBufferConcurrently() throws {
        let payload = String(repeating: "x", count: 262_144)
        let json = response(extra: ",\"result\":{\"payload\":\"\(payload)\"}")
        try withCLI(emit(json)) { executable in
            let value = try CLIExecutor(executableURL: executable, timeout: 0.8).execute(["status"])
            XCTAssertEqual(value["result"]?["payload"], .string(payload))
        }
    }

    func testCapsStdoutWithoutReturningTruncatedJSONAsSuccess() throws {
        let json = response(extra: ",\"result\":\"\(String(repeating: "x", count: 1_100_000))\"")
        try withCLI(emit(json)) { executable in
            assertUnknown(try CLIExecutor(executableURL: executable, timeout: 0.8).execute(["status"]), error: "cli_output_limit")
        }
    }

    func testTimeoutEscalatesForIgnoredSIGTERMandDoesNotRetry() throws {
        try withCLI("trap '' TERM\nwhile :; do :; done") { executable in
            let start = Date()
            let value = try CLIExecutor(executableURL: executable, timeout: 0.05).execute(["status"])
            assertUnknown(value, error: "cli_timeout")
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.9)
        }
    }

    func testUnavailableExecutableIsRejectedBeforeLaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("missing-logicctl-\(UUID().uuidString)")
        let value = try CLIExecutor(executableURL: url).execute(["status"])
        XCTAssertEqual(value["error"], "cli_unavailable")
        XCTAssertEqual(value["ok"], false)
        XCTAssertEqual(value["verified"], false)
        XCTAssertEqual(value["execution"]?["state"], "rejected")
    }

    func testInvalidLogicCommandIsRejectedBeforeExecution() throws {
        try withCLI(emit(response(command: "track.pan"))) { executable in
            XCTAssertThrowsError(try CLIExecutor(executableURL: executable).execute(["track", "pan", "1", "2"])) { error in
                XCTAssertEqual((error as? CommandError)?.code, "invalid_argument")
            }
        }
    }
}
