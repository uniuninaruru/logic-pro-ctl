import Darwin
import Foundation
import LogicCore

// logicctl: thin client. Parses argv, probes native support when selected,
// sends the command Request to logicd, and prints
// the Response as one JSON line on stdout. Starts logicd if it is not
// running. Exit status: 0 ok, 1 command failed (incl. verification),
// 64 usage. Connection failures also return 1.

func stderr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func emit(_ response: Response) -> Never {
    let data = (try? JSONEncoder.logicctl.encode(response)) ?? Data("{\"ok\":false}".utf8)
    print(String(decoding: data, as: UTF8.self))
    exit(response.ok ? 0 : 1)
}

let argv = Array(CommandLine.arguments.dropFirst())
if argv.isEmpty || argv.contains("--help") || argv.contains("-h") {
    stderr(CLIParser.usage)
    exit(argv.isEmpty ? 64 : 0)
}

let request: Request
do {
    request = try CLIParser.parse(argv)
} catch let e as CommandError {
    stderr(CLIParser.usage)
    let data = try JSONEncoder.logicctl.encode(
        Response(id: "", ok: false, command: argv.joined(separator: " "), error: e.code, message: e.message))
    print(String(decoding: data, as: UTF8.self))
    exit(64)
}

/// Starts logicd (next to this executable, or $LOGICD_PATH) in its own session,
/// logging to ~/Library/Logs/logicctl/logicd.log.
func startDaemon() -> Bool {
    let env = ProcessInfo.processInfo.environment
    let selfURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let path = env["LOGICD_PATH"] ?? selfURL.deletingLastPathComponent().appendingPathComponent("logicd").path
    guard FileManager.default.isExecutableFile(atPath: path) else {
        stderr("logicctl: \(path) に logicd がありません。LOGICD_PATH で場所を指定できます")
        return false
    }
    let logDir = NSString(string: "~/Library/Logs/logicctl").expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    let logPath = logDir + "/logicd.log"

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    posix_spawn_file_actions_addopen(&actions, 2, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

    var pid: pid_t = 0
    let args = [path]
    var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
    defer { cargs.forEach { free($0) } }
    let rc = posix_spawn(&pid, path, &actions, &attr, &cargs, environ)
    guard rc == 0 else {
        stderr("logicctl: logicd を起動できませんでした: \(String(cString: strerror(rc)))")
        return false
    }
    stderr("logicctl: logicd を起動しました。PID=\(pid)、ログ: \(logPath)")
    return true
}

var socket = try? LineSocket.connect(path: defaultSocketPath)
if socket == nil {
    if request.command == "daemon.stop" {
        emit(Response(id: request.id, ok: true, command: request.command, message: "logicd は起動していません"))
    }
    if startDaemon() {
        let deadline = Date().addingTimeInterval(5)
        while socket == nil && Date() < deadline {
            usleep(100_000)
            socket = try? LineSocket.connect(path: defaultSocketPath)
        }
    }
}
guard let socket else {
    emit(Response(id: request.id, ok: false, command: request.command, error: "daemon_unavailable",
                  message: "logicd に接続できません。接続先: \(defaultSocketPath)"))
}

do {
    // Older daemons ignore request fields they do not know and would run the command without the
    // safeguard the caller asked for (another backend, a missing precondition, no duplicate
    // protection). Ask what the running daemon honours before sending any such request.
    var needed: [(capability: String, message: String)] = []
    if request.backend == BackendKind.appleEvent.rawValue {
        needed.append(("appleevent_transport",
                       "起動中の logicd はAppleEvent操作に対応していません。logicctl daemon stop で停止してから、このコマンドを再実行してください"))
    }
    if request.idempotencyKey != nil || request.expectSession != nil || request.deadlineMs != nil {
        needed.append(("execution_contract",
                       "起動中の logicd は --idempotency-key / --expect-session / --deadline-ms に対応していません。指定した安全装置なしで実行しないよう、何も送信していません。logicctl daemon stop で停止してから、このコマンドを再実行してください"))
    }
    if request.args[LogicCommand.expectNameKey] != nil {
        needed.append(("target_expectation",
                       "起動中の logicd は --expect-name に対応していません。対象を確認せずに実行しないよう、何も送信していません。logicctl daemon stop で停止してから、このコマンドを再実行してください"))
    }
    if !needed.isEmpty {
        let status = Request(command: "status")
        try socket.writeLine(String(decoding: try JSONEncoder.logicctl.encode(status), as: UTF8.self))
        let statusLine = try socket.readLine()
        let statusResponse = try JSONDecoder().decode(Response.self, from: Data(statusLine.utf8))
        for need in needed {
            guard statusResponse.ok, statusResponse.result?["capabilities"]?[need.capability] == .bool(true) else {
                emit(Response(id: request.id, ok: false, command: request.command,
                              backend: request.backend, error: "daemon_upgrade_required", message: need.message))
            }
        }
    }
    try socket.writeLine(String(decoding: try JSONEncoder.logicctl.encode(request), as: UTF8.self))
    let line = try socket.readLine()
    let response = try JSONDecoder().decode(Response.self, from: Data(line.utf8))
    if request.backend == BackendKind.appleEvent.rawValue && response.backend != request.backend {
        emit(Response(id: request.id, ok: false, command: request.command,
                      backend: request.backend, error: "backend_mismatch",
                      message: "logicd の応答した経路が指定と異なります（応答: \(response.backend ?? "未指定")、指定: appleevent）。再送信はしていません"))
    }
    print(line)
    exit(response.ok ? 0 : 1)
} catch {
    emit(Response(id: request.id, ok: false, command: request.command, error: "daemon_unavailable",
                  message: "\(error)"))
}
