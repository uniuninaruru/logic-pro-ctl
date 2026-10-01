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
    #expect(Response(id: "1", ok: true).verified == false)
}
#elseif canImport(XCTest)
import XCTest

final class ProtocolTests: XCTestCase {
    func testRequestRoundTrip() throws {
        let request = Request(id: "1", command: "transport.play")
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(Request.self, from: data), request)
    }

    func testResponseDefaultsToUnverified() {
        XCTAssertFalse(Response(id: "1", ok: true).verified)
    }
}
#endif
