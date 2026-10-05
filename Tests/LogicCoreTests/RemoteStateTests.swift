import Compression
import Foundation
@testable import LogicCore

// The Remote state builder (RemoteState.swift) against the contract of EXP-REMOTE-002.
// Every message here is SYNTHETIC; the contract was checked once against a real reception (EXP-REMOTE-001).
#if canImport(Testing)
import Testing

// MARK: - Builders for synthetic messages

private func dict(_ pairs: [(String, RemoteValue)]) -> RemoteValue {
    .dictionary(pairs.map { RemoteEntry(key: .string($0.0), value: $0.1) })
}

private func ati(_ names: [String], gindex: [Int]? = nil, trackID: [Int]? = nil, uuid: [String]? = nil) -> RemoteValue {
    let n = names.count
    let g = gindex ?? (0..<n).map { 100 + $0 }
    let t = trackID ?? (0..<n).map { (4 << 16) | ($0 + 1) }
    let u = uuid ?? g.map { "U-\($0)" }
    let colour = RemoteValue.data(Data([0x36, 0x6E, 0xAA, 0xFF]))
    func ints(_ values: [Int]) -> RemoteValue { .array(values.map { .int($0) }) }
    return dict([
        ("c", .array((0..<n).map { _ in dict([("nc", colour), ("sc", colour), ("tnc", colour), ("tsc", colour)]) })),
        ("n", .array((0..<n).map { dict([("name", .string(names[$0])), ("gindex", .int(g[$0]))]) })),
        ("t", ints(Array(repeating: 1, count: n))), ("nc", ints(Array(repeating: 1, count: n))),
        ("p", ints(Array(repeating: 0, count: n))), ("tn", ints((1...max(n, 1)).prefix(n).map { $0 })),
        ("BgTrackInfoTrackIDKey", ints(t)), ("BgTrackInfoTrackUUIDKey", .array(u.map { .string($0) })),
        ("BgTrackInfoIconIDKey", ints(Array(repeating: 0, count: n))),
        ("BgTrackInfoHasArrangeKey", .array(Array(repeating: .bool(true), count: n))),
        ("BgTrackInfoArrangeHiddenKey", .array(Array(repeating: .bool(false), count: n))),
        ("BgTrackInfoCollapsibleInfoKey", ints(Array(repeating: 0, count: n))),
        ("BgTrackInfoMetaInfoFlagsKey", ints(Array(repeating: 0, count: n))),
    ])
}

private func fader(g: [Int: [String: Int]] = [:], t: [Int: [String: Int]] = [:]) -> RemoteValue {
    func side(_ entries: [Int: [String: Int]]) -> RemoteValue {
        .dictionary(entries.sorted { $0.key < $1.key }.map { key, fields in
            RemoteEntry(key: .int(key), value: dict(fields.sorted { $0.key < $1.key }.map { ($0.key, .int($0.value)) }))
        })
    }
    var pairs: [(String, RemoteValue)] = []
    if !g.isEmpty { pairs.append(("g", side(g))) }
    if !t.isEmpty { pairs.append(("t", side(t))) }
    return dict(pairs)
}

private func sti(_ name: String, index: Int, tn: Int) -> RemoteValue {
    dict([("n", .string(name)), ("t", .int(1)), ("BgTrackInfoMetaInfoFlagsKey", .int(0)), ("tn", .int(tn)),
          ("BgTrackInfoIndexKey", .int(index))])
}

private func message(_ address: String, _ argument: RemoteValue) -> RemoteMessage { RemoteMessage(address: address, argument: argument) }

private func strip(_ snapshot: RemoteStateSnapshot, _ gindex: Int) -> RemoteStrip? { snapshot.strips.first { $0.gindex == gindex } }

private func kinds(_ builder: RemoteStateBuilder) -> [RemoteStateEvent.Kind] { builder.events.map(\.kind) }

/// zlib stream (header, raw deflate, Adler-32) inside a MAZP container, as Logic writes it.
private func mazp(_ body: Data) -> Data {
    var raw = Data(count: body.count + 1024)
    let written = raw.withUnsafeMutableBytes { dst in
        body.withUnsafeBytes { src in
            compression_encode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, body.count + 1024,
                                      src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB)
        }
    }
    raw.removeLast(raw.count - written)
    let adler = RemoteFrameParser.adler32(body)
    var out = Data("MAZP".utf8) + Data([0, 10]) + Data([UInt8(body.count >> 24 & 0xFF), UInt8(body.count >> 16 & 0xFF),
                                                       UInt8(body.count >> 8 & 0xFF), UInt8(body.count & 0xFF)])
    out += Data([0x78, 0x9C]) + raw
    out += Data([UInt8(adler >> 24 & 0xFF), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)])
    return out
}

