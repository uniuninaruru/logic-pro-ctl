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

@Test func requestBackendRemainsOptionalOnTheWire() throws {
    let legacy = Data(#"{"id":"old","command":"transport.play","args":{}}"#.utf8)
    let request = try JSONDecoder().decode(Request.self, from: legacy)
    #expect(request.backend == nil)
    let encoded = try JSONEncoder.logicctl.encode(request)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["backend"] == nil)

    let explicit = Request(id: "new", command: "transport.play", backend: "appleevent")
    #expect(try JSONDecoder().decode(Request.self, from: JSONEncoder.logicctl.encode(explicit)) == explicit)
}

@Test func responseReadbackBackendUsesSnakeCaseAndAcceptsLegacyResponse() throws {
    let legacy = Data(#"{"id":"old","ok":true,"command":"transport.play","backend":"mcu","verified":true}"#.utf8)
    let decoded = try JSONDecoder().decode(Response.self, from: legacy)
    #expect(decoded.readbackBackend == nil)
    let legacyEncoded = try JSONEncoder.logicctl.encode(decoded)
    let legacyObject = try #require(JSONSerialization.jsonObject(with: legacyEncoded) as? [String: Any])
    #expect(legacyObject["readback_backend"] == nil)

    let response = Response(id: "new", ok: true, command: "transport.play", backend: "appleevent",
                            readbackBackend: "mcu", verified: true)
    let encoded = try JSONEncoder.logicctl.encode(response)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    #expect(object["backend"] as? String == "appleevent")
    #expect(object["readback_backend"] as? String == "mcu")
    #expect(object["readbackBackend"] == nil)
    #expect(try JSONDecoder().decode(Response.self, from: encoded) == response)
    #expect(BackendKind.appleEvent.rawValue == "appleevent")
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
