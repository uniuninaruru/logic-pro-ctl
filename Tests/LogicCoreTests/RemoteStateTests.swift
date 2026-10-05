import Compression
import Foundation
@testable import LogicCore

// The Remote state builder (RemoteState.swift) against the contract of EXP-REMOTE-002.
// Every message here is SYNTHETIC; the contract was checked once against a real reception (EXP-REMOTE-001).
// The optional real-data regression uses only EXP-REMOTE-001's reference recording, 20261005-094234-e1.
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

private func replacing(_ dictionary: RemoteValue, _ key: String, with value: RemoteValue?) -> RemoteValue {
    guard case .dictionary(var entries) = dictionary else { preconditionFailure("fixture is not a dictionary") }
    entries.removeAll { $0.key == .string(key) }
    if let value { entries.append(RemoteEntry(key: .string(key), value: value)) }
    return .dictionary(entries)
}

/// Fixture encoding only. Plists use decimal strings for the number keys; archive-key parity is tested separately.
private func fixtureObject(_ value: RemoteValue) throws -> Any {
    switch value {
    case .bool(let v): return v
    case .int(let v): return v
    case .double(let v): return v
    case .string(let v): return v
    case .data(let v): return v
    case .array(let values): return try values.map(fixtureObject)
    case .dictionary(let entries):
        var out: [String: Any] = [:]
        for entry in entries {
            let key: String
            switch entry.key {
            case .string(let s): key = s
            case .int(let n): key = String(n)
            default: throw NSError(domain: "RemoteStateFixture", code: 1)
            }
            out[key] = try fixtureObject(entry.value)
        }
        return out
    default: throw NSError(domain: "RemoteStateFixture", code: 2)
    }
}

private func decodedFixture(_ address: String, _ argument: RemoteValue) throws -> RemoteFrame {
    let body = try PropertyListSerialization.data(fromPropertyList: [address: fixtureObject(argument)], format: .binary, options: 0)
    return try RemoteFrameParser.decode(Data([0x01]) + body).get()
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

// MARK: - Regression boundaries: decoded inputs, old state retained on rejection

@Test func anEmptyATIUnresolvesSelectionWithoutInventingNoSelection() throws {
    var b = RemoteStateBuilder()
    b.apply(frame: 1, try decodedFixture("/ati", ati(["A"])))
    b.apply(frame: 2, try decodedFixture("/sti", sti("A", index: 0, tn: 1)))
    #expect(b.snapshot().selection?.gindex == 100)
    b.apply(frame: 3, try decodedFixture("/ati", ati([])))
    #expect(b.snapshot().strips.isEmpty && b.snapshot().atiFrame == 3)
    #expect(b.snapshot().selection?.selected == true) // no NoTrackSelected message was received
    #expect(b.snapshot().selection?.gindex == nil && b.snapshot().selection?.position == nil)
    #expect(b.issues.last?.kind == .selectionMismatch)

    var pending = RemoteStateBuilder()
    pending.apply(frame: 1, try decodedFixture("/sti", sti("A", index: 0, tn: 1)))
    #expect(pending.issues.isEmpty)
    pending.apply(frame: 2, try decodedFixture("/ati", ati([])))
    #expect(pending.issues.last?.kind == .selectionMismatch)
    pending.apply(frame: 3, try decodedFixture("/ati", ati(["A"])))
    #expect(pending.snapshot().selection?.gindex == 100)
}

@Test func malformedNestedATIAndItsKnownBoundsLeaveTheWholeStateIntact() throws {
    let base = ati(["A"]), changed = ati(["B"], uuid: ["OTHER"])
    let data = RemoteValue.data(Data([1, 2, 3, 4]))
    let colours = dict([("nc", data), ("sc", data), ("tnc", data), ("tsc", data)])
    var broken = [dict([]), replacing(colours, "nc", with: .int(1)), replacing(colours, "tsc", with: nil),
                  replacing(colours, "extra", with: data)].map { replacing(changed, "c", with: .array([$0])) }
    broken += [replacing(changed, "n", with: .array([dict([("name", .string("B"))])])),
               replacing(changed, "n", with: .array([dict([("name", .string("B")), ("gindex", .int(100)), ("extra", .int(1))])])),
               replacing(changed, "extra", with: .array([]))]
    for (key, values) in [("t", [-1, 11]), ("p", [-129, 128]), ("BgTrackInfoCollapsibleInfoKey", [-1]),
                          ("BgTrackInfoMetaInfoFlagsKey", [-1, 2])] {
        broken += values.map { replacing(changed, key, with: .array([.int($0)])) }
    }
    for bad in broken {
        var b = RemoteStateBuilder()
        b.apply(frame: 1, try decodedFixture("/ati", base))
        b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 7]], t: [0x40001: ["r": 64]])))
        let previous = b.snapshot()
        b.apply(frame: 3, try decodedFixture("/ati", bad))
        #expect(b.events.last?.kind == .atiRejected)
        #expect(b.snapshot().strips == previous.strips && b.snapshot().atiFrame == previous.atiFrame)
        b.apply(frame: 4, try decodedFixture("/ati", base))
        #expect(b.events.last?.kind == .atiDuplicate) // the rejected snapshot did not replace the duplicate baseline
    }
    // No invented constraints on nc/tn/icon or NSData length; JSON-rendered data is a string in the schema.
    for (kind, pan) in [(0, -128), (10, 127)] {
        var valid = replacing(base, "t", with: .array([.int(kind)]))
        valid = replacing(valid, "p", with: .array([.int(pan)]))
        valid = replacing(valid, "nc", with: .array([.int(-1)]))
        valid = replacing(valid, "BgTrackInfoCollapsibleInfoKey", with: .array([.int(Int.max)]))
        valid = replacing(valid, "BgTrackInfoMetaInfoFlagsKey", with: .array([.int(1)]))
        valid = replacing(valid, "c", with: .array([dict([("nc", .data(Data())), ("sc", .string("AQIDBA==")), ("tnc", data), ("tsc", data)])]))
        var b = RemoteStateBuilder()
        b.apply(frame: 1, try decodedFixture("/ati", valid))
        #expect(b.issues.isEmpty && b.snapshot().strips.count == 1)
    }
}