private func archive(_ object: Any) throws -> Data {
    try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false)
}

// MARK: - 1. Unknown is nil, not 0

@Test func anAbsentFieldIsNilAndAReceivedZeroIsZero() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A", "B"])))
    b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 0x5A00_0000]])))
    b.apply(frame: 3, message("/gtFaderData", fader(g: [100: ["s": 0]])))
    let snap = b.snapshot()
    #expect(strip(snap, 100)?.fader.vL?.value == 0x5A00_0000)
    #expect(strip(snap, 100)?.fader.s == RemoteKnown(0, frame: 3))
    #expect(strip(snap, 100)?.fader.m == nil)          // never sent: nil, not 0
    #expect(strip(snap, 101)?.fader == RemoteFaderValues())
    #expect(strip(snap, 101)?.track == RemoteTrackValues())
}

@Test func aPartialDeltaKeepsTheFieldsItDoesNotCarryAndAnEqualValueKeepsItsFirstFrame() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A"])))
    b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 1, "s": 0, "m": 0]])))
    b.apply(frame: 3, message("/gtFaderData", fader(g: [100: ["m": 0]])))
    b.apply(frame: 4, message("/gtFaderData", fader(g: [100: ["m": 1]])))
    let values = strip(b.snapshot(), 100)!.fader
    #expect(values.vL?.value == 1 && values.s?.value == 0)
    #expect(values.m == RemoteKnown(1, frame: 4))
    #expect(b.events.contains { $0.frame == 3 && $0.detail == "changed 0 unchanged 1" })
}

// MARK: - 3. /ati is a whole snapshot; broken ones are refused

@Test func aBrokenATIIsRefusedAndThePreviousStateKept() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A", "B"])))
    guard case .dictionary(var entries) = ati(["A", "B", "C"]) else { Issue.record("not a dictionary"); return }
    entries = entries.map { $0.key == .string("tn") ? RemoteEntry(key: $0.key, value: .array([.int(1), .int(2)])) : $0 }
    b.apply(frame: 2, message("/ati", .dictionary(entries)))
    #expect(b.issues.last?.kind == .atiRejected)
    #expect(b.snapshot().strips.map(\.name) == ["A", "B"])
    #expect(b.snapshot().atiFrame == 1)
}

@Test func aRepeatedIdentifierInsideOneATIIsRefused() {
    for broken in [ati(["A", "B"], gindex: [7, 7]), ati(["A", "B"], trackID: [5, 5]), ati(["A", "B"], uuid: ["X", "X"])] {
        var b = RemoteStateBuilder()
        b.apply(frame: 1, message("/ati", broken))
        #expect(b.issues.first?.kind == .atiRejected)
        #expect(b.issues.first?.detail.hasPrefix("repeated") == true)
        #expect(b.snapshot().strips.isEmpty)
    }
}

@Test func aValueOfTheWrongTypeInATIIsRefused() {
    guard case .dictionary(var entries) = ati(["A"]) else { return }
    entries = entries.map { $0.key == .string("BgTrackInfoHasArrangeKey") ? RemoteEntry(key: $0.key, value: .array([.int(1)])) : $0 }
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", .dictionary(entries)))
    #expect(b.issues.first?.kind == .atiRejected)
}

@Test func anIdenticalATIIsADuplicateNotAChange() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A"])))
    b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 9]])))
    b.apply(frame: 3, message("/ati", ati(["A"])))
    #expect(kinds(b).last == .atiDuplicate)
    #expect(strip(b.snapshot(), 100)?.fader.vL?.value == 9)
    #expect(b.snapshot().atiFrame == 1)
}

// MARK: - 2 and 4. Identifiers stay apart

@Test func stripValuesFollowGindexThroughAReorderButTrackValuesDoNotFollowAMovedTrackID() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A", "B"], gindex: [100, 104])))
    b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 1], 104: ["vL": 2]], t: [0x40001: ["r": 64]])))
    // Reorder: positions swap; track IDs follow position (as in EXP-REMOTE-001), so 0x40001 now belongs to B.
    b.apply(frame: 3, message("/ati", ati(["B", "A"], gindex: [104, 100], uuid: ["U-104", "U-100"])))
    let snap = b.snapshot()
    #expect(snap.strips.map(\.name) == ["B", "A"])
    #expect(snap.strips.map { $0.fader.vL?.value } == [2, 1])
    #expect(snap.strips.map(\.position) == [1, 2])
    #expect(snap.strips[0].track.r == nil)          // A's r=64 is not handed to B
    #expect(kinds(b).contains(.stripMoved))
}

