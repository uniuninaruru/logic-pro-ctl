import Foundation

private enum HarnessError: Error { case sendFailed, expectation(String) }
private func expect(_ condition: @autoclosure () -> Bool, _ text: String) throws {
    if !condition() { throw HarnessError.expectation(text) }
}

// Exercises the actual PeerLifecycle and initialFrame from main.swift. FakePeer supplies
// callback sequences and substitutes transport/recording effects. The native ResearchPeer,
// Recorder, timers, runner and MultipeerConnectivity callbacks are not exercised.
private final class FakePeer {
    let queue = DispatchQueue(label: "offline-peer-serial")
    lazy var lifecycle = PeerLifecycle(queue: queue)
    var records: [String] = []
    var attempts: [String] = []
    var frames: [Data] = []
    var certificates: [Bool] = []
    var connected = false
    var failedAttempt: Int?
    var stopAfterFirstSuccess = false
    var summarySentInitial: Bool?
    var summaryRecordCount: Int?

    func end(_ reason: String) {
        records.append("finish:" + reason)
        summarySentInitial = lifecycle.sentInitial
        summaryRecordCount = records.count
    }
    func stop() { lifecycle.route { self.lifecycle.finish { self.end("stop") } } }
    func connect() {
        lifecycle.route {
            guard !self.connected else { return }
            self.connected = true
            self.records.append("connected")
            let success = self.lifecycle.sendInitial(
                send: { address, argument in
                    self.attempts.append(address)
                    if self.attempts.count == self.failedAttempt { throw HarnessError.sendFailed }
                    let frame = try PeerLifecycle.initialFrame(address, argument)
                    self.frames.append(frame)
                    return frame.count
                },
                didSend: { address, _, _ in
                    self.records.append("sent:" + address)
                    if self.stopAfterFirstSuccess {
                        self.lifecycle.finish { self.end("stop_during_send") }
                    }
                },
                didFail: { address, _ in
                    self.records.append("send_failed:" + address)
                    self.end("initial_send_failed")
                }
            )
            if success { self.records.append("receive_window") }
        }
    }
    func receive() { lifecycle.route { self.records.append("frame") } }
    func otherCallback(_ name: String) { lifecycle.route { self.records.append(name) } }
    func certificate() {
        lifecycle.route(onStopped: { self.certificates.append(false) }) {
            self.records.append("certificate")
            self.certificates.append(true)
        }
    }
    func drained<T>(_ body: () throws -> T) rethrows -> T { try queue.sync(execute: body) }
}