@Test func malformedSTILeavesTheSelectionAndDuplicateBaselineIntact() throws {
    let base = sti("A", index: 0, tn: 1)
    var broken = [dict([("n", .string("NoTrackSelected"))])]
    for key in ["n", "t", "BgTrackInfoMetaInfoFlagsKey", "tn", "BgTrackInfoIndexKey"] {
        broken.append(replacing(base, key, with: nil))
    }
    for (key, value) in [("n", RemoteValue.int(0)), ("t", .bool(false)), ("t", .int(-1)), ("t", .int(5)),
                         ("tn", .bool(false)), ("BgTrackInfoIndexKey", .string("0")),
                         ("BgTrackInfoMetaInfoFlagsKey", .double(0)), ("BgTrackInfoMetaInfoFlagsKey", .int(-1)),
                         ("BgTrackInfoShowArpeggiatorButtonKey", .int(0)), ("extra", .bool(true))] {
        broken.append(replacing(base, key, with: value))
    }
    for bad in broken {
        var b = RemoteStateBuilder()
        b.apply(frame: 1, message("/ati", ati(["A"])))
        b.apply(frame: 2, try decodedFixture("/sti", base))
        let previous = b.snapshot().selection
        b.apply(frame: 3, try decodedFixture("/sti", bad))
        #expect(b.events.last?.kind == .stiRejected)
        #expect(b.snapshot().selection == previous)
        b.apply(frame: 4, try decodedFixture("/sti", base))
        #expect(b.events.last?.kind == .stiDuplicate)
    }
    for kind in [0, 4] {
        var valid = replacing(base, "t", with: .int(kind))
        valid = replacing(valid, "BgTrackInfoMetaInfoFlagsKey", with: .int(Int.max))
        valid = replacing(valid, "BgTrackInfoShowArpeggiatorButtonKey", with: .bool(false))
        var b = RemoteStateBuilder()
        b.apply(frame: 1, message("/ati", ati(["A"])))
        b.apply(frame: 2, try decodedFixture("/sti", valid))
        #expect(b.issues.isEmpty && b.snapshot().selection?.gindex == 100)
    }
}