@Test func aNewUUIDUnderTheSameGindexIsAnotherStrip() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A"])))
    b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 1, "s": 0, "m": 0]])))
    b.apply(frame: 3, message("/ati", ati(["A2"], uuid: ["OTHER"])))
    #expect(b.issues.contains { $0.kind == .identityChanged })
    #expect(strip(b.snapshot(), 100)?.fader == RemoteFaderValues())
}

@Test func aStripThatLeavesAndReturnsStartsUnknown() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A", "B"])))
    b.apply(frame: 2, message("/gtFaderData", fader(g: [101: ["vL": 3]], t: [0x40002: ["r": 64]])))
    b.apply(frame: 3, message("/ati", ati(["A"])))
    b.apply(frame: 4, message("/ati", ati(["A", "B"])))
    #expect(kinds(b).contains(.stripRemoved))
    #expect(strip(b.snapshot(), 101)?.fader == RemoteFaderValues())
    #expect(strip(b.snapshot(), 101)?.track == RemoteTrackValues())
}

// MARK: - 5. Orphans

@Test func faderDataForAnUnknownIdentifierIsHeldAndAttachedLater() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/gtFaderData", fader(g: [100: ["m": 0]], t: [0x40001: ["ip": 0]])))
    #expect(Set(b.issues.map(\.kind)) == [.orphanGindex, .orphanTrackID])
    #expect(b.snapshot().orphanGindex == [100])
    b.apply(frame: 2, message("/ati", ati(["A"])))
    let snap = b.snapshot()
    #expect(strip(snap, 100)?.fader.m?.value == 0)
    #expect(strip(snap, 100)?.track.ip?.value == 0)
    #expect(snap.orphanGindex.isEmpty && snap.orphanTrackID.isEmpty)
}

@Test func aFaderMessageWithAnUnknownFieldOrANonIntegerChangesNothing() {
    for bad in [dict([("g", .dictionary([RemoteEntry(key: .int(100), value: dict([("volume", .int(3))]))]))]),
                dict([("g", .dictionary([RemoteEntry(key: .int(100), value: dict([("vL", .string("loud"))]))]))]),
                dict([("x", .int(1))])] {
        var b = RemoteStateBuilder()
        b.apply(frame: 1, message("/ati", ati(["A"])))
        b.apply(frame: 2, message("/gtFaderData", bad))
        #expect(b.issues.last?.kind == .faderRejected)
        #expect(strip(b.snapshot(), 100)?.fader == RemoteFaderValues())
    }
}

// MARK: - The same content through different encodings

@Test func jsonStringKeysAndArchiveNumberKeysGiveTheSameState() throws {
    let json = Data(#"{"/gtFaderData": {"g": {"100": {"vL": 7, "s": 0}}, "t": {"262145": {"r": 64}}}}"#.utf8)
    let archived = try archive(["/gtFaderData": ["g": [NSNumber(value: 100): ["vL": 7, "s": 0]],
                                                 "t": [NSNumber(value: 262145): ["r": 64]]]] as NSDictionary)
    var states: [RemoteStateSnapshot] = []
    for frameData in [Data([0x04]) + json, Data([0x82]) + mazp(archived)] {
        guard case .success(let frame) = RemoteFrameParser.decode(frameData) else { Issue.record("decode failed"); return }
        var b = RemoteStateBuilder()
        b.apply(frame: 1, message("/ati", ati(["A"])))
        b.apply(frame: 2, frame)
        #expect(b.issues.isEmpty)
        states.append(b.snapshot())
    }
    #expect(states[0] == states[1])
    #expect(strip(states[0], 100)?.fader.vL?.value == 7)
    #expect(strip(states[0], 100)?.track.r?.value == 64)
}

@Test func anSTIInsideACompressedArchiveEqualsThePlainDictionary() throws {
    let archived = try archive(["n": "B", "t": 1, "BgTrackInfoMetaInfoFlagsKey": 0, "tn": 2, "BgTrackInfoIndexKey": 1] as NSDictionary)
    var plain = RemoteStateBuilder(), packed = RemoteStateBuilder(), bare = RemoteStateBuilder()
    plain.apply(frame: 1, message("/ati", ati(["A", "B"])))
    packed.apply(frame: 1, message("/ati", ati(["A", "B"])))
    bare.apply(frame: 1, message("/ati", ati(["A", "B"])))
    plain.apply(frame: 2, message("/sti", sti("B", index: 1, tn: 2)))
    packed.apply(frame: 2, message("/sti", .data(mazp(archived))))
    bare.apply(frame: 2, message("/sti", .data(archived)))
    #expect(plain.snapshot().selection?.gindex == 101)
    #expect(packed.snapshot().selection == plain.snapshot().selection)
    #expect(bare.snapshot().selection == plain.snapshot().selection)
    #expect(packed.issues.isEmpty && bare.issues.isEmpty)
}

// MARK: - 6. Selection

@Test func anSTIThatArrivesBeforeTheFirstATIIsResolvedLater() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/sti", sti("B", index: 1, tn: 2)))
    #expect(b.snapshot().selection?.gindex == nil)
    b.apply(frame: 2, message("/ati", ati(["A", "B"])))
    #expect(b.snapshot().selection?.gindex == 101)
    #expect(b.snapshot().selection?.position == 2)
    #expect(b.issues.isEmpty)
}