func runPeerOfflineTests() {
    var passed: [String] = []
    func test(_ name: String, _ body: () throws -> Void) throws { try body(); passed.append(name) }
    do {
        try test("both_sends_then_window_and_exact_frames") {
            let peer = FakePeer()
            peer.connect(); peer.certificate(); peer.receive()
            try peer.drained {
                try expect(peer.records == ["connected", "sent:/protocolVersion", "sent:/jsonSupport", "receive_window", "certificate", "frame"], "normal order")
                try expect(peer.lifecycle.sentInitial, "both successful sends")
                try expect(peer.certificates == [true], "active certificate accepted exactly once")
                try expect(peer.frames.count == 2, "exactly two frames")
                for (frame, message) in zip(peer.frames, PeerLifecycle.initialMessages) {
                    try expect(frame.first == 1, "property-list tag")
                    let plist = try PropertyListSerialization.propertyList(from: frame.dropFirst(), format: nil) as? [String: Int]
                    try expect(plist == [message.0: message.1], "exact address and argument; no editing frame")
                }
            }
        }
        try test("stop_before_queued_callbacks_and_certificate_false") {
            let peer = FakePeer()
            peer.stop(); peer.connect(); peer.receive()
            for name in ["found", "lost", "browse_failed", "state", "stream", "resource_start", "resource_finish"] { peer.otherCallback(name) }
            peer.certificate(); peer.stop()
            try peer.drained {
                try expect(peer.records == ["finish:stop"], "nothing appended after finish")
                try expect(peer.attempts.isEmpty && peer.frames.isEmpty, "no initial send after stop")
                try expect(peer.certificates == [false], "stopped certificate handler invoked once with false")
                try expect(peer.summaryRecordCount == peer.records.count, "summary still matches final record count")
            }
        }
        try test("first_send_failure_is_terminal") {
            let peer = FakePeer(); peer.failedAttempt = 1
            peer.connect(); peer.receive(); peer.connect(); peer.certificate(); peer.stop()
            try peer.drained {
                try expect(peer.attempts == ["/protocolVersion"], "second send never attempted")
                try expect(peer.frames.isEmpty && peer.summarySentInitial == false, "no success counted on throw")
                try expect(peer.records == ["connected", "send_failed:/protocolVersion", "finish:initial_send_failed"], "failure stops recording and window")
                try expect(peer.certificates == [false], "failure certificate rejected")
            }
        }
        try test("second_send_failure_does_not_mark_initial_complete") {
            let peer = FakePeer(); peer.failedAttempt = 2
            peer.connect(); peer.receive(); peer.connect(); peer.stop()
            try peer.drained {
                try expect(peer.attempts == ["/protocolVersion", "/jsonSupport"], "both attempted once")
                try expect(peer.frames.count == 1, "one nonthrow send")
                try expect(peer.summarySentInitial == false && !peer.lifecycle.sentInitial, "failed second send must not be counted")
                try expect(peer.records == ["connected", "sent:/protocolVersion", "send_failed:/jsonSupport", "finish:initial_send_failed"], "no second sent event, no receive window, no late frames")
            }
        }
        try test("stop_inside_first_send_completion_prevents_second_and_window") {
            let peer = FakePeer(); peer.stopAfterFirstSuccess = true
            peer.connect(); peer.receive()
            try peer.drained {
                try expect(peer.attempts == ["/protocolVersion"], "no second send after completion requested stop")
                try expect(peer.summarySentInitial == false, "partial initial summary")
                try expect(peer.records == ["connected", "sent:/protocolVersion", "finish:stop_during_send"], "no window or receive after completion stop")
            }
        }
        try test("duplicate_connection_does_not_resend") {
            let peer = FakePeer()
            peer.connect(); peer.connect(); peer.connect()
            try peer.drained {
                try expect(peer.attempts.count == 2 && peer.records.filter { $0 == "receive_window" }.count == 1, "no resend or duplicate window")
                let result = peer.lifecycle.sendInitial(send: { _, _ in throw HarnessError.expectation("duplicate send called") }, didSend: { _, _, _ in }, didFail: { _, _ in })
                try expect(!result, "lifecycle itself rejects a repeated initial sequence")
            }
        }
        try test("concurrent_callbacks_are_serial_and_summary_terminal") {
            let peer = FakePeer()
            // Initialize the lazy core on its owning queue before concurrent callers use it.
            peer.drained { _ = peer.lifecycle }
            DispatchQueue.concurrentPerform(iterations: 200) { _ in peer.receive() }
            peer.stop()
            DispatchQueue.concurrentPerform(iterations: 200) { _ in peer.receive(); peer.otherCallback("late") }
            try peer.drained {
                try expect(peer.records.count == 201 && peer.records.last == "finish:stop", "200 frames + one finish, no late records")
                try expect(peer.summaryRecordCount == 201, "stable terminal count")
            }
        }
        try test("finish_routes_once_even_when_queued_from_many_threads") {
            let peer = FakePeer()
            peer.drained { _ = peer.lifecycle }
            DispatchQueue.concurrentPerform(iterations: 100) { _ in peer.stop() }
            try peer.drained { try expect(peer.records == ["finish:stop"], "one terminal write") }
        }
        let result: [String: Any] = ["passed": passed.count, "tests": passed, "native_peer_created": false, "browsing_started": false, "messages_sent_to_logic": 0]
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    } catch {
        FileHandle.standardError.write(Data("FAILED after \(passed.count) tests: \(error)\n".utf8))
        exit(1)
    }
}
