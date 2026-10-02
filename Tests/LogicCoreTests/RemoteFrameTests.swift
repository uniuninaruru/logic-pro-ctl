import Foundation
@testable import LogicCore

// Logic Remote frame parser. The fixtures are SYNTHETIC (Tools/research-scripts/make_remote_fixtures.py),
// built from the format read in SA-REMOTE-FRAME-001: they show the parser follows that reading,
// not that Logic sends exactly this. Replace with captures when PLAN-05 produces some.
#if canImport(Testing)
import Testing

private func frame(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/logic-remote/\(name)")
    return try Data(contentsOf: url)
}

private func decode(_ data: Data, limits: RemoteFrameLimits = .default) -> Result<RemoteFrame, RemoteFrameError> {
    RemoteFrameParser.decode(data, limits: limits)
}

private func failure(_ result: Result<RemoteFrame, RemoteFrameError>) -> RemoteFrameError? {
    if case .failure(let error) = result { return error }
    return nil
}

/// A MAZP container built the way maCompressedDataWithCompressionLevel: does it.
private func mazp(declared: Int, headerLength: Int = 10, body: [UInt8]) -> Data {
    var data = Data("MAZP".utf8)
    data.append(contentsOf: [UInt8(headerLength >> 8), UInt8(headerLength & 0xFF)])
    data.append(contentsOf: [UInt8(declared >> 24 & 0xFF), UInt8(declared >> 16 & 0xFF), UInt8(declared >> 8 & 0xFF), UInt8(declared & 0xFF)])
    data.append(contentsOf: body)
    return data
}

@Test func plistFrameWithOneMessage() throws {
    let result = try decode(frame("plist_single.bin")).get()
    #expect(result.format == .propertyList && result.container == .plain && !result.ordered)
    #expect(result.messages == [RemoteMessage(address: "/transport/headerState", argument: .int(5))])
}

@Test func jsonFrameWithOneOrTwoMessages() throws {
    let one = try decode(frame("json_single.bin")).get()
    #expect(one.format == .json)
    #expect(one.messages == [RemoteMessage(address: "/keyCommand/actionNum", argument: .int(3))])

    let two = try decode(frame("json_two_messages.bin")).get()
    #expect(two.groups.count == 1 && two.groups[0].count == 2)
    #expect(Set(two.messages.map(\.address)) == ["/protocolVersion", "/hostLocaleIdentifier"])
    #expect(two.messages.first { $0.address == "/hostLocaleIdentifier" }?.argument == .string("ja_JP"))
}

@Test func anArrayIsAnOrderedBatchAndKeepsItsOrder() throws {
    let result = try decode(frame("plist_ordered_batch.bin")).get()
    #expect(result.ordered)
    #expect(result.groups.map { $0.map(\.address) } == [["/a/first"], ["/a/second"], ["/a/third"]])
    #expect(result.messages.map(\.argument) == [.int(1), .int(2), .int(3)])
}

@Test func keyedArchivesKeepNumericDictionaryKeys() throws {
    let result = try decode(frame("archive_numeric_keys.bin")).get()
    #expect(result.format == .keyedArchive)
    #expect(result.messages.map(\.address) == ["/gtFaderData"])
    guard case .dictionary(let top) = result.messages[0].argument,
          let g = top.first(where: { $0.key == .string("g") }), case .dictionary(let instruments) = g.value else {
        Issue.record("expected /gtFaderData to hold a dictionary g"); return
    }
    // The inner keys are numbers, which plist and JSON cannot carry.
    #expect(instruments.map(\.key) == [.int(7), .int(12)])
    #expect(instruments[0].value == .dictionary([
        RemoteEntry(key: .string("m"), value: .int(2)),
        RemoteEntry(key: .string("s"), value: .int(0)),
        RemoteEntry(key: .string("vL"), value: .int(12441)),
    ]))
}

@Test func compressedFramesAreInflatedAndChecked() throws {
    for name in ["json_compressed_mazp.bin", "plist_compressed_mazp.bin"] {
        let result = try decode(frame(name)).get()
        guard case .mazp(let declared) = result.container else { Issue.record("\(name): not MAZP"); continue }
        #expect(declared > 1024, "\(name): only payloads above 1 KiB are compressed")
        guard case .dictionary(let ati) = result.messages[0].argument,
              case .array(let tracks)? = ati.first(where: { $0.key == .string("tracks") })?.value else {
            Issue.record("\(name): /ati tracks missing"); continue
        }
        #expect(tracks.count == 60)
    }
}

@Test func theCompressedFlagWithoutAHeaderIsAPassthroughNotAnError() throws {
    let result = try decode(frame("compressed_flag_without_header.bin")).get()
    #expect(result.container == .flaggedWithoutHeader)
    #expect(result.messages == [RemoteMessage(address: "/x", argument: .int(1))])
}

@Test func anUnknownFormatIsReportedNotGuessed() throws {
    #expect(failure(decode(try frame("unknown_format_3.bin"))) == .unknownFormat(3))
    #expect(failure(decode(Data([0x00, 0x01]))) == .unknownFormat(0))
    #expect(failure(decode(Data([0xFF, 0x01]))) == .unknownFormat(0x7F))
}

