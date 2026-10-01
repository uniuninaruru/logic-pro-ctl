import XCTest
@testable import LogicCore

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
