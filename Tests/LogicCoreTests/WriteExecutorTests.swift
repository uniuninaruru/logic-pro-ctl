import Foundation
@testable import LogicCore

// The execution contract (docs/execution-contract.md): an unknown result is never
// success, a repeated write is never a second effect, a different request never
// borrows another's key.
#if canImport(Testing)
import Testing

private final class Counter {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private func routed(ok: Bool = true, verified: Bool = true, error: String? = nil) -> RoutedOutcome {
    RoutedOutcome(backend: "mcu", readbackBackend: nil,
                  outcome: Outcome(ok: ok, verified: verified, requested: ["playing": true],
                                   observed: ["playing": ok ? true : false], error: error))
}

private func play(key: String? = nil, expect: Int? = nil, deadlineMs: Int? = nil,
                  command: String = "transport.play", args: [String: String] = [:]) -> (Request, LogicCommand, ExecutionOptions) {
    let request = Request(command: command, args: args, idempotencyKey: key, expectSession: expect, deadlineMs: deadlineMs)
    return (request, try! LogicCommand(request: request), ExecutionOptions(request: request))
}

@discardableResult
private func run(_ executor: WriteExecutor, _ call: (Request, LogicCommand, ExecutionOptions),
                 body: @escaping () -> RoutedOutcome) -> ExecutionResult {
    executor.execute(call.1, request: call.0, options: call.2, run: body)
}

private func eventually(_ seconds: Double = 2, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { if condition() { return true }; Thread.sleep(forTimeInterval: 0.005) }
    return condition()
}

private func state(_ result: ExecutionResult) -> JSONValue? { result.execution["state"] }
private func error(_ result: ExecutionResult) -> String? { result.routed.outcome.error }

@Test func retryWithTheSameKeyReplaysTheResultInsteadOfActingAgain() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let calls = Counter()
    let first = run(executor, play(key: "k1")) { calls.increment(); return routed() }
    let second = run(executor, play(key: "k1")) { calls.increment(); return routed() }
    #expect(calls.count == 1)
    #expect(state(first) == .string("completed"))
    #expect(state(second) == .string("replayed"))
    #expect(second.routed.outcome.ok && second.routed.outcome.verified)
    #expect(second.execution["replayed_from"] != nil)
}

@Test func theSameKeyWithDifferentContentIsRefused() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let calls = Counter()
    run(executor, play(key: "k1")) { calls.increment(); return routed() }
    let other = run(executor, play(key: "k1", command: "transport.stop")) { calls.increment(); return routed() }
    #expect(error(other) == "idempotency_key_conflict")
    #expect(state(other) == .string("rejected"))
    let backendDiffers = run(executor, (Request(command: "transport.play", backend: "appleevent", idempotencyKey: "k1"),
                                        .transportPlay, ExecutionOptions(idempotencyKey: "k1"))) { calls.increment(); return routed() }
    #expect(error(backendDiffers) == "idempotency_key_conflict")  // another route is another operation
    #expect(calls.count == 1)
}

@Test func aTimeoutIsUnknownAndNothingRepeatsItUntilItIsReconciled() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let calls = Counter()
    let release = DispatchSemaphore(value: 0)
    let slow = run(executor, play(key: "k1", deadlineMs: 60)) {
        calls.increment(); release.wait(); return routed()
    }
    #expect(error(slow) == "timeout")
    #expect(state(slow) == .string("unknown"))
    #expect(!slow.routed.outcome.ok)

    // While it is unknown, the same key neither runs again nor claims success.
    let retry = run(executor, play(key: "k1")) { calls.increment(); return routed() }
    #expect(error(retry) == "outcome_unknown")
    #expect(calls.count == 1)

    // The slow command finally ends verified: the journal reconciles, and the key now replays it.
    release.signal()
    #expect(eventually { state(run(executor, play(key: "k1")) { calls.increment(); return routed() }) == .string("replayed") })
    #expect(calls.count == 1)
}

@Test func failuresThatNeverReachedLogicMayRetryWithTheSameKey() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let calls = Counter()
    let first = run(executor, play(key: "k1")) {
        calls.increment(); return routed(ok: false, verified: false, error: "surface_not_connected")
    }
    #expect(state(first) == .string("not_applied"))
    let second = run(executor, play(key: "k1")) { calls.increment(); return routed() }
    #expect(state(second) == .string("completed"))
    #expect(calls.count == 2)
}

@Test func aFailureThatMayHaveChangedLogicBlocksTheKey() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let calls = Counter()
    let first = run(executor, play(key: "k1")) {
        calls.increment(); return routed(ok: false, verified: false, error: "verification_failed")
    }
    #expect(state(first) == .string("unknown"))
    let retry = run(executor, play(key: "k1")) { calls.increment(); return routed() }
    #expect(error(retry) == "outcome_unknown")
    #expect(calls.count == 1)
    // A new key is the caller's explicit decision to act again.
    let fresh = run(executor, play(key: "k2")) { calls.increment(); return routed() }
    #expect(state(fresh) == .string("completed"))
}

