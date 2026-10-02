import Foundation
import LogicCore

// logicd: owns the connection to Logic (virtual MCU ports must stay alive
// for Logic to keep its control surface) and serves logicctl over a Unix
// socket, one JSON request/response per line. Commands run one at a time.
//
//   logicd [--socket PATH] [--trace]
// Diagnostics go to stderr; --trace (or LOGICD_TRACE=1) logs every MIDI message.

let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
func log(_ s: String) {
    FileHandle.standardError.write(Data("\(iso.string(from: Date())) logicd \(s)\n".utf8))
}

var socketPath = defaultSocketPath
var trace = ProcessInfo.processInfo.environment["LOGICD_TRACE"] == "1"
var argv = Array(CommandLine.arguments.dropFirst())
while let arg = argv.first {
    argv.removeFirst()
    switch arg {
    case "--socket" where !argv.isEmpty: socketPath = argv.removeFirst()
    case "--trace": trace = true
    default:
        log("使い方: logicd [--socket PATH] [--trace]")
        exit(64)
    }
}

let backend = MCUBackend(trace: trace, log: log)
let appleEventBackend = AppleEventTransportBackend(readback: backend)
let router = CommandRouter(mcu: backend, appleEvent: appleEventBackend)
// Serialises commands, enforces deadlines/preconditions and records writes so a retry is
// never a second effect (docs/execution-contract.md).
let journalPath = ProcessInfo.processInfo.environment["LOGICCTL_JOURNAL"]
    ?? NSString(string: "~/Library/Application Support/logicctl/journal.jsonl").expandingTildeInPath
let executor = WriteExecutor(store: FileJournalStore(path: journalPath),
                             sessionProbe: { backend.sessionGeneration() }, log: log)
do {
    try backend.start()
} catch {
    log("エラー: \(error)")
    exit(1)
}

let listener: SocketListener
do {
    listener = try SocketListener(path: socketPath)
} catch {
    log("エラー: \(error)")
    exit(1)
}
log("PID=\(getpid())、接続を待っています: \(socketPath)")

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler {
        log("シグナル \(sig) を受け取り、終了します")
        executor.shutdown()
        unlink(socketPath)
        exit(0)
    }
    src.resume()
    signalSources.append(src)
}

/// Runs a command on its backend. A request that names the target it expects (`expect_name`)
/// can only be honoured by the MCU path, which can read strip names; it is never sent anywhere
/// else, and never without the check.
func route(_ command: LogicCommand, _ request: Request) -> RoutedOutcome {
    guard let expected = request.args[LogicCommand.expectNameKey] else {
        return router.execute(command, backend: request.backend)
    }
    do {
        guard try CommandBackendSelection.resolve(request.backend, for: command) == .mcu else {
            throw CommandError("unsupported_backend_command", "名前の照合は mcu 経路だけで使えます。")
        }
    } catch let e as CommandError {
        return RoutedOutcome(backend: request.backend ?? BackendKind.mcu.rawValue, readbackBackend: nil,
                             outcome: .failure(e.code, e.message))
    } catch {
        return RoutedOutcome(backend: request.backend ?? BackendKind.mcu.rawValue, readbackBackend: nil,
                             outcome: .failure("internal", String(describing: error)))
    }
    return RoutedOutcome(backend: BackendKind.mcu.rawValue, readbackBackend: nil,
                         outcome: backend.execute(command, expectName: expected))
}

/// What this daemon honours beyond the basics. logicctl asks before sending an option an older
/// daemon would silently ignore (and so run the write without the safeguard).
func addSafetyCapabilities(_ outcome: Outcome) -> Outcome {
    guard case .object(var result)? = outcome.result, case .object(var capabilities)? = result["capabilities"]
            ?? .object([:]) else { return outcome }
    capabilities["execution_contract"] = .bool(true)  // --idempotency-key, --expect-session, --deadline-ms
    capabilities["target_expectation"] = .bool(true)  // --expect-name
    result["capabilities"] = .object(capabilities)
    var changed = outcome
    changed.result = .object(result)
    return changed
}

func handle(_ line: String) -> (response: Response, stop: Bool) {
    guard let request = try? JSONDecoder().decode(Request.self, from: Data(line.utf8)) else {
        return (Response(id: "", ok: false, command: "", error: "bad_request", message: "リクエストのJSON形式が正しくありません"), false)
    }
    let command: LogicCommand
    do {
        command = try LogicCommand(request: request)
    } catch let e as CommandError {
        return (Response(id: request.id, ok: false, command: request.command, error: e.code, message: e.message), false)
    } catch {
        return (Response(id: request.id, ok: false, command: request.command, error: "internal", message: "\(error)"), false)
    }
    if command == .daemonStop {
        do { _ = try CommandBackendSelection.resolve(request.backend, for: command) }
        catch let e as CommandError {
            return (Response(id: request.id, ok: false, command: request.command, backend: request.backend,
                             error: e.code, message: e.message), false)
        } catch {
            return (Response(id: request.id, ok: false, command: request.command, error: "internal"), false)
        }
        executor.shutdown()
        return (Response(id: request.id, ok: true, command: request.command, message: "logicd を停止します"), true)
    }
    let started = Date()
    let executed = executor.execute(command, request: request, options: ExecutionOptions(request: request)) {
        route(command, request)
    }
    let routed = executed.routed
    let o = command == .status ? addSafetyCapabilities(routed.outcome) : routed.outcome
    log("id=\(request.id) cmd=\(request.command) backend=\(routed.backend) readback=\(routed.readbackBackend ?? "-") "
        + "args=\(request.args) key=\(request.idempotencyKey ?? "-") exec=\(executed.execution["state"] ?? .null) "
        + "ok=\(o.ok) verified=\(o.verified) "
        + "error=\(o.error ?? "-") ms=\(Int(Date().timeIntervalSince(started) * 1000))")
    return (Response(id: request.id, ok: o.ok, command: request.command, backend: routed.backend,
                     readbackBackend: routed.readbackBackend,
                     verified: o.verified, requested: o.requested, observed: o.observed, result: o.result,
                     error: o.error, message: o.message, observation: o.observation,
                     execution: executed.execution), false)
}

Thread.detachNewThread {
    while true {
        guard let conn = try? listener.accept() else { continue }
        Thread.detachNewThread {
            while let line = try? conn.readLine() {
                let (response, stop) = handle(line)
                let data = (try? JSONEncoder.logicctl.encode(response)) ?? Data("{\"ok\":false}".utf8)
                try? conn.writeLine(String(decoding: data, as: UTF8.self))
                if stop {
                    log("停止リクエストにより終了します")
                    unlink(socketPath)
                    exit(0)
                }
            }
        }
    }
}

RunLoop.main.run()
