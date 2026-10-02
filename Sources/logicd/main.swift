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
        unlink(socketPath)
        exit(0)
    }
    src.resume()
    signalSources.append(src)
}

let commandLock = NSLock()

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
        return (Response(id: request.id, ok: true, command: request.command, message: "logicd を停止します"), true)
    }
    commandLock.lock()
    let started = Date()
    let routed = router.execute(command, backend: request.backend)
    let o = routed.outcome
    commandLock.unlock()
    log("id=\(request.id) cmd=\(request.command) backend=\(routed.backend) readback=\(routed.readbackBackend ?? "-") "
        + "args=\(request.args) ok=\(o.ok) verified=\(o.verified) "
        + "error=\(o.error ?? "-") ms=\(Int(Date().timeIntervalSince(started) * 1000))")
    return (Response(id: request.id, ok: o.ok, command: request.command, backend: routed.backend,
                     readbackBackend: routed.readbackBackend,
                     verified: o.verified, requested: o.requested, observed: o.observed, result: o.result,
                     error: o.error, message: o.message, observation: o.observation), false)
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