@Test func aDuplicateWhileTheFirstIsRunningIsRefusedNotQueued() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let calls = Counter()
    let release = DispatchSemaphore(value: 0)
    let started = DispatchSemaphore(value: 0)
    let box = Box<ExecutionResult?>(nil)
    Thread.detachNewThread {
        box.value = run(executor, play(key: "k1")) { calls.increment(); started.signal(); release.wait(); return routed() }
    }
    started.wait()
    let duplicate = run(executor, play(key: "k1")) { calls.increment(); return routed() }
    #expect(error(duplicate) == "request_in_flight")
    release.signal()
    #expect(eventually { box.value != nil })
    #expect(state(box.value!) == .string("completed"))
    #expect(calls.count == 1)
}

@Test func waitingPastTheDeadlineNeverRunsTheCommand() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let release = DispatchSemaphore(value: 0)
    let started = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        run(executor, play(key: "a")) { started.signal(); release.wait(); return routed() }
    }
    started.wait()
    let calls = Counter()
    let waiter = run(executor, play(key: "b", deadlineMs: 50)) { calls.increment(); return routed() }
    #expect(error(waiter) == "deadline_exceeded")
    #expect(state(waiter) == .string("rejected"))
    #expect(calls.count == 0)
    release.signal()
}

@Test func theQueueIsBounded() {
    let executor = WriteExecutor(store: MemoryJournalStore(), queueLimit: 1)
    let release = DispatchSemaphore(value: 0)
    let started = DispatchSemaphore(value: 0)
    Thread.detachNewThread { run(executor, play(key: "a")) { started.signal(); release.wait(); return routed() } }
    started.wait()
    Thread.detachNewThread { run(executor, play(key: "b")) { routed() } }  // takes the one waiting place
    Thread.sleep(forTimeInterval: 0.1)
    let calls = Counter()
    let overflow = run(executor, play(key: "c")) { calls.increment(); return routed() }
    #expect(error(overflow) == "queue_full")
    #expect(calls.count == 0)
    release.signal()
}

@Test func aWriteBasedOnAnOldConnectionIsRefusedWithoutSending() {
    var generation: Int? = 8
    let executor = WriteExecutor(store: MemoryJournalStore(), sessionProbe: { generation })
    let calls = Counter()

    let stale = run(executor, play(expect: 7)) { calls.increment(); return routed() }
    #expect(error(stale) == "precondition_failed")
    #expect(stale.execution["current_session"] == .number(8))

    generation = nil  // Logic not connected
    let disconnected = run(executor, play(expect: 8)) { calls.increment(); return routed() }
    #expect(error(disconnected) == "precondition_failed")
    #expect(calls.count == 0)

    generation = 8
    #expect(state(run(executor, play(expect: 8)) { calls.increment(); return routed() }) == .string("completed"))
}

@Test func aWriteInFlightWhenTheDaemonDiesIsUnknownAfterTheRestart() {
    let store = MemoryJournalStore()
    let release = DispatchSemaphore(value: 0)
    let started = DispatchSemaphore(value: 0)
    let first = WriteExecutor(store: store)
    Thread.detachNewThread { run(first, play(key: "k1")) { started.signal(); release.wait(); return routed() } }
    started.wait()

    let restarted = WriteExecutor(store: store)  // the old process never wrote a result
    let calls = Counter()
    let retry = run(restarted, play(key: "k1")) { calls.increment(); return routed() }
    #expect(error(retry) == "outcome_unknown")
    #expect(retry.execution["previous"]?["reason"] == .string("daemon_restarted"))
    #expect(calls.count == 0)
    release.signal()
}

@Test func shutdownMakesRunningWritesUnknownAndRefusesNewOnes() {
    let store = MemoryJournalStore()
    let executor = WriteExecutor(store: store)
    let release = DispatchSemaphore(value: 0)
    let started = DispatchSemaphore(value: 0)
    Thread.detachNewThread { run(executor, play(key: "k1")) { started.signal(); release.wait(); return routed(ok: false, verified: false, error: "verification_failed") } }
    started.wait()

    executor.shutdown()
    #expect(store.load().last { $0.key == "k1" }?.state == .unknown)
    #expect(store.load().last { $0.key == "k1" }?.reason == "daemon_stopped")
    #expect(error(run(executor, play(key: "k2")) { routed() }) == "shutting_down")
    release.signal()
}

@Test func keysBelongToWritesOnlyAndMustBeWellFormed() {
    let executor = WriteExecutor(store: MemoryJournalStore())
    let read = Request(command: "state", idempotencyKey: "k1")
    let refused = executor.execute(.state, request: read, options: ExecutionOptions(request: read)) { routed() }
    #expect(error(refused) == "invalid_argument")

    for bad in ["", "with space", "日本語", String(repeating: "a", count: 129)] {
        let result = run(executor, play(key: bad)) { routed() }
        #expect(error(result) == "invalid_argument", "key '\(bad)'")
    }
    // A read without a key is serialised but never journaled.
    let store = MemoryJournalStore()
    let plain = WriteExecutor(store: store)
    let plainRead = Request(command: "state")
    #expect(state(plain.execute(.state, request: plainRead, options: ExecutionOptions()) { routed() }) == .string("read"))
    #expect(store.load().isEmpty)
}

