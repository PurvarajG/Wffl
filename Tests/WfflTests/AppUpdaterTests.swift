import XCTest
@testable import Wffl

final class AppUpdaterTests: XCTestCase {
    func testIntervalSecondsMatchSparkleValues() {
        XCTAssertEqual(UpdateCheckInterval.daily.seconds, 86_400)
        XCTAssertEqual(UpdateCheckInterval.weekly.seconds, 604_800)
        XCTAssertEqual(UpdateCheckInterval.monthly.seconds, 2_592_000)
    }

    func testIntervalMapsStoredSecondsToTheNearestChoice() {
        XCTAssertEqual(UpdateCheckInterval(seconds: 86_400), .daily)
        XCTAssertEqual(UpdateCheckInterval(seconds: 604_800), .weekly)
        XCTAssertEqual(UpdateCheckInterval(seconds: 2_592_000), .monthly)
        XCTAssertEqual(UpdateCheckInterval(seconds: 3_600), .daily)
        XCTAssertEqual(UpdateCheckInterval(seconds: 400_000), .weekly)
        XCTAssertEqual(UpdateCheckInterval(seconds: 10_000_000), .monthly)
    }

    func testPublicKeyDetection() {
        XCTAssertFalse(UpdaterEligibility.hasPublicKey(nil))
        XCTAssertFalse(UpdaterEligibility.hasPublicKey(""))
        XCTAssertFalse(UpdaterEligibility.hasPublicKey("  \n"))
        XCTAssertFalse(UpdaterEligibility.hasPublicKey("SPARKLE_PUBLIC_ED_KEY_NOT_SET"))
        XCTAssertTrue(UpdaterEligibility.hasPublicKey("dGVzdC1rZXktdGVzdC1rZXktdGVzdC1rZXktMDEyMzQ="))
    }

    func testUpdaterStartsOnlyInTheRealAppWithAKey() {
        let key = "dGVzdC1rZXktdGVzdC1rZXktdGVzdC1rZXktMDEyMzQ="
        func start(key: String? = key, id: String? = "com.purvaraj.wffl", preview: Bool = false,
                   tests: Bool = false, env: [String: String] = [:]) -> Bool {
            UpdaterEligibility.shouldStart(publicKey: key, bundleIdentifier: id, isUIPreview: preview,
                                           isRunningTests: tests, environment: env)
        }
        XCTAssertTrue(start())
        XCTAssertFalse(start(key: nil))
        XCTAssertFalse(start(key: UpdaterEligibility.placeholderKey))
        XCTAssertFalse(start(id: nil))
        XCTAssertFalse(start(id: "com.example.review"))
        XCTAssertFalse(start(preview: true))
        XCTAssertFalse(start(tests: true))
        XCTAssertFalse(start(env: ["WFFL_DISABLE_UPDATER": "1"]))
    }

    @MainActor func testUpdaterIsInertUnderTests() {
        let updater = AppUpdater()
        XCTAssertFalse(updater.isConfigured)
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertFalse(updater.automaticallyChecksForUpdates)
        XCTAssertNil(updater.lastUpdateCheckDate)
    }

    func testSettingsCopy() {
        XCTAssertEqual(UpdateSettings.versionLine(short: "2.1.0", build: "22"), "Wffl 2.1.0 (22)")
        XCTAssertEqual(UpdateSettings.versionLine(short: nil, build: nil), "Wffl")
        XCTAssertEqual(UpdateSettings.lastCheckedLine(nil), "Never checked")
        let now = Date()
        XCTAssertEqual(UpdateSettings.lastCheckedLine(now.addingTimeInterval(-7_200), now: now), "Last checked 2 hours ago")
        for line in ["Never checked", "This build of Wffl can’t check for updates."] {
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}"))
        }
    }
}
