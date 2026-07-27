import XCTest
@testable import Wffl

final class PrefsProfileTests: XCTestCase {
    private let profileKey = "transcriptionProfile"
    private let modelKey = "whisperModel"
    private let engineKey = "transcriptionEngine"
    private let gateProfileKey = "vocabularyGateSelectedProfile"
    private var savedProfile: Any?
    private var savedModel: Any?
    private var savedEngine: Any?
    private var savedGateProfile: Any?

    override func setUp() {
        super.setUp()
        savedProfile = Prefs.d.object(forKey: profileKey)
        savedModel = Prefs.d.object(forKey: modelKey)
        savedEngine = Prefs.d.object(forKey: engineKey)
        savedGateProfile = Prefs.d.object(forKey: gateProfileKey)
        Prefs.d.removeObject(forKey: profileKey)
        Prefs.d.removeObject(forKey: modelKey)
        Prefs.d.removeObject(forKey: engineKey)
        Prefs.d.removeObject(forKey: gateProfileKey)
    }

    override func tearDown() {
        if let savedProfile { Prefs.d.set(savedProfile, forKey: profileKey) } else { Prefs.d.removeObject(forKey: profileKey) }
        if let savedModel { Prefs.d.set(savedModel, forKey: modelKey) } else { Prefs.d.removeObject(forKey: modelKey) }
        if let savedEngine { Prefs.d.set(savedEngine, forKey: engineKey) } else { Prefs.d.removeObject(forKey: engineKey) }
        if let savedGateProfile { Prefs.d.set(savedGateProfile, forKey: gateProfileKey) } else { Prefs.d.removeObject(forKey: gateProfileKey) }
        super.tearDown()
    }

    // MARK: - T-01: Whisper becomes the default engine and model

    func testFreshDefaultEngineIsWhisper() {
        XCTAssertEqual(Prefs.transcriptionEngine, "whisper")
        XCTAssertEqual(Prefs.effectiveEngine, .whisper)
    }

    func testFreshDefaultModelIsLargeV3Turbo() {
        XCTAssertEqual(Prefs.whisperModel, "large-v3-turbo")
        XCTAssertEqual(Prefs.effectiveWhisperModel, "large-v3-turbo")
    }

    func testExplicitParakeetChoiceIsPreserved() {
        Prefs.d.set("parakeet", forKey: engineKey)
        XCTAssertEqual(Prefs.transcriptionEngine, "parakeet")
        XCTAssertEqual(Prefs.effectiveEngine, .parakeet)
    }

    func testExplicitBaseEnModelChoiceIsPreserved() {
        Prefs.d.set("base.en", forKey: modelKey)
        XCTAssertEqual(Prefs.whisperModel, "base.en")
        XCTAssertEqual(Prefs.effectiveWhisperModel, "base.en")
    }

    func testDevotionalProfileUnchangedByEngineDefaultFlip() {
        Prefs.d.set(TranscriptionProfile.devotional.rawValue, forKey: profileKey)
        // Devotional forces Whisper regardless of the (now-also-Whisper)
        // engine default, and still defers to whisperModel's own default.
        XCTAssertEqual(Prefs.effectiveEngine, .whisper)
        XCTAssertEqual(Prefs.effectiveWhisperModel, "large-v3-turbo")
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