@Test func invalidFaderRangesAndCountsCannotReplaceKnownValues() throws {
    for (field, value) in [("vL", Int(Int32.min) - 1), ("vL", Int(Int32.max) + 1), ("s", -129), ("s", 128),
                           ("m", -1), ("r", -1), ("r", 2), ("ip", -1), ("ip", 4096)] {
        var b = RemoteStateBuilder()
        b.apply(frame: 1, message("/ati", ati(["A"])))
        b.apply(frame: 2, message("/gtFaderData", fader(g: [100: ["vL": 7, "m": 0]], t: [0x40001: ["r": 64, "ip": 0]])))
        let previous = b.snapshot().strips
        let bad = ["r", "ip"].contains(field)
            ? fader(g: [100: ["m": 1]], t: [0x40001: [field: value]])
            : fader(g: [100: [field: value]], t: [0x40001: ["r": 128]])
        b.apply(frame: 3, try decodedFixture("/gtFaderData", bad))
        #expect(b.events.last?.kind == .faderRejected)
        #expect(b.snapshot().strips == previous) // even the valid side of the refused message is not applied
    }
    var b = RemoteStateBuilder()
    b.apply(frame: 1, message("/ati", ati(["A"])))
    for (i, r) in [0, 1, 3, 64, 128].enumerated() {
        let lower = i % 2 == 0
        b.apply(frame: i + 2, try decodedFixture("/gtFaderData", fader(
            g: [100: ["vL": lower ? Int(Int32.min) : Int(Int32.max), "s": lower ? -128 : 127, "m": Int.max]],
            t: [0x40001: ["r": r, "ip": lower ? 0 : 4095]])))
        #expect(b.snapshot().strips[0].track.r?.value == r)
    }
    #expect(b.issues.isEmpty)
    for address in ["/allTrackCount", "/trackCount"] {
        var counts = RemoteStateBuilder()
        counts.apply(frame: 1, try decodedFixture(address, .int(0)))
        counts.apply(frame: 2, try decodedFixture(address, .int(-1)))
        #expect(counts.events.last?.kind == .countRejected)
        let snapshot = counts.snapshot()
        #expect((address == "/allTrackCount" ? snapshot.allTrackCount : snapshot.trackCount) == RemoteKnown(0, frame: 1))
        counts.apply(frame: 3, try decodedFixture(address, .int(Int.max)))
        #expect(counts.events.last?.kind == .countApplied)
    }
}
#endif

#if canImport(Testing)
// MARK: - EXP-REMOTE-001 reference recording, when present (Research/raw is not tracked by Git)

private let exp001ReferenceFrames: URL? = {
    let frames = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Research/raw/remote-recv/20261005-094234-e1/frames")
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: frames.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
    return frames
}()

@Test(.enabled(if: exp001ReferenceFrames != nil, "EXP-REMOTE-001 reference recording 20261005-094234-e1 is absent"))
func theEXP001ReferenceRecordingRebuildsLikeTheResearchTool() throws {
    let files = try FileManager.default.contentsOfDirectory(at: exp001ReferenceFrames!, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "bin" }
        // Frame files are numbered in arrival order; "10000.bin" sorts before "2000.bin" as text, so sort by number.
        .sorted { (Int($0.deletingPathExtension().lastPathComponent) ?? 0) < (Int($1.deletingPathExtension().lastPathComponent) ?? 0) }
    var b = RemoteStateBuilder()
    for file in files {
        guard case .success(let frame) = RemoteFrameParser.decode(try Data(contentsOf: file)) else { Issue.record("\(file.lastPathComponent)"); continue }
        b.apply(frame: Int(file.deletingPathExtension().lastPathComponent)!, frame)
    }
    let snap = b.snapshot()
    // Only this EXP-REMOTE-001 recording has the fixed EXP-REMOTE-002 initial-state expectations.
    #expect(b.issues.isEmpty)
    #expect(snap.strips.count == 12)
    #expect(snap.knownFaderFields == 36 && snap.knownTrackFields == 24)
    #expect(snap.complete == nil)
    #expect(snap.selection?.position == 3)
    #expect(b.events.filter { $0.kind == .atiDuplicate }.count == 1)
}
#endif
