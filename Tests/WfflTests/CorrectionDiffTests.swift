import XCTest
@testable import Wffl

final class CorrectionDiffTests: XCTestCase {
    private typealias Pair = CorrectionDiff.Pair

    func testSingleWordFix() {
        XCTAssertEqual(CorrectionDiff.pairs(old: "He went to Garada, yesterday.", new: "He went to Gadhada, yesterday."),
                       [Pair(heard: "Garada", meant: "Gadhada")])
    }

    func testTwoWordsBecomeOne() {
        XCTAssertEqual(CorrectionDiff.pairs(old: "Jay Swami Narayan to all", new: "Jay Swaminarayan to all"),
                       [Pair(heard: "Swami Narayan", meant: "Swaminarayan")])
    }

    func testTwoSeparateFixes() {
        XCTAssertEqual(CorrectionDiff.pairs(old: "Jeeva Kachar was forgiven", new: "Jiva Khachar was forgiven"),
                       [Pair(heard: "Jeeva Kachar", meant: "Jiva Khachar")])
        XCTAssertEqual(CorrectionDiff.pairs(old: "Jeeva was in Garada then", new: "Jiva was in Gadhada then"),
                       [Pair(heard: "Jeeva", meant: "Jiva"), Pair(heard: "Garada", meant: "Gadhada")])
    }

    func testPureInsertionAndDeletionAreNotAliases() {
        XCTAssertEqual(CorrectionDiff.pairs(old: "He went home", new: "He went back home"), [])
        XCTAssertEqual(CorrectionDiff.pairs(old: "He went back home", new: "He went home"), [])
    }

    func testCaseAndPunctuationOnlyChangesAreIgnored() {
        XCTAssertEqual(CorrectionDiff.pairs(old: "the mandir was full", new: "The mandir was full."), [])
    }

    func testLongRewriteIsNotAnAlias() {
        XCTAssertEqual(CorrectionDiff.pairs(old: "one two three four five", new: "six seven eight nine ten"), [])
    }

    func testSamePairTwiceIsReportedOnce() {
        XCTAssertEqual(CorrectionDiff.pairs(old: "Garada and Garada", new: "Gadhada and Gadhada"),
                       [Pair(heard: "Garada", meant: "Gadhada")])
    }
}