@Test func theJournalSurvivesInAFileAndAnUnfinishedEntryBecomesUnknown() throws {
    let path = NSTemporaryDirectory() + "logicctl-journal-\(UUID().uuidString).jsonl"
    defer { try? FileManager.default.removeItem(atPath: path) }

    let file = FileJournalStore(path: path)
    let done = WriteExecutor(store: file)
    run(done, play(key: "done")) { routed() }
    // An entry begun but never finished, as a crash would leave it.
    file.save(JournalEntry(key: "crashed", fingerprint: WriteExecutor.fingerprint(Request(command: "transport.play")),
                           command: "transport.play", state: .inFlight, startedAt: Date(), finishedAt: nil,
                           reason: nil, stored: nil))
    try "not json\n".data(using: .utf8)!.write(to: URL(fileURLWithPath: path + ".junk"))
    defer { try? FileManager.default.removeItem(atPath: path + ".junk") }

    let restarted = WriteExecutor(store: FileJournalStore(path: path))
    let calls = Counter()
    #expect(state(run(restarted, play(key: "done")) { calls.increment(); return routed() }) == .string("replayed"))
    #expect(error(run(restarted, play(key: "crashed")) { calls.increment(); return routed() }) == "outcome_unknown")
    #expect(calls.count == 0)
    // The recovery itself was written down.
    #expect(FileJournalStore(path: path).load().last { $0.key == "crashed" }?.state == .unknown)
}

@Test func fingerprintsIgnoreArgumentOrderAndTheDefaultRoute() {
    let a = Request(command: "track.volume", args: ["track": "1", "db": "-6"])
    let b = Request(command: "track.volume", args: ["db": "-6", "track": "1"], backend: "mcu")
    #expect(WriteExecutor.fingerprint(a) == WriteExecutor.fingerprint(b))
    #expect(WriteExecutor.fingerprint(a) != WriteExecutor.fingerprint(Request(command: "track.volume", args: ["track": "1", "db": "-3"])))
}

@Test func isWriteAgreesWithTheWireNames() {
    let commands: [LogicCommand] = [.status, .state, .transportPlay, .transportStop, .trackList, .trackGet(track: 1),
        .trackSelect(track: 1), .trackMute(track: 1, on: true), .trackSolo(track: 1, on: true),
        .trackVolume(track: 1, db: 0, tolerance: 0.1), .trackPan(track: 1, pan: 0), .daemonStop, .debugMCU(messages: [[0x90]])]
    for command in commands {
        #expect(command.isWrite == LogicCommand.isWrite(named: command.name), "\(command.name)")
    }
    #expect(commands.filter(\.isWrite).count == 8)
}

@Test func theNewRequestFieldsRoundTripAndOldRequestsStillDecode() throws {
    let request = Request(command: "transport.play", idempotencyKey: "k1", expectSession: 4, deadlineMs: 5000)
    let text = String(decoding: try JSONEncoder.logicctl.encode(request), as: UTF8.self)
    #expect(text.contains("\"idempotency_key\":\"k1\"") && text.contains("\"expect_session\":4") && text.contains("\"deadline_ms\":5000"))
    #expect(try JSONDecoder().decode(Request.self, from: Data(text.utf8)) == request)

    let old = #"{"id":"1","command":"status","args":{}}"#
    let decoded = try JSONDecoder().decode(Request.self, from: Data(old.utf8))
    #expect(decoded.idempotencyKey == nil && decoded.expectSession == nil && decoded.deadlineMs == nil)
}

@Test func theCLIParsesTheSafetyOptionsAndRefusesThemWhereTheyDoNotApply() throws {
    let r = try CLIParser.parse(["transport", "play", "--idempotency-key", "abc-1", "--expect-session", "4", "--deadline-ms", "2500"])
    #expect(r.idempotencyKey == "abc-1" && r.expectSession == 4 && r.deadlineMs == 2500)
    #expect(try CLIParser.parse(["track", "mute", "1", "on", "--expect-session", "3"]).expectSession == 3)

    #expect(throws: CommandError.self) { try CLIParser.parse(["status", "--idempotency-key", "k"]) }
    #expect(throws: CommandError.self) { try CLIParser.parse(["track", "list", "--idempotency-key", "k"]) }
    #expect(throws: CommandError.self) { try CLIParser.parse(["transport", "play", "--idempotency-key", "has space"]) }
    #expect(throws: CommandError.self) { try CLIParser.parse(["transport", "play", "--expect-session", "0"]) }
    #expect(throws: CommandError.self) { try CLIParser.parse(["transport", "play", "--deadline-ms", "abc"]) }
    #expect(throws: CommandError.self) { try CLIParser.parse(["daemon", "stop", "--deadline-ms", "100"]) }
}

private final class Box<T> {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}
#endif
