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

    // MARK: - BAPS Whisper becomes the default engine; Whisper stays the default Whisper model

    func testFreshDefaultEngineIsBaps() {
        XCTAssertEqual(Prefs.transcriptionEngine, "baps")
        XCTAssertEqual(Prefs.effectiveEngine, .baps)
    }

    /// BAPS Whisper only writes English (Gujarati words in Latin letters), so
    /// any other language, or translation, goes to stock Whisper.
    func testBapsFallsBackToWhisperOutsideEnglish() {
        let saved = Prefs.d.object(forKey: "language")
        defer { if let saved { Prefs.d.set(saved, forKey: "language") } else { Prefs.d.removeObject(forKey: "language") } }
        Prefs.d.set("gu", forKey: "language")
        XCTAssertEqual(Prefs.effectiveEngine, .whisper)
    }

    func testExplicitWhisperChoiceIsPreserved() {
        Prefs.d.set("whisper", forKey: engineKey)
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

    func testDevotionalProfileKeepsBapsButNeverParakeet() {
        Prefs.d.set(TranscriptionProfile.devotional.rawValue, forKey: profileKey)
        // BAPS Whisper is built for devotional content, so it stays; Parakeet
        // is still forced over to Whisper, which defers to whisperModel's default.
        XCTAssertEqual(Prefs.effectiveEngine, .baps)
        Prefs.d.set("parakeet", forKey: engineKey)
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
