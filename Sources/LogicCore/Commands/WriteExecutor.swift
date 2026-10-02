import CryptoKit
import Foundation

// The execution contract (docs/execution-contract.md): one place that decides
// whether a request may run, runs it with a deadline, and records what is and
// is not known about the result. It never turns "unknown" into success and never
// repeats a write by itself.

public struct ExecutionOptions: Equatable, Sendable {
    public var idempotencyKey: String?
    public var expectSession: Int?
    public var deadline: TimeInterval?

    public init(idempotencyKey: String? = nil, expectSession: Int? = nil, deadline: TimeInterval? = nil) {
        self.idempotencyKey = idempotencyKey
        self.expectSession = expectSession
        self.deadline = deadline
    }

    public init(request: Request) {
        self.init(idempotencyKey: request.idempotencyKey, expectSession: request.expectSession,
                  deadline: request.deadlineMs.map { Double($0) / 1000 })
    }
}

/// What the journal keeps of a finished write so a retry can be answered without acting again.
public struct StoredOutcome: Codable, Equatable {
    public var ok: Bool
    public var verified: Bool
    public var backend: String
    public var readbackBackend: String?
    public var requested: JSONValue?
    public var observed: JSONValue?
    public var result: JSONValue?
    public var error: String?
    public var message: String?
    public var observation: JSONValue?

    init(_ routed: RoutedOutcome) {
        let o = routed.outcome
        ok = o.ok; verified = o.verified; backend = routed.backend; readbackBackend = routed.readbackBackend
        requested = o.requested; observed = o.observed; result = o.result
        error = o.error; message = o.message; observation = o.observation
    }

    var routed: RoutedOutcome {
        RoutedOutcome(backend: backend, readbackBackend: readbackBackend,
                      outcome: Outcome(ok: ok, verified: verified, requested: requested, observed: observed,
                                       result: result, error: error, message: message, observation: observation))
    }
}

public struct JournalEntry: Codable, Equatable {
    public enum State: String, Codable {
        /// Started, no result yet.
        case inFlight = "in_flight"
        /// Finished and verified. A retry with the same key replays it.
        case completed
        /// Refused before anything could reach Logic. The same key may run again.
        case notApplied = "not_applied"
        /// May or may not have changed Logic. The same key is refused; read the state and use a new key.
        case unknown
    }

    public var key: String
    public var fingerprint: String
    public var command: String
    public var state: State
    public var startedAt: Date
    public var finishedAt: Date?
    public var reason: String?
    public var stored: StoredOutcome?
}

/// Append-only: the last entry saved for a key wins.
public protocol JournalStore: AnyObject {
    func load() -> [JournalEntry]
    func save(_ entry: JournalEntry)
}

public final class MemoryJournalStore: JournalStore {
    private var entries: [JournalEntry]
    private let lock = NSLock()
    public init(_ entries: [JournalEntry] = []) { self.entries = entries }
    public func load() -> [JournalEntry] { lock.lock(); defer { lock.unlock() }; return entries }
    public func save(_ entry: JournalEntry) { lock.lock(); entries.append(entry); lock.unlock() }
}

/// One JSON object per line. A line that cannot be read is skipped; the file is
/// compacted to the newest entries when it grows.
public final class FileJournalStore: JournalStore {
    private let url: URL
    private let lock = NSLock()
    static let keep = 500
    static let compactAt = 2000

    public init(path: String) {
        url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    public func load() -> [JournalEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let (_, decoder) = Self.coder()
        var entries = text.split(separator: "\n").compactMap { try? decoder.decode(JournalEntry.self, from: Data($0.utf8)) }
        if entries.count > Self.compactAt {
            var latest: [String: JournalEntry] = [:]
            var order: [String] = []
            for entry in entries { if latest[entry.key] == nil { order.append(entry.key) }; latest[entry.key] = entry }
            entries = order.suffix(Self.keep).compactMap { latest[$0] }
            rewrite(entries)
        }
        return entries
    }

    public func save(_ entry: JournalEntry) {
        lock.lock(); defer { lock.unlock() }
        let (encoder, _) = Self.coder()
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.synchronize()
        } else {
            try? line.write(to: url)
        }
    }

