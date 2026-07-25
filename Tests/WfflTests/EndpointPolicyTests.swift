import XCTest
@testable import Wffl

final class EndpointPolicyTests: XCTestCase {
    func testHTTPSRemoteEndpointIsAllowed() {
        XCTAssertNil(EndpointPolicy.problem(with: "https://api.example.com/v1"))
    }

    func testEmptyEndpointIsAllowedBecauseItFallsBackToAnHTTPSDefault() {
        XCTAssertNil(EndpointPolicy.problem(with: ""))
        XCTAssertNil(EndpointPolicy.problem(with: "   "))
    }

    func testPlainHTTPOnLoopbackIsAllowedForSelfHostedServers() {
        for base in ["http://localhost:8080/v1",
                     "http://127.0.0.1:11434",
                     "http://[::1]:8080/v1",
                     "http://app.localhost:1234/v1"] {
            XCTAssertNil(EndpointPolicy.problem(with: base), "expected \(base) to be allowed")
        }
    }

    func testPlainHTTPToARemoteHostIsRejected() {
        XCTAssertNotNil(EndpointPolicy.problem(with: "http://api.example.com/v1"))
        // A hostname merely containing "localhost" is still remote.
        XCTAssertNotNil(EndpointPolicy.problem(with: "http://localhost.evil.com/v1"))
    }

    func testNonHTTPSchemesAndMalformedURLsAreRejected() {
        XCTAssertNotNil(EndpointPolicy.problem(with: "ftp://api.example.com"))
        XCTAssertNotNil(EndpointPolicy.problem(with: "not a url"))
    }

    func testValidateThrowsForRejectedEndpoints() {
        XCTAssertThrowsError(try EndpointPolicy.validate("http://api.example.com/v1"))
        XCTAssertNoThrow(try EndpointPolicy.validate("https://api.example.com/v1"))
    }
}
