import Foundation

// Rebuilds Logic's mixer state from Logic Remote messages (/ati, /gtFaderData, /sti, counts, /docOpen).
// It only consumes decoded messages (RemoteFrameParser); it does not connect, send or know about MCU.
// The contract and its evidence are in Research/experiments/EXP-REMOTE-002-offline-state-replay.md
// (checked once against a real reception, EXP-REMOTE-001):
//
// 1. A value not received is nil. 0 / false appear only when Logic sent them, with the frame they came in.
// 2. gindex (strip key; keys of /gtFaderData "g"), position (1-based order in the latest /ati), trackID
//    (BgTrackInfoTrackIDKey; keys of "t") and uuid are kept apart. Values follow gindex, never position.
// 3. /ati is a whole snapshot. A malformed one (wrong types, columns of different length, a repeated gindex,
//    trackID or uuid) is refused and the previous state kept. An identical resend is a duplicate.
// 4. The same gindex with another uuid is another strip: its values start again from nil. A strip that leaves
//    /ati loses its values.
// 5. /gtFaderData is partial: only the fields present change. Entries for an identifier the current /ati does
//    not list are orphans, reported and attached when a later /ati lists that identifier.
// 6. /sti is tied to a strip by its index into the latest /ati and checked (name, tn), again on every /ati
//    (an /sti can arrive first). A disagreement leaves it unresolved and is reported.
// 7. Logic sends no end-of-initial-state marker, so `complete` is never true (it is nil).
// 8. Within one group /ati is applied first.

public struct RemoteKnown<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value
    public let frame: Int
    public init(_ value: Value, frame: Int) { self.value = value; self.frame = frame }
}

public struct RemoteFaderValues: Equatable, Sendable {
    public var vL: RemoteKnown<Int>?
    public var s: RemoteKnown<Int>?
    public var m: RemoteKnown<Int>?
    public init() {}
    var knownCount: Int { [vL, s, m].compactMap { $0 }.count }
}

public struct RemoteTrackValues: Equatable, Sendable {
    public var r: RemoteKnown<Int>?
    public var ip: RemoteKnown<Int>?
    public init() {}
    var knownCount: Int { [r, ip].compactMap { $0 }.count }
}

public struct RemoteStrip: Equatable, Sendable {
    public let gindex: Int
    public var position: Int
    public var trackID: Int
    public var uuid: String
    public var tn: Int
    public var name: String
    /// /ati "t": 1 audio, 2 software instrument, 5 output, 6 Master were seen; other values are not interpreted.
    public var kind: Int
    public var channels: Int
    public var panKind: Int
    public var atiFrame: Int
    public var fader = RemoteFaderValues()
    public var track = RemoteTrackValues()
}

public struct RemoteSelection: Equatable, Sendable {
    public var selected: Bool
    public var name: String?
    public var index: Int?
    public var tn: Int?
    public var kind: Int?
    public var frame: Int
    public var gindex: Int?
    public var position: Int?
}

public struct RemoteStateEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case atiApplied, atiDuplicate, atiRejected, stripAdded, stripRemoved, stripMoved, identityChanged
        case faderApplied, faderRejected, orphanGindex, orphanTrackID, orphanAttached, badKey
        case stiApplied, stiDuplicate, stiRejected, selectionMismatch
        case countApplied, countDuplicate, countMismatch, countRejected, docOpen, docOpenRejected

        public var isIssue: Bool {
            switch self {
            case .atiRejected, .faderRejected, .stiRejected, .orphanGindex, .orphanTrackID, .identityChanged,
                 .selectionMismatch, .countMismatch, .countRejected, .badKey, .docOpenRejected:
                return true
            default:
                return false
            }
        }
    }

    public let frame: Int
    public let address: String
    public let kind: Kind
    public let detail: String
}

public struct RemoteStateSnapshot: Equatable, Sendable {
    /// Always nil: Logic sends no end marker, so completeness is never inferred.
    public let complete: Bool? = nil
    public let lastFrame: Int?
    public let atiFrame: Int?
    public let strips: [RemoteStrip]
    public let selection: RemoteSelection?
    public let allTrackCount: RemoteKnown<Int>?
    public let trackCount: RemoteKnown<Int>?
    public let docOpen: RemoteKnown<Bool>?
    public let orphanGindex: [Int]
    public let orphanTrackID: [Int]

    /// How many fader/track fields are known. Full coverage does not mean complete.
    public var knownFaderFields: Int { strips.reduce(0) { $0 + $1.fader.knownCount } }
    public var knownTrackFields: Int { strips.reduce(0) { $0 + $1.track.knownCount } }
}

