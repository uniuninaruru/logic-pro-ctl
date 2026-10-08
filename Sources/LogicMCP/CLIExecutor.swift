import Darwin
import Foundation
import LogicCore

/// Runs the existing CLI so its daemon gates and readback contract stay authoritative.
/// A failed or interrupted child is never retried: termination cannot undo an
/// operation that the CLI has already dispatched to Logic.
public final class CLIExecutor {
    private let executableURL: URL
    private let timeout: TimeInterval
    private static let stdoutLimit = 1_048_576

    public init(executableURL: URL, timeout: TimeInterval = 40) {
        self.executableURL = executableURL
        self.timeout = timeout.isFinite ? max(0.001, timeout) : 40
    }

    public func execute(_ arguments: [String]) throws -> JSONValue {
        let request = try CLIParser.parse(arguments)
        _ = try LogicCommand(request: request)
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return failure(request, "cli_unavailable", "The logicctl executable is unavailable.", status: "rejected")
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        let stdout = Pipe()
        process.standardOutput = stdout
        let descriptor = stdout.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return failure(request, "cli_unavailable", "Cannot prepare the CLI output pipe.", status: "rejected")
        }

        let capture = BoundedCLIOutput(limit: Self.stdoutLimit)
        let drained = DispatchGroup()
        drained.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { drained.leave() }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            while !capture.shouldStop {
                let count = bytes.withUnsafeMutableBytes { buffer in
                    Darwin.read(descriptor, buffer.baseAddress, buffer.count)
                }
                if count > 0 {
                    capture.append(Data(bytes.prefix(count)))
                } else if count == 0 {
                    capture.finish(reachedEOF: true)
                    return
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    // Wait for bytes rather than imposing a delay on every small
                    // pipe write. A short bound also lets stop() end this reader.
                    var ready = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                    _ = Darwin.poll(&ready, 1, 10)
                } else {
                    capture.finish(reachedEOF: false)
                    return
                }
            }
        }
        defer {
            capture.stop()
            drained.wait()
            try? stdout.fileHandleForReading.close()
            try? stdout.fileHandleForWriting.close()
        }

        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
            // Only the child should retain the write end; otherwise EOF never arrives.
            try? stdout.fileHandleForWriting.close()
        } catch {
            return failure(request, "cli_unavailable", "Cannot launch logicctl: \(error.localizedDescription)", status: "rejected")
        }

        let deadline = DispatchTime.now() + timeout
        var timedOut = false
        var limitExceeded = false
        var childExited = false
        while !childExited {
            if capture.exceededLimit {
                limitExceeded = true
                break
            }
            let nextCheck = min(deadline, DispatchTime.now() + 0.02)
            if terminated.wait(timeout: nextCheck) == .success {
                childExited = true
            } else if DispatchTime.now() >= deadline {
                timedOut = true
                break
            }
        }

        if !childExited {
            if process.isRunning { process.terminate() }
            if terminated.wait(timeout: .now() + 0.1) == .timedOut, process.isRunning {
                // SIGTERM may be ignored. Kill and reap this child, without retrying.
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        // A descendant can retain stdout after the CLI exits. Do not wait for it
        // indefinitely or accept a response whose output stream is still open.
        if drained.wait(timeout: .now() + 0.1) == .timedOut {
            capture.stop()
        }
        drained.wait()
        let output = capture.snapshot()

        if timedOut {
            return failure(request, "cli_timeout", "logicctl timed out; its operation outcome is unknown. No retry was made.")
        }
        if limitExceeded || output.exceededLimit {
            return failure(request, "cli_output_limit", "logicctl output exceeded 1 MiB; its operation outcome is unknown. No retry was made.")
        }
        guard output.reachedEOF else {
            return failure(request, "cli_output_incomplete", "The CLI output stream did not finish; its operation outcome is unknown.")
        }
        guard process.terminationReason == .exit else {
            return failure(request, "cli_terminated", "logicctl ended by a signal; its operation outcome is unknown.")
        }

        let value: JSONValue
        let response: Response
        do {
            // JSONSerialization rejects trailing noise or a second JSON document.
            guard try JSONSerialization.jsonObject(with: output.data) is [String: Any] else {
                return failure(request, "cli_response_malformed", "logicctl did not return a JSON response object.")
            }
            let decoder = JSONDecoder()
            response = try decoder.decode(Response.self, from: output.data)
            value = try decoder.decode(JSONValue.self, from: output.data)
        } catch {
            return failure(request, "cli_response_malformed", "logicctl did not return exactly one valid CLI response.")
        }
        guard response.command == request.command else {
            return failure(request, "cli_response_mismatch", "logicctl returned a different command; the requested outcome is unknown.")
        }
        guard (process.terminationStatus == 0) == response.ok else {
            return failure(request, "cli_exit_mismatch", "logicctl exit status contradicts its response; the operation outcome is unknown.")
        }
        // Preserve optional/unknown fields and verified:false, including genuine
        // CLI errors with a nonzero exit. Sending is never promoted to verification.
        return value
    }

    private func failure(_ request: Request, _ code: String, _ message: String,
                         status: String = "unknown") -> JSONValue {
        ["id": .string(request.id), "command": .string(request.command),
         "ok": false, "verified": false, "error": .string(code),
         "message": .string(message), "execution": ["state": .string(status), "retried": false]]
    }
}

private final class BoundedCLIOutput: @unchecked Sendable {
    struct Snapshot {
        var data: Data
        var exceededLimit: Bool
        var reachedEOF: Bool
    }

    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private var exceeded = false
    private var eof = false
    private var stopped = false

    init(limit: Int) { self.limit = limit }

    var shouldStop: Bool { locked { stopped } }
    var exceededLimit: Bool { locked { exceeded } }

    func append(_ bytes: Data) {
        locked {
            let remaining = limit - data.count
            if bytes.count > remaining { exceeded = true }
            if remaining > 0 { data.append(bytes.prefix(remaining)) }
        }
    }

    func finish(reachedEOF: Bool) { locked { eof = reachedEOF } }
    func stop() { locked { stopped = true } }
    func snapshot() -> Snapshot { locked { Snapshot(data: data, exceededLimit: exceeded, reachedEOF: eof) } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
