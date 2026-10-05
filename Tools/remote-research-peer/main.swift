import Foundation
#if !RESEARCH_PEER_OFFLINE_TEST
import AppKit
import MultipeerConnectivity
#endif

// Receive-only research peer for Logic Remote (PLAN-05, Research/plans/PLAN-05-approval-brief.md).
//
//   E0  browse for `apple-lgremote` and record what is advertised. Nothing is sent, nobody is invited.
//   E1  invite the advertising Logic under this peer's OWN name (never the name of a real Remote device).
//       A person presses "Connect" in Logic's dialog. When connected, send exactly two messages,
//       /protocolVersion = 10 and /jsonSupport = 1, and nothing else, ever.
//   E2  after both sends return without an error, receive for --seconds. Nothing is sent.
//
// Everything received is saved raw under --out (Research/raw/, not tracked by Git) and decoded with
// the product's RemoteFrameParser. This tool lives under Tools/ and is not part of the product.

// MARK: - Options

struct Options {
    enum Stage: String { case e0, e1 }
    var stage = Stage.e0
    var seconds = 60.0
    var peerName = "logicctl-research-peer"
    var deviceKind = 0          // Logic reads an integer 0...4 from the invitation context (SA-REMOTE-SESSION-001 §3.2)
    var target: String?
    var out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("remote-recv")

    init(_ arguments: [String]) {
        var index = 1
        func value() -> String { index += 1; return index < arguments.count ? arguments[index] : "" }
        while index < arguments.count {
            switch arguments[index] {
            case "--stage": stage = Stage(rawValue: value()) ?? .e0
            case "--seconds": seconds = min(max(Double(value()) ?? 60, 1), 120)
            case "--peer-name": peerName = value()
            case "--device-kind": deviceKind = min(max(Int(value()) ?? 0, 0), 4)
            case "--target": target = value()
            case "--out": out = URL(fileURLWithPath: value())
            default: break
            }
            index += 1
        }
    }
}

// MARK: - Recording

final class Recorder {
    let directory: URL
    private let events: FileHandle
    private let decoded: FileHandle
    private let started = DispatchTime.now()
    private(set) var frames = 0

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("frames"), withIntermediateDirectories: true)
        for name in ["events.jsonl", "decoded.jsonl"] {
            FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: nil)
        }
        events = try FileHandle(forWritingTo: directory.appendingPathComponent("events.jsonl"))
        decoded = try FileHandle(forWritingTo: directory.appendingPathComponent("decoded.jsonl"))
    }

    var elapsedMs: Double { Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1e6 }

    private func line(_ object: [String: Any], to handle: FileHandle) {
        dispatchPrecondition(condition: .onQueue(.main))
        var object = object
        object["t_ms"] = (elapsedMs * 10).rounded() / 10
        object["wall"] = ISO8601DateFormatter().string(from: Date())
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
            handle.write(data)
            handle.write(Data([0x0A]))
        }
    }

    func event(_ name: String, _ fields: [String: Any] = [:]) {
        dispatchPrecondition(condition: .onQueue(.main))
        var fields = fields
        fields["event"] = name
        line(fields, to: events)
        FileHandle.standardError.write(Data("[\(Int(elapsedMs)) ms] \(name) \(fields.filter { $0.key != "event" })\n".utf8))
    }

    /// Saves the raw frame and returns its number.
    func saveFrame(_ data: Data, peer: String) -> Int {
        dispatchPrecondition(condition: .onQueue(.main))
        frames += 1
        let name = String(format: "%04d.bin", frames)
        try? data.write(to: directory.appendingPathComponent("frames").appendingPathComponent(name))
        event("frame", ["n": frames, "bytes": data.count, "tag": data.first.map { Int($0) } ?? -1, "peer": peer])
        return frames
    }

    func decoded(_ fields: [String: Any]) { line(fields, to: decoded) }

    func writeSummary(_ summary: [String: Any]) {
        dispatchPrecondition(condition: .onQueue(.main))
        if let data = try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted]) {
            try? data.write(to: directory.appendingPathComponent("summary.json"))
        }
    }
}

// MARK: - Serial lifecycle (also executed by the offline fake-transport harness)

final class PeerLifecycle {
    static let initialMessages = [("/protocolVersion", 10), ("/jsonSupport", 1)]
    static let allowedAddresses = Set(initialMessages.map { $0.0 })
    private let queue: DispatchQueue
    private var finished = false
    private var sentAddresses: Set<String> = []

    init(queue: DispatchQueue = .main) { self.queue = queue }

    static func initialFrame(_ address: String, _ argument: Int) throws -> Data {
        precondition(allowedAddresses.contains(address), "refusing to send \(address)")
        let body = try PropertyListSerialization.data(fromPropertyList: [address: argument], format: .binary, options: 0)
        var frame = Data([0x01])
        frame.append(body)
        return frame
    }