/// Why a message was refused (Result needs an Error type).
struct RemoteStateRefusal: Error, Equatable { let reason: String }

public struct RemoteStateBuilder: Sendable {
    public private(set) var events: [RemoteStateEvent] = []
    public var issues: [RemoteStateEvent] { events.filter { $0.kind.isIssue } }

    private var strips: [Int: RemoteStrip] = [:]
    private var order: [Int] = []
    private var trackValues: [Int: RemoteTrackValues] = [:]
    private var orphanFader: [Int: RemoteFaderValues] = [:]
    private var orphanTrack: [Int: RemoteTrackValues] = [:]
    private var lastATI: RemoteValue?
    private var lastSTI: RemoteValue?
    private var selection: RemoteSelection?
    private var allTrackCount: RemoteKnown<Int>?
    private var trackCount: RemoteKnown<Int>?
    private var docOpen: RemoteKnown<Bool>?
    private var lastFrame: Int?
    private var atiFrame: Int?

    public init() {}

    // MARK: - Input

    public mutating func apply(frame number: Int, _ frame: RemoteFrame) {
        for group in frame.groups { apply(frame: number, group: group) }
    }

    /// One dictionary of messages. /ati first, because the others refer to it.
    public mutating func apply(frame: Int, group: [RemoteMessage]) {
        for message in group where message.address == "/ati" { apply(frame: frame, message) }
        for message in group where message.address != "/ati" { apply(frame: frame, message) }
    }

    public mutating func apply(frame: Int, _ message: RemoteMessage) {
        switch message.address {
        case "/ati": lastFrame = frame; ati(frame, message.argument)
        case "/gtFaderData": lastFrame = frame; fader(frame, message.argument)
        case "/sti": lastFrame = frame; sti(frame, message.argument)
        case "/allTrackCount", "/trackCount": lastFrame = frame; count(frame, message.address, message.argument)
        case "/docOpen":
            lastFrame = frame
            if case .bool(let open) = message.argument { docOpen = RemoteKnown(open, frame: frame); event(frame, "/docOpen", .docOpen, "\(open)") }
            else { event(frame, "/docOpen", .docOpenRejected, "not a boolean") }
        default:
            return
        }
    }

    // MARK: - Output

    public func snapshot() -> RemoteStateSnapshot {
        let list = order.compactMap { gindex -> RemoteStrip? in
            guard var strip = strips[gindex] else { return nil }
            strip.track = trackValues[strip.trackID] ?? RemoteTrackValues()
            return strip
        }
        return RemoteStateSnapshot(lastFrame: lastFrame, atiFrame: atiFrame, strips: list, selection: selection,
                                   allTrackCount: allTrackCount, trackCount: trackCount, docOpen: docOpen,
                                   orphanGindex: orphanFader.keys.sorted(), orphanTrackID: orphanTrack.keys.sorted())
    }

    // MARK: - /ati

    private struct ATIRow { var gindex, trackID, tn, kind, channels, panKind: Int; var uuid, name: String }

    private static let atiColumns = ["c", "n", "t", "nc", "p", "tn", "BgTrackInfoTrackIDKey", "BgTrackInfoTrackUUIDKey",
                                     "BgTrackInfoIconIDKey", "BgTrackInfoHasArrangeKey", "BgTrackInfoArrangeHiddenKey",
                                     "BgTrackInfoCollapsibleInfoKey", "BgTrackInfoMetaInfoFlagsKey"]