    private func rewrite(_ entries: [JournalEntry]) {
        let (encoder, _) = Self.coder()
        var data = Data()
        for entry in entries { if let line = try? encoder.encode(entry) { data.append(line); data.append(0x0A) } }
        try? data.write(to: url, options: .atomic)
    }
}

public struct ExecutionResult {
    public var routed: RoutedOutcome
    public var execution: JSONValue
}

public final class WriteExecutor {
    /// Failures that mean nothing reached Logic. A write that ended with one of these may be
    /// retried with the same key. Any other failure leaves the effect unknown.
    static let notApplied: Set<String> = [
        "logic_not_running", "surface_not_connected", "invalid_argument", "usage", "unknown_command",
        "unsupported_backend", "unsupported_backend_command", "no_such_track", "bank_unknown",
        "bank_home_failed", "daemon_upgrade_required", "precondition_failed", "target_mismatch",
        "unsupported_logic_version",
    ]

    public static func isValidKey(_ key: String) -> Bool {
        (1...128).contains(key.count) && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._:-".contains($0)) }
    }

    public static func fingerprint(_ request: Request) -> String {
        let args = request.args.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\u{1}")
        let text = [request.command, args, request.backend ?? BackendKind.mcu.rawValue].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private let store: JournalStore
    private let queueLimit: Int
    private let defaultDeadline: TimeInterval
    private let sessionProbe: () -> Int?
    private let now: () -> Date
    private let log: (String) -> Void

    private let gate = DispatchSemaphore(value: 1)  // one command at a time; held until the command really ends
    private let lock = NSLock()
    private var entries: [String: JournalEntry] = [:]
    private var waiting = 0
    private var stopping = false

    public init(store: JournalStore, queueLimit: Int = 8, defaultDeadline: TimeInterval = 30,
                sessionProbe: @escaping () -> Int? = { nil }, now: @escaping () -> Date = Date.init,
                log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.queueLimit = queueLimit
        self.defaultDeadline = defaultDeadline
        self.sessionProbe = sessionProbe
        self.now = now
        self.log = log
        for entry in store.load() { entries[entry.key] = entry }  // last saved entry per key wins
        // A write that was in flight when the previous daemon ended has an unknown effect.
        for (key, var entry) in entries where entry.state == .inFlight {
            entry.state = .unknown
            entry.reason = "daemon_restarted"
            entry.finishedAt = now()
            entries[key] = entry
            store.save(entry)
            log("ジャーナル: 前回のdaemon終了時に実行中だった操作を不明として記録しました key=\(key)")
        }
    }

    /// Called when the daemon stops: whatever is still running ends with an unknown effect.
    public func shutdown() {
        lock.lock(); defer { lock.unlock() }
        stopping = true
        for (key, var entry) in entries where entry.state == .inFlight {
            entry.state = .unknown
            entry.reason = "daemon_stopped"
            entry.finishedAt = now()
            entries[key] = entry
            store.save(entry)
        }
    }

    // MARK: - Execute

    private final class Job {
        let lock = NSLock()
        let done = DispatchSemaphore(value: 0)
        var result: (routed: RoutedOutcome, final: JournalEntry.State)?
        var abandoned = false
    }

    public func execute(_ command: LogicCommand, request: Request, options: ExecutionOptions,
                        run: @escaping () -> RoutedOutcome) -> ExecutionResult {
        let backend = request.backend ?? BackendKind.mcu.rawValue
        let key = options.idempotencyKey
        let isWrite = command.isWrite
        let enqueued = now()
        let deadline = enqueued.addingTimeInterval(options.deadline ?? defaultDeadline)

        func reject(_ code: String, _ message: String, state: String = "rejected",
                    extra: [String: JSONValue] = [:]) -> ExecutionResult {
            var execution: [String: JSONValue] = ["state": .string(state), "idempotency_key": .string(key)]
            for (name, value) in extra { execution[name] = value }
            return ExecutionResult(routed: RoutedOutcome(backend: backend, readbackBackend: nil,
                                                         outcome: .failure(code, message)),
                                   execution: .object(execution))
        }

        if let key {
            guard isWrite else {
                return reject("invalid_argument", "冪等キーは、状態を変更するコマンドだけで使えます。")
            }
            guard Self.isValidKey(key) else {
                return reject("invalid_argument", "冪等キーは英数字と . _ : - の1〜128文字で指定してください。")
            }
        }
        let fingerprint = Self.fingerprint(request)

        // 1. A duplicate is answered before it waits in the queue.
        if let key, let early = decide(key: key, fingerprint: fingerprint, backend: backend, reject: reject) { return early }

        // 2. Wait for the single execution slot, but only for a bounded number of callers and time.
        lock.lock()
        if stopping { lock.unlock(); return reject("shutting_down", "logicd は停止中です。") }
        if waiting >= queueLimit {
            lock.unlock()
            return reject("queue_full", "待機中のリクエストが多すぎます（上限 \(queueLimit)）。後でやり直してください。")
        }
        waiting += 1
        lock.unlock()
        let acquired = gate.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow))
        lock.lock(); waiting -= 1; lock.unlock()
        guard acquired == .success else {
            return reject("deadline_exceeded", "待ち時間の上限を超えたため、実行していません。")
        }
        let waitedMs = Int(now().timeIntervalSince(enqueued) * 1000)

