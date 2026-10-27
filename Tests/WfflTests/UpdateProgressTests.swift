import XCTest
@testable import Wffl

final class UpdateProgressTests: XCTestCase {
    func testProgressUsesReceivedBytesAndClampsOverreportedLength() {
        var progress = UpdateProgress()
        progress.setExpected(100)
        progress.received(30)
        XCTAssertEqual(progress.fraction, 0.3)
        progress.received(90)
        XCTAssertEqual(progress.fraction, 1.0)
    }

    func testProgressIsIndeterminateWithoutKnownLength() {
        var progress = UpdateProgress()
        progress.received(50)
        XCTAssertNil(progress.fraction)
    }
}
