import XCTest
@testable import Wffl

final class PrefsProfileTests: XCTestCase {
    private let profileKey = "transcriptionProfile"
    private let modelKey = "whisperModel"
    private let gateProfileKey = "vocabularyGateSelectedProfile"
    private var savedProfile: Any?
    private var savedModel: Any?
    private var savedGateProfile: Any?

    override func setUp() {
        super.setUp()
        savedProfile = Prefs.d.object(forKey: profileKey)
        savedModel = Prefs.d.object(forKey: modelKey)
        savedGateProfile = Prefs.d.object(forKey: gateProfileKey)
        Prefs.d.removeObject(forKey: profileKey)
        Prefs.d.removeObject(forKey: modelKey)
        Prefs.d.removeObject(forKey: gateProfileKey)
    }

    override func tearDown() {
        if let savedProfile { Prefs.d.set(savedProfile, forKey: profileKey) } else { Prefs.d.removeObject(forKey: profileKey) }
        if let savedModel { Prefs.d.set(savedModel, forKey: modelKey) } else { Prefs.d.removeObject(forKey: modelKey) }
        if let savedGateProfile { Prefs.d.set(savedGateProfile, forKey: gateProfileKey) } else { Prefs.d.removeObject(forKey: gateProfileKey) }
        super.tearDown()
    }

    func testGateOpenSelectsDevotionalDefaults() {
        let gate = VocabularyGate(mode: .auto)
        var seen = Set<String>()
        for tripwire in Vocabulary.shared.tripwires where seen.insert(tripwire.canonical).inserted {
            gate.observe(rawText: tripwire.text)
            if gate.enabled { break }
        }
        XCTAssertTrue(gate.enabled)
        XCTAssertEqual(Prefs.transcriptionProfile, .devotional)
        XCTAssertEqual(Prefs.effectiveWhisperModel, "large-v3-turbo")
        XCTAssertTrue(Prefs.offlineBeamSearch)
    }

    func testExplicitUserModelAndProfileWinOverGate() {
        Prefs.d.set(TranscriptionProfile.general.rawValue, forKey: profileKey)
        Prefs.d.set("base.en", forKey: modelKey)
        Prefs.selectDevotionalProfileFromVocabularyGate()
        XCTAssertEqual(Prefs.transcriptionProfile, .general)
        XCTAssertEqual(Prefs.effectiveWhisperModel, "base.en")
        XCTAssertFalse(Prefs.offlineBeamSearch)
    }

    func testAutomaticProfileResetsForNextAutomaticGate() {
        Prefs.selectDevotionalProfileFromVocabularyGate()
        XCTAssertEqual(Prefs.transcriptionProfile, .devotional)
        _ = VocabularyGate(mode: .auto)
        XCTAssertEqual(Prefs.transcriptionProfile, .general)
    }

    func testExplicitProfileReplacesAutomaticProfileProvenance() {
        Prefs.selectDevotionalProfileFromVocabularyGate()
        Prefs.d.set(TranscriptionProfile.devotional.rawValue, forKey: profileKey)
        Prefs.markProfileExplicit()
        _ = VocabularyGate(mode: .auto)
        XCTAssertEqual(Prefs.transcriptionProfile, .devotional)
    }
}