@Test func aReorderAfterTheSTILeavesAStaleSelectionUnresolved() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A", "B"])))
    b.apply(frame: 2, message("/sti", sti("B", index: 1, tn: 2)))
    b.apply(frame: 3, message("/ati", ati(["B", "A"], gindex: [101, 100], uuid: ["U-101", "U-100"])))
    #expect(b.issues.last?.kind == .selectionMismatch)
    #expect(b.snapshot().selection?.gindex == nil)
}

@Test func noTrackSelectedIsNoSelectionNotUnknown() {
    var b = RemoteStateBuilder()
    #expect(b.snapshot().selection == nil)
    b.apply(frame: 1, message("/sti", dict([("n", .string("NoTrackSelected")), ("t", .int(0)), ("tn", .int(0)),
                                             ("BgTrackInfoMetaInfoFlagsKey", .int(0)), ("BgTrackInfoIndexKey", .int(Int.max))])))
    #expect(b.snapshot().selection?.selected == false)
}

@Test func aRepeatedSTIIsADuplicate() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A"])))
    b.apply(frame: 2, message("/sti", sti("A", index: 0, tn: 1)))
    b.apply(frame: 3, message("/sti", sti("A", index: 0, tn: 1)))
    #expect(kinds(b).last == .stiDuplicate)
}

// MARK: - Counts, completeness, order

@Test func aCountThatDisagreesWithATIIsReported() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A", "B"])))
    b.apply(frame: 2, message("/allTrackCount", .int(3)))
    #expect(b.issues.last?.kind == .countMismatch)
    var early = RemoteStateBuilder()
    early.apply(frame: 1, message("/allTrackCount", .int(2)))
    early.apply(frame: 2, message("/ati", ati(["A", "B"])))
    #expect(early.issues.isEmpty)
}

@Test func completeIsNeverTrueEvenWhenEveryFieldIsKnown() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A"])))
    b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 1, "s": 0, "m": 0]], t: [0x40001: ["r": 0, "ip": 0]])))
    b.apply(frame: 3, message("/sti", sti("A", index: 0, tn: 1)))
    let snap = b.snapshot()
    #expect(snap.knownFaderFields == 3 && snap.knownTrackFields == 2)
    #expect(snap.complete == nil)
}

@Test func atiIsAppliedFirstWithinOneGroup() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, group: [message("/gtFaderData", fader(g: [100: ["vL": 7]])), message("/ati", ati(["A"]))])
    #expect(b.issues.isEmpty)
    #expect(strip(b.snapshot(), 100)?.fader.vL?.value == 7)
}

@Test func addressesOutsideTheStateAreIgnored() {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/mixerLevels", .array([.int(0)])))
    #expect(b.events.isEmpty && b.snapshot().lastFrame == nil)
}
#endif

#if canImport(Testing)
// MARK: - The real reception, when it is on this machine (Research/raw is not tracked by Git)

private let capturedFrames: URL? = {
    let raw = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Research/raw/remote-recv")
    let captures = (try? FileManager.default.contentsOfDirectory(at: raw, includingPropertiesForKeys: nil)) ?? []
    return captures.filter { $0.lastPathComponent.hasSuffix("-e1") }.sorted { $0.path < $1.path }.last?.appendingPathComponent("frames")
}()

@Test(.enabled(if: capturedFrames != nil, "no capture under Research/raw/remote-recv/"))
func theRealReceptionRebuildsLikeTheResearchTool() throws {
    let files = try FileManager.default.contentsOfDirectory(at: capturedFrames!, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "bin" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    var b = RemoteStateBuilder()
    for file in files {
        guard case .success(let frame) = RemoteFrameParser.decode(try Data(contentsOf: file)) else { Issue.record("\(file.lastPathComponent)"); continue }
        b.apply(frame: Int(file.deletingPathExtension().lastPathComponent)!, frame)
    }
    let snap = b.snapshot()
    // The same numbers as Tools/research-scripts/remote_state.py (EXP-REMOTE-002).
    #expect(b.issues.isEmpty)
    #expect(snap.strips.count == 12)
    #expect(snap.knownFaderFields == 36 && snap.knownTrackFields == 24)
    #expect(snap.complete == nil)
    #expect(snap.selection?.position == 3)
    #expect(b.events.filter { $0.kind == .atiDuplicate }.count == 1)
}
#endif
