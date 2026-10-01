import Foundation
@testable import LogicCore

// Command Line Tools ship Swift Testing but not XCTest; full Xcode ships both.
#if canImport(Testing)
import Testing

@Test func requestRoundTrip() throws {
    let request = Request(id: "1", command: "transport.play")
    let data = try JSONEncoder().encode(request)
    #expect(try JSONDecoder().decode(Request.self, from: data) == request)
}

@Test func responseDefaultsToUnverified() {
    #expect(Response(id: "1", ok: true, command: "status").verified == false)
}

@Test func responseRoundTripWithStructuredFields() throws {
    let r = Response(id: "1", ok: false, command: "track.volume", backend: "mcu",
                     requested: ["volume_db": .db(-6)], observed: ["volume_db": .db(-3)],
                     error: "verification_failed")
    let data = try JSONEncoder.logicctl.encode(r)
    #expect(try JSONDecoder().decode(Response.self, from: data) == r)
}

@Test func infiniteDecibelsEncodeAsString() throws {
    let data = try JSONEncoder.logicctl.encode(JSONValue.db(-.infinity))
    #expect(String(decoding: data, as: UTF8.self) == "\"-inf\"")
    #expect(JSONValue.db(-6.05) == .number(-6.05))  // requested values are never rounded
}
#endif