        // From here the slot is released by the worker, or here when nothing is started.
        func refuse(_ result: ExecutionResult) -> ExecutionResult { gate.signal(); return result }

        if let key, let late = decide(key: key, fingerprint: fingerprint, backend: backend, reject: reject) {
            return refuse(late)  // changed while this request waited
        }
        if let expected = options.expectSession {
            let current = sessionProbe()
            if current != expected {
                return refuse(reject("precondition_failed",
                                     "Logicとの接続が変わったため、実行していません（期待した世代 \(expected)、現在 \(current.map(String.init) ?? "未接続")）。状態を読み直してください。",
                                     extra: ["expected_session": .int(expected), "current_session": .int(current)]))
            }
        }
        if now() >= deadline { return refuse(reject("deadline_exceeded", "待ち時間の上限を超えたため、実行していません。")) }
        lock.lock()
        if stopping { lock.unlock(); return refuse(reject("shutting_down", "logicd は停止中です。")) }
        let startedAt = now()
        if let key, isWrite {
            let entry = JournalEntry(key: key, fingerprint: fingerprint, command: request.command, state: .inFlight,
                                     startedAt: startedAt, finishedAt: nil, reason: nil, stored: nil)
            entries[key] = entry
            store.save(entry)
        }
        lock.unlock()