@Test func malformedFramesAreEachTold() throws {
    #expect(failure(decode(Data())) == .empty)
    #expect(failure(decode(Data([4]) + Data("{not json".utf8)))?.isDecodeFailed == true)
    // A bare word is a valid old-style ASCII plist (a string): Logic reads it the same way, then finds no messages.
    #expect(failure(decode(Data([1]) + Data("junk".utf8))) == .unexpectedTopLevel)
    #expect(failure(decode(Data([1]) + Data("bplist00".utf8) + Data([0, 1, 2, 3])))?.isDecodeFailed == true)
    #expect(failure(decode(Data([1]) + Data("<?xml version=\"1.0\"?><plist><dict><key>a".utf8)))?.isDecodeFailed == true)
    #expect(failure(decode(Data([2]) + Data("junk".utf8)))?.isDecodeFailed == true)
    #expect(failure(decode(Data([0x84]) + Data("123456789".utf8))) == .truncatedContainer)  // under 10 bytes
    #expect(failure(decode(Data([4]) + Data("[1,2]".utf8))) == .arrayElementNotDictionary(index: 0))
    #expect(failure(decode(Data([4]) + Data("\"text\"".utf8)))?.isDecodeFailed == true)  // JSON fragments are refused
    #expect(failure(decode(Data([4]) + Data("{\"/a\":".utf8)))?.isDecodeFailed == true)
}

@Test func containerHeaderProblemsAreTold() throws {
    let good = try frame("json_compressed_mazp.bin")
    var body = Array(good.dropFirst(11))  // the zlib stream after tag + 10-byte header

    // header length beyond the data
    var bad = Data([0x84]) + mazp(declared: 100, headerLength: 5000, body: body)
    #expect(failure(decode(bad)) == .badContainerHeader)
    // header length below the 10 bytes it must hold
    bad = Data([0x84]) + mazp(declared: 100, headerLength: 4, body: body)
    #expect(failure(decode(bad)) == .badContainerHeader)
    // a declared size above the limit (Logic itself would try to allocate it)
    bad = Data([0x84]) + mazp(declared: 0x7FFF_FFFF, body: body)
    #expect(failure(decode(bad)) == .declaredSizeTooLarge(0x7FFF_FFFF))
    // declared smaller / larger than what the stream really inflates to
    let real = (try decode(good).get().container)
    guard case .mazp(let declared) = real else { Issue.record("not MAZP"); return }
    #expect(failure(decode(Data([0x84]) + mazp(declared: declared - 1, body: body))) == .sizeMismatch(declared: declared - 1, actual: declared))
    #expect(failure(decode(Data([0x84]) + mazp(declared: declared + 5, body: body))) == .sizeMismatch(declared: declared + 5, actual: declared))
    // a damaged stream and a damaged checksum
    body[body.count / 2] ^= 0xFF
    #expect(failure(decode(Data([0x84]) + mazp(declared: declared, body: body))) != nil)
    var checksum = Array(good.dropFirst(11)); checksum[checksum.count - 1] ^= 0x01
    #expect(failure(decode(Data([0x84]) + mazp(declared: declared, body: checksum))) == .decompressionFailed)
    // not a zlib stream at all
    #expect(failure(decode(Data([0x84]) + mazp(declared: 10, body: [1, 2, 3, 4, 5, 6, 7, 8]))) == .decompressionFailed)
}

@Test func addressesMustBeStringsAndFramesAreBounded() throws {
    // a keyed archive whose top-level dictionary has a number key: not an address
    let archive = try frame("archive_numeric_keys.bin")
    let nested = Data([4]) + Data(#"{"/a":{"b":{"c":[[[[1]]]]}}}"#.utf8)
    var limits = RemoteFrameLimits(); limits.maxDepth = 3
    #expect(failure(decode(nested, limits: limits)) == .tooDeep)
    #expect(try decode(nested).get().messages.count == 1)

    var small = RemoteFrameLimits(); small.maxFrameBytes = 10
    #expect(failure(decode(archive, limits: small)) == .tooLarge(archive.count))

    // a plist dictionary can only have string keys, but a keyed archive can have number keys at the top
    let numericTop = Data([4]) + Data("5".utf8)
    #expect(failure(decode(numericTop))?.isDecodeFailed == true)
}

@Test func argumentTypesAreKept() throws {
    func argument(_ json: String) throws -> RemoteValue {
        try decode(Data([4]) + Data("{\"/a\":\(json)}".utf8)).get().messages[0].argument
    }
    #expect(try argument("true") == .bool(true))
    #expect(try argument("1") == .int(1))
    #expect(try argument("1.5") == .double(1.5))
    #expect(try argument("\"x\"") == .string("x"))
    #expect(try argument("null") == .null)
    #expect(try argument("[1,\"a\"]") == .array([.int(1), .string("a")]))
    #expect(try argument("0") != .bool(false))  // 0 and false stay different
}

private extension RemoteFrameError {
    var isDecodeFailed: Bool { if case .decodeFailed = self { return true }; return false }
}
#endif