    /// Reads /ati into rows, or returns why it is refused.
    private static func parseATI(_ value: RemoteValue) -> Result<[ATIRow], RemoteStateRefusal> {
        guard let table = value.stringKeyedDictionary else { return .failure(RemoteStateRefusal(reason: "not a dictionary")) }
        var columns: [String: [RemoteValue]] = [:]
        for name in atiColumns {
            guard let column = table[name] else { return .failure(RemoteStateRefusal(reason: "missing column \(name)")) }
            guard case .array(let items) = column else { return .failure(RemoteStateRefusal(reason: "column \(name) is not an array")) }
            columns[name] = items
        }
        let lengths = Set(columns.values.map(\.count))
        guard lengths.count == 1, let count = lengths.first else { return .failure(RemoteStateRefusal(reason: "columns differ in length")) }
        var rows: [ATIRow] = []
        for i in 0..<count {
            guard let n = columns["n"]![i].stringKeyedDictionary, let name = n["name"]?.string, let gindex = n["gindex"]?.int,
                  let kind = columns["t"]![i].int, let channels = columns["nc"]![i].int, let panKind = columns["p"]![i].int,
                  let tn = columns["tn"]![i].int, let trackID = columns["BgTrackInfoTrackIDKey"]![i].int,
                  let uuid = columns["BgTrackInfoTrackUUIDKey"]![i].string,
                  columns["c"]![i].stringKeyedDictionary != nil,
                  columns["BgTrackInfoIconIDKey"]![i].int != nil, columns["BgTrackInfoCollapsibleInfoKey"]![i].int != nil,
                  columns["BgTrackInfoMetaInfoFlagsKey"]![i].int != nil,
                  case .bool = columns["BgTrackInfoHasArrangeKey"]![i], case .bool = columns["BgTrackInfoArrangeHiddenKey"]![i]
            else { return .failure(RemoteStateRefusal(reason: "row \(i) has a value of the wrong type")) }
            rows.append(ATIRow(gindex: gindex, trackID: trackID, tn: tn, kind: kind, channels: channels, panKind: panKind,
                               uuid: uuid, name: name))
        }
        for (label, values) in [("gindex", rows.map { "\($0.gindex)" }), ("trackID", rows.map { "\($0.trackID)" }), ("uuid", rows.map(\.uuid))]
        where Set(values).count != values.count {
            return .failure(RemoteStateRefusal(reason: "repeated \(label)"))
        }
        return .success(rows)
    }

    private mutating func ati(_ frame: Int, _ value: RemoteValue) {
        let rows: [ATIRow]
        switch Self.parseATI(value) {
        case .failure(let refusal): event(frame, "/ati", .atiRejected, refusal.reason); return
        case .success(let parsed): rows = parsed
        }
        if value == lastATI { event(frame, "/ati", .atiDuplicate, ""); return }
        var next: [Int: RemoteStrip] = [:]
        for (i, row) in rows.enumerated() {
            var strip = RemoteStrip(gindex: row.gindex, position: i + 1, trackID: row.trackID, uuid: row.uuid, tn: row.tn,
                                    name: row.name, kind: row.kind, channels: row.channels, panKind: row.panKind, atiFrame: frame)
            if let previous = strips[row.gindex] {
                if previous.uuid != row.uuid {
                    event(frame, "/ati", .identityChanged, "gindex \(row.gindex)")
                } else {
                    strip.fader = previous.fader
                    if previous.position != i + 1 {
                        event(frame, "/ati", .stripMoved, "gindex \(row.gindex) \(previous.position)→\(i + 1)")
                    }
                }
            } else {
                event(frame, "/ati", .stripAdded, "gindex \(row.gindex) position \(i + 1)")
            }
            next[row.gindex] = strip
        }
        for gindex in strips.keys.sorted() where next[gindex] == nil { event(frame, "/ati", .stripRemoved, "gindex \(gindex)") }
        // A track ID that stays with the same strip keeps its values; one that leaves or changes strip starts over.
        let kept = Dictionary(uniqueKeysWithValues: rows.map { ($0.trackID, $0.uuid) })
        let before = Dictionary(strips.values.map { ($0.trackID, $0.uuid) }, uniquingKeysWith: { a, _ in a })
        trackValues = trackValues.filter { id, _ in kept[id] != nil && kept[id] == before[id] }
        strips = next
        order = rows.map(\.gindex)
        lastATI = value
        atiFrame = frame
        event(frame, "/ati", .atiApplied, "\(rows.count) strips")
        attachOrphans(frame)
        resolveSelection(frame, "/ati")
        checkCounts(frame)
    }

    private mutating func attachOrphans(_ frame: Int) {
        for gindex in orphanFader.keys.sorted() where strips[gindex] != nil {
            let values = orphanFader.removeValue(forKey: gindex)!
            strips[gindex]!.fader.merge(values)
            event(frame, "/ati", .orphanAttached, "gindex \(gindex)")
        }
        let tracks = Set(strips.values.map(\.trackID))
        for id in orphanTrack.keys.sorted() where tracks.contains(id) {
            let values = orphanTrack.removeValue(forKey: id)!
            trackValues[id, default: RemoteTrackValues()].merge(values)
            event(frame, "/ati", .orphanAttached, "trackID \(id)")
        }
    }

    // MARK: - /gtFaderData

    private static let stripFields: Set<String> = ["vL", "s", "m"]
    private static let trackFields: Set<String> = ["r", "ip"]