        // 3. Run on a worker so the caller can give up at the deadline. The slot stays taken until
        //    the worker really ends, so a later request never overlaps a command still talking to Logic.
        let job = Job()
        Thread.detachNewThread { [self] in
            let routed = run()
            let final = classify(routed.outcome)
            job.lock.lock(); job.result = (routed, final); job.lock.unlock()
            if let key, isWrite { finish(key: key, state: final, routed: routed, reason: nil) }
            job.done.signal()
            gate.signal()
        }
        if job.done.wait(timeout: .now() + max(0, deadline.timeIntervalSinceNow)) == .success,
           let (routed, final) = job.result {
            return ExecutionResult(routed: routed, execution: executionJSON(
                state: isWrite ? (final == .completed ? "completed" : final == .notApplied ? "not_applied" : "unknown") : "read",
                key: key, waitedMs: waitedMs))
        }
        job.lock.lock()
        let late = job.result
        if late == nil { job.abandoned = true }
        job.lock.unlock()
        if let (routed, final) = late {  // finished in the same instant
            return ExecutionResult(routed: routed, execution: executionJSON(
                state: isWrite ? (final == .completed ? "completed" : final == .notApplied ? "not_applied" : "unknown") : "read",
                key: key, waitedMs: waitedMs))
        }
        if let key, isWrite { markUnknownIfInFlight(key: key, reason: "deadline_exceeded") }
        return ExecutionResult(
            routed: RoutedOutcome(backend: backend, readbackBackend: nil, outcome: .failure(
                "timeout", "時間内に完了しませんでした。実行された可能性があります。結果は不明です。状態を読み直してください。")),
            execution: executionJSON(state: isWrite ? "unknown" : "read", key: key, waitedMs: waitedMs,
                                     extra: ["reason": "deadline_exceeded"]))
    }

    // MARK: - Decisions

    private func decide(key: String, fingerprint: String, backend: String,
                        reject: (String, String, String, [String: JSONValue]) -> ExecutionResult) -> ExecutionResult? {
        lock.lock(); let entry = entries[key]; lock.unlock()
        guard let entry else { return nil }
        let previous: [String: JSONValue] = [
            "previous": ["state": .string(entry.state.rawValue), "command": .string(entry.command),
                         "started_at": .string(ISO8601DateFormatter().string(from: entry.startedAt)),
                         "reason": .string(entry.reason)],
        ]
        guard entry.fingerprint == fingerprint else {
            return reject("idempotency_key_conflict", "同じキーで、内容の違う操作はできません。別のキーを使ってください。",
                          "rejected", previous)
        }
        switch entry.state {
        case .completed:
            guard let stored = entry.stored else { return nil }
            return ExecutionResult(routed: stored.routed, execution: executionJSON(
                state: "replayed", key: key, waitedMs: 0,
                extra: ["replayed_from": .string(ISO8601DateFormatter().string(from: entry.finishedAt ?? entry.startedAt))]))
        case .inFlight:
            return reject("request_in_flight", "同じキーの操作がまだ実行中です。完了を待ってから状態を確認してください。",
                          "rejected", previous)
        case .unknown:
            return reject("outcome_unknown",
                          "同じキーの前回の操作は、結果が不明です。自動では再実行しません。状態を読み直し、必要なら別のキーで実行してください。",
                          "unknown", previous)
        case .notApplied:
            return nil  // refused before reaching Logic: the same key may run again
        }
    }

    private func classify(_ outcome: Outcome) -> JournalEntry.State {
        if outcome.ok && outcome.verified { return .completed }
        if let error = outcome.error, Self.notApplied.contains(error) { return .notApplied }
        return .unknown
    }

    private func finish(key: String, state: JournalEntry.State, routed: RoutedOutcome, reason: String?) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[key] else { return }
        entry.state = state
        entry.finishedAt = now()
        entry.reason = state == .unknown ? (routed.outcome.error ?? reason) : nil
        entry.stored = state == .completed ? StoredOutcome(routed) : nil
        entries[key] = entry
        store.save(entry)
    }

    private func markUnknownIfInFlight(key: String, reason: String) {
        lock.lock(); defer { lock.unlock() }
        guard var entry = entries[key], entry.state == .inFlight else { return }
        entry.state = .unknown
        entry.reason = reason
        entry.finishedAt = now()
        entries[key] = entry
        store.save(entry)
    }

    private func executionJSON(state: String, key: String?, waitedMs: Int, extra: [String: JSONValue] = [:]) -> JSONValue {
        var o: [String: JSONValue] = ["state": .string(state), "idempotency_key": .string(key), "queue_wait_ms": .int(waitedMs)]
        for (name, value) in extra { o[name] = value }
        return .object(o)
    }
}