    var sentInitial: Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        return sentAddresses == Self.allowedAddresses
    }

    /// Native callbacks may arrive on different queues. Their work and terminal-state check
    /// run together on this serial queue. A stopped certificate still needs its false reply.
    func route(onStopped: (() -> Void)? = nil, _ work: @escaping () -> Void) {
        queue.async { [self] in
            perform(onStopped: onStopped, work)
        }
    }

    func perform(onStopped: (() -> Void)? = nil, _ work: () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished else { onStopped?(); return }
        work()
    }

    /// Changes state before disconnecting or writing a summary, so queued callbacks cannot
    /// send or append records during the short interval before process exit.
    func finish(_ work: () -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished else { return }
        finished = true
        work()
    }

    /// Counts only sends that return without throwing. This does not imply a Logic ACK.
    /// The failure callback runs once, with the lifecycle already terminal.
    func sendInitial(send: (String, Int) throws -> Int,
                     didSend: (String, Int, Int) -> Void,
                     didFail: (String, Error) -> Void) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished, sentAddresses.isEmpty else { return false }
        for (address, argument) in Self.initialMessages {
            guard !finished else { return false }
            do {
                let bytes = try send(address, argument)
                sentAddresses.insert(address)
                didSend(address, argument, bytes)
            } catch {
                finish { didFail(address, error) }
                return false
            }
        }
        return !finished && sentInitial
    }
}

// MARK: - Decoding for the log

func json(_ value: RemoteValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let flag): return flag
    case .int(let number): return number
    case .double(let number): return number
    case .string(let text): return text
    case .data(let data): return ["data_length": data.count, "data_head_hex": data.prefix(24).map { String(format: "%02x", $0) }.joined()]
    case .url(let text): return ["url": text]
    case .indexPath(let path): return ["indexPath": path]
    case .array(let items): return items.map(json)
    case .dictionary(let entries): return entries.map { ["k": json($0.key), "v": json($0.value)] }
    }
}

// MARK: - The peer

