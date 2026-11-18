import XCTest
@testable import Wffl

final class UserAliasesTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wffl-aliases-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func store() -> UserAliases { UserAliases(fileURL: dir.appendingPathComponent("user.json")) }

    func testEmptyWhenFileMissing() {
        XCTAssertEqual(store().entries(), [])
    }

    func testAddPersistsAndGroupsByCanonical() {
        let s = store()
        s.add(heard: "Garada", meant: "Gadhada")
        s.add(heard: "Gharada", meant: "Gadhada")
        XCTAssertEqual(store().entries(), [NormalizationPack.Entry(canonical: "Gadhada", aliases: ["Garada", "Gharada"])])
    }

    func testAddingTheSameAliasTwiceKeepsOne() {
        let s = store()
        s.add(heard: "Garada", meant: "Gadhada")
        s.add(heard: "garada", meant: "Gadhada")
        XCTAssertEqual(s.entries().first?.aliases, ["Garada"])
    }

    func testRemoveDropsAliasAndEmptyEntry() {
        let s = store()
        s.add(heard: "Garada", meant: "Gadhada")
        s.remove(heard: "Garada", meant: "Gadhada")
        XCTAssertEqual(store().entries(), [])
    }

    func testUserAliasRewritesTextOnceMerged() {
        let s = store()
        s.add(heard: "Zzgarada", meant: "Gadhada")
        let loaded = NormalizationPack.Loaded(validating: s.entries())
        XCTAssertEqual(loaded.apply("He went to Zzgarada.").result, "He went to Gadhada.")
    }

    func testEnglishWordAliasIsRejectedNotApplied() {
        let s = store()
        s.add(heard: "curtain", meant: "kirtan")
        let loaded = NormalizationPack.Loaded(validating: s.entries())
        XCTAssertEqual(loaded.apply("the curtain fell").result, "the curtain fell")
        XCTAssertEqual(loaded.rejections.first?.reason, .englishWord)
    }
}