    /// Keys are numbers in a keyed archive and strings in JSON; both name the same identifier.
    private static func identifier(_ key: RemoteValue) -> Int? {
        switch key {
        case .int(let n): return n
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    private static func entries(_ value: RemoteValue?, allowed: Set<String>) -> Result<[(key: RemoteValue, fields: [String: Int])], RemoteStateRefusal> {
        guard let value else { return .success([]) }
        guard case .dictionary(let list) = value else { return .failure(RemoteStateRefusal(reason: "not a dictionary")) }
        var out: [(key: RemoteValue, fields: [String: Int])] = []
        for entry in list {
            guard let fields = entry.value.stringKeyedDictionary else { return .failure(RemoteStateRefusal(reason: "an entry is not a dictionary")) }
            var ints: [String: Int] = [:]
            for (name, field) in fields {
                guard allowed.contains(name) else { return .failure(RemoteStateRefusal(reason: "unknown field \(name)")) }
                guard let n = field.int else { return .failure(RemoteStateRefusal(reason: "field \(name) is not an integer")) }
                ints[name] = n
            }
            out.append((entry.key, ints))
        }
        return .success(out)
    }

    private mutating func fader(_ frame: Int, _ value: RemoteValue) {
        guard let top = value.stringKeyedDictionary, Set(top.keys).isSubset(of: ["g", "t"]) else {
            event(frame, "/gtFaderData", .faderRejected, "not a dictionary of g and t"); return
        }
        let g: [(key: RemoteValue, fields: [String: Int])], t: [(key: RemoteValue, fields: [String: Int])]
        switch (Self.entries(top["g"], allowed: Self.stripFields), Self.entries(top["t"], allowed: Self.trackFields)) {
        case (.success(let a), .success(let b)): g = a; t = b
        case (.failure(let refusal), _), (_, .failure(let refusal)): event(frame, "/gtFaderData", .faderRejected, refusal.reason); return
        }
        var changed = 0, unchanged = 0
        let tracks = Set(strips.values.map(\.trackID))
        for (key, fields) in g {
            guard let gindex = Self.identifier(key) else { event(frame, "/gtFaderData", .badKey, "g \(key)"); continue }
            var incoming = RemoteFaderValues()
            incoming.set(fields, frame: frame)
            if strips[gindex] == nil {
                orphanFader[gindex, default: RemoteFaderValues()].merge(incoming)
                event(frame, "/gtFaderData", .orphanGindex, "gindex \(gindex)")
                continue
            }
            let (c, u) = strips[gindex]!.fader.mergeCounting(incoming)
            changed += c; unchanged += u
        }
        for (key, fields) in t {
            guard let id = Self.identifier(key) else { event(frame, "/gtFaderData", .badKey, "t \(key)"); continue }
            var incoming = RemoteTrackValues()
            incoming.set(fields, frame: frame)
            if !tracks.contains(id) {
                orphanTrack[id, default: RemoteTrackValues()].merge(incoming)
                event(frame, "/gtFaderData", .orphanTrackID, "trackID \(id)")
                continue
            }
            let (c, u) = trackValues[id, default: RemoteTrackValues()].mergeCounting(incoming)
            changed += c; unchanged += u
        }
        event(frame, "/gtFaderData", .faderApplied, "changed \(changed) unchanged \(unchanged)")
    }

    // MARK: - /sti

    /// /sti arrives as a keyed archive (often MAZP-compressed) inside a property-list frame.
    /// It is opened by the same frame decoder: an archive whose root dictionary has string keys reads as one group.
    static func openArchivedArgument(_ value: RemoteValue) -> RemoteValue? {
        guard case .data(let data) = value else { return value }
        let tag: UInt8 = data.starts(with: Data("MAZP".utf8)) ? 0x82 : 0x02
        guard case .success(let frame) = RemoteFrameParser.decode(Data([tag]) + data), frame.groups.count == 1 else { return nil }
        return .dictionary(frame.groups[0].map { RemoteEntry(key: .string($0.address), value: $0.argument) })
    }

    private mutating func sti(_ frame: Int, _ raw: RemoteValue) {
        guard let value = Self.openArchivedArgument(raw), let sti = value.stringKeyedDictionary,
              let name = sti["n"]?.string else {
            event(frame, "/sti", .stiRejected, "not a selected-track dictionary"); return
        }
        if value == lastSTI { event(frame, "/sti", .stiDuplicate, ""); return }
        lastSTI = value
        if name == "NoTrackSelected" {
            selection = RemoteSelection(selected: false, frame: frame)
            event(frame, "/sti", .stiApplied, "no selection")
            return
        }
        selection = RemoteSelection(selected: true, name: name, index: sti["BgTrackInfoIndexKey"]?.int, tn: sti["tn"]?.int,
                                    kind: sti["t"]?.int, frame: frame)
        resolveSelection(frame, "/sti")
        event(frame, "/sti", .stiApplied, selection?.gindex.map { "gindex \($0)" } ?? "unresolved")
    }

    private mutating func resolveSelection(_ frame: Int, _ address: String) {
        guard var current = selection, current.selected, !order.isEmpty else { return }
        current.gindex = nil
        current.position = nil
        var problems: [String] = []
        if let index = current.index, order.indices.contains(index), let strip = strips[order[index]] {
            if strip.name != current.name { problems.append("name") }
            if strip.tn != current.tn { problems.append("tn") }
            if problems.isEmpty { current.gindex = strip.gindex; current.position = strip.position }
        } else {
            problems.append("index outside /ati")
        }
        selection = current
        if !problems.isEmpty { event(frame, address, .selectionMismatch, problems.joined(separator: ",")) }
    }

    // MARK: - Counts

    private mutating func count(_ frame: Int, _ address: String, _ value: RemoteValue) {
        guard let n = value.int else { event(frame, address, .countRejected, "not an integer"); return }
        let previous = address == "/allTrackCount" ? allTrackCount : trackCount
        let known = RemoteKnown(n, frame: frame)
        if address == "/allTrackCount" { allTrackCount = known } else { trackCount = known }
        event(frame, address, previous?.value == n ? .countDuplicate : .countApplied, "\(n)")
        checkCounts(frame)
    }

    private mutating func checkCounts(_ frame: Int) {
        if let total = allTrackCount, lastATI != nil, total.value != order.count {
            event(frame, "/allTrackCount", .countMismatch, "\(total.value) vs \(order.count) strips in /ati")
        }
    }

    private mutating func event(_ frame: Int, _ address: String, _ kind: RemoteStateEvent.Kind, _ detail: String) {
        events.append(RemoteStateEvent(frame: frame, address: address, kind: kind, detail: detail))
    }
}

// MARK: - Field helpers

extension RemoteFaderValues {
    mutating func set(_ fields: [String: Int], frame: Int) {
        if let v = fields["vL"] { vL = RemoteKnown(v, frame: frame) }
        if let v = fields["s"] { s = RemoteKnown(v, frame: frame) }
        if let v = fields["m"] { m = RemoteKnown(v, frame: frame) }
    }

    mutating func merge(_ other: RemoteFaderValues) { _ = mergeCounting(other) }

    /// Takes the fields `other` has; an equal value keeps its first sighting. Returns (changed, unchanged).
    mutating func mergeCounting(_ other: RemoteFaderValues) -> (Int, Int) {
        var changed = 0, unchanged = 0
        func take(_ mine: inout RemoteKnown<Int>?, _ theirs: RemoteKnown<Int>?) {
            guard let theirs else { return }
            if mine?.value == theirs.value { unchanged += 1 } else { mine = theirs; changed += 1 }
        }
        take(&vL, other.vL); take(&s, other.s); take(&m, other.m)
        return (changed, unchanged)
    }
}

extension RemoteTrackValues {
    mutating func set(_ fields: [String: Int], frame: Int) {
        if let v = fields["r"] { r = RemoteKnown(v, frame: frame) }
        if let v = fields["ip"] { ip = RemoteKnown(v, frame: frame) }
    }

    mutating func merge(_ other: RemoteTrackValues) { _ = mergeCounting(other) }

    mutating func mergeCounting(_ other: RemoteTrackValues) -> (Int, Int) {
        var changed = 0, unchanged = 0
        func take(_ mine: inout RemoteKnown<Int>?, _ theirs: RemoteKnown<Int>?) {
            guard let theirs else { return }
            if mine?.value == theirs.value { unchanged += 1 } else { mine = theirs; changed += 1 }
        }
        take(&r, other.r); take(&ip, other.ip)
        return (changed, unchanged)
    }
}

extension RemoteValue {
    var int: Int? { if case .int(let n) = self { return n }; return nil }
    var string: String? { if case .string(let s) = self { return s }; return nil }
    /// A dictionary whose keys are all strings, as a Swift dictionary; nil otherwise.
    var stringKeyedDictionary: [String: RemoteValue]? {
        guard case .dictionary(let entries) = self else { return nil }
        var out: [String: RemoteValue] = [:]
        for entry in entries {
            guard case .string(let key) = entry.key else { return nil }
            out[key] = entry.value
        }
        return out
    }
}