#if !RESEARCH_PEER_OFFLINE_TEST
final class ResearchPeer: NSObject, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    let options: Options
    let recorder: Recorder
    let myID: MCPeerID
    let session: MCSession
    let browser: MCNearbyServiceBrowser
    private let lifecycle = PeerLifecycle()
    private var found: [MCPeerID: [String: String]] = [:]
    private var invited = false
    private var connectedPeer: MCPeerID?
    private var stopTimer: Timer?

    init(options: Options, recorder: Recorder) {
        self.options = options
        self.recorder = recorder
        myID = MCPeerID(displayName: options.peerName)
        // Logic itself creates its session with encryption preference 2 (none): SA-REMOTE-SESSION-001 §3.1.
        session = MCSession(peer: myID, securityIdentity: nil, encryptionPreference: .none)
        browser = MCNearbyServiceBrowser(peer: myID, serviceType: "apple-lgremote")
        super.init()
        session.delegate = self
        browser.delegate = self
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        lifecycle.perform { startActive() }
    }

    private func startActive() {
        recorder.event("start", [
            "stage": options.stage.rawValue, "seconds": options.seconds, "peer_name": options.peerName,
            "device_kind": options.deviceKind, "target": options.target ?? NSNull(),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ])
        browser.startBrowsingForPeers()
        recorder.event("browsing")
        // E0 browses for the whole window; E1 gives up if Logic is not seen quickly.
        let browseLimit = options.stage == .e0 ? options.seconds : 30
        after(browseLimit) { [self] in
            if options.stage == .e0 { finish("browse_window_over", found.isEmpty ? 3 : 0) }
            else if !invited { finish("no_peer_found", 3) }
        }
        // `touch <out>/STOP` ends the run early (the person's signal).
        stopTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            lifecycle.perform {
                if FileManager.default.fileExists(atPath: recorder.directory.appendingPathComponent("STOP").path) {
                    finish("stop_file", 0)
                }
            }
        }
    }

    func after(_ seconds: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in lifecycle.perform(work) }
    }

    func finish(_ reason: String, _ code: Int32) {
        lifecycle.finish { endRun(reason, code) }
    }

    /// Called only by lifecycle.finish, including the terminal initial-send failure path.
    private func endRun(_ reason: String, _ code: Int32) {
        dispatchPrecondition(condition: .onQueue(.main))
        recorder.event("finish", ["reason": reason, "frames": recorder.frames, "connected": connectedPeer != nil])
        stopTimer?.invalidate()
        stopTimer = nil
        browser.stopBrowsingForPeers()
        session.disconnect()
        recorder.writeSummary([
            "stage": options.stage.rawValue, "reason": reason, "exit_code": Int(code), "frames": recorder.frames,
            "found": found.map { ["name": $0.key.displayName, "discoveryInfo": $0.value] },
            "invited": invited, "connected": connectedPeer != nil, "sent_initial": lifecycle.sentInitial,
        ])
        // Give the disconnect a moment to leave the machine.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exit(code) }
    }

    // MARK: Browser

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        lifecycle.route { [self] in foundPeer(browser, peerID, info) }
    }

    private func foundPeer(_ browser: MCNearbyServiceBrowser, _ peerID: MCPeerID, _ info: [String: String]?) {
        found[peerID] = info ?? [:]
        recorder.event("found_peer", ["name": peerID.displayName, "discoveryInfo": info ?? [:]])
        guard options.stage == .e1, !invited else { return }
        if let target = options.target, target != peerID.displayName { return }
        invited = true
        // Context: the device kind as a binary property list holding an integer, as the client code does (SESSION §3.3).
        let context = try? PropertyListSerialization.data(fromPropertyList: options.deviceKind, format: .binary, options: 0)
        recorder.event("invite", ["to": peerID.displayName, "context_bytes": context?.count ?? 0, "timeout_s": 30])
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 30)
        // The invitation times out after 30 s; the dialog is answered by a person.
        after(45) { [self] in if connectedPeer == nil { finish("not_connected", 4) } }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        lifecycle.route { [self] in recorder.event("lost_peer", ["name": peerID.displayName]) }
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        lifecycle.route { [self] in
            recorder.event("browse_failed", ["error": "\(error)"])
            finish("browse_failed", 2)
        }
    }

    // MARK: Session

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        lifecycle.route { [self] in changedState(peerID, state) }
    }

    private func changedState(_ peerID: MCPeerID, _ state: MCSessionState) {
        let name = ["not_connected", "connecting", "connected"][min(max(state.rawValue, 0), 2)]
        recorder.event("state", ["peer": peerID.displayName, "state": name])
        switch state {
        case .connected:
            guard options.stage == .e1 else { finish("unexpected_connection", 2); return }
            guard connectedPeer == nil else { return }
            connectedPeer = peerID
            // E1: the two allowed messages, at once (Logic waits up to ~2.5 s for the version).
            guard lifecycle.sendInitial(
                send: { [self] address, argument in try send(address, argument, to: peerID) },
                didSend: { [self] address, argument, bytes in
                    recorder.event("sent", ["address": address, "argument": argument, "bytes": bytes])
                },
                didFail: { [self] address, error in
                    recorder.event("send_failed", ["address": address, "error": "\(error)"])
                    endRun("initial_send_failed", 2)
                }
            ) else { return }
            // E2: receive only.
            recorder.event("receive_window", ["seconds": options.seconds])
            after(options.seconds) { [self] in finish("receive_window_over", 0) }
        case .notConnected:
            if connectedPeer == peerID { finish("disconnected_by_peer", 0) }
        default: break
        }
    }

    /// The single place that sends. Frame = tag 1 (property list) + a binary property list {address: argument}.
    /// Only the two allowed addresses, each at most once, and only in E1.
    private func send(_ address: String, _ argument: Int, to peerID: MCPeerID) throws -> Int {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(options.stage == .e1 && PeerLifecycle.allowedAddresses.contains(address),
                     "refusing to send \(address)")
        let frame = try PeerLifecycle.initialFrame(address, argument)
        try session.send(frame, toPeers: [peerID], with: .reliable)
        return frame.count
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        lifecycle.route { [self] in received(data, peerID) }
    }

    private func received(_ data: Data, _ peerID: MCPeerID) {
        let number = recorder.saveFrame(data, peer: peerID.displayName)
        switch RemoteFrameParser.decode(data) {
        case .success(let frame):
            let groups = frame.groups.map { group in group.map { ["address": $0.address, "argument": json($0.argument)] as [String: Any] } }
            recorder.decoded([
                "n": number, "bytes": data.count, "ok": true,
                "format": "\(frame.format)", "container": "\(frame.container)", "ordered": frame.ordered, "groups": groups,
            ])
            recorder.event("decoded", ["n": number, "addresses": frame.messages.map(\.address)])
        case .failure(let error):
            recorder.decoded(["n": number, "bytes": data.count, "ok": false, "error": "\(error)",
                              "head_hex": data.prefix(64).map { String(format: "%02x", $0) }.joined()])
            recorder.event("decode_failed", ["n": number, "error": "\(error)"])
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        lifecycle.route { [self] in recorder.event("stream_received_and_ignored", ["name": streamName]) }
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        lifecycle.route { [self] in recorder.event("resource_started_and_ignored", ["name": resourceName]) }
    }

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        lifecycle.route { [self] in recorder.event("resource_finished", ["name": resourceName, "error": error.map { "\($0)" } ?? NSNull()]) }
    }

    func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
        lifecycle.route(onStopped: { certificateHandler(false) }) { [self] in
            recorder.event("certificate", ["count": certificate?.count ?? 0])
            certificateHandler(true)
        }
    }
}

// MARK: - Main

let options = Options(CommandLine.arguments)
do {
    let recorder = try Recorder(directory: options.out)
    let peer = ResearchPeer(options: options, recorder: recorder)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    signal(SIGTERM, SIG_IGN)
    let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    term.setEventHandler { peer.finish("sigterm", 0) }
    term.resume()
    DispatchQueue.main.async { peer.start() }
    app.run()
} catch {
    FileHandle.standardError.write(Data("cannot start: \(error)\n".utf8))
    exit(2)
}
#else
// Compiled only for an offline harness: no native peer, browsing, invitations, or app loop.
runPeerOfflineTests()
#endif
