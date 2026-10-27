import Foundation
import Combine
import Sparkle

/// How often Sparkle looks for an update when automatic checks are on.
enum UpdateCheckInterval: String, CaseIterable, Identifiable {
    case daily, weekly, monthly

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .daily: 86_400
        case .weekly: 604_800
        case .monthly: 2_592_000
        }
    }

    var label: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// Sparkle stores a raw number of seconds, so a value that is not one of ours (a shortened
    /// interval set in defaults, say) maps to the nearest of the three.
    init(seconds: TimeInterval) {
        self = Self.allCases.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) } ?? .daily
    }
}

/// Decides whether this process may run the updater. Pure, so tests can cover it.
enum UpdaterEligibility {
    static let placeholderKey = "SPARKLE_PUBLIC_ED_KEY_NOT_SET"
    static let appBundleIdentifier = "com.purvaraj.wffl"

    /// Missing, blank or the placeholder means this build cannot verify an update, so it must not
    /// try to fetch one.
    static func hasPublicKey(_ value: String?) -> Bool {
        guard let key = value?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return false }
        return key != placeholderKey
    }

    static func shouldStart(
        publicKey: String?,
        bundleIdentifier: String?,
        isUIPreview: Bool,
        isRunningTests: Bool,
        environment: [String: String]
    ) -> Bool {
        guard hasPublicKey(publicKey) else { return false }
        // Not `swift run` (no bundle id), and not the isolated review app (its own id).
        guard bundleIdentifier == appBundleIdentifier else { return false }
        guard !isUIPreview, !isRunningTests else { return false }
        return environment["WFFL_DISABLE_UPDATER"] != "1"
    }
}

/// Wraps Sparkle's standard updater for the app menu and Settings. It starts only in the real
/// app: never in previews, tests, the review app, or a build without a public key.
@MainActor
final class AppUpdater: ObservableObject {
    /// False when this process runs no updater (no usable public key, or a preview, test or review app).
    let isConfigured: Bool

    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?

    init(enabled: Bool = true) {
        isConfigured = enabled && UpdaterEligibility.shouldStart(
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            isUIPreview: PreviewRuntime.isUIPreview,
            isRunningTests: NSClassFromString("XCTestCase") != nil,
            environment: ProcessInfo.processInfo.environment
        )
        guard isConfigured else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let can = updater.canCheckForUpdates
            Task { @MainActor in
                guard let self else { return }
                self.canCheckForUpdates = can
                self.objectWillChange.send()   // the last check date moves when a check starts or ends
            }
        }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var checkInterval: UpdateCheckInterval {
        get { UpdateCheckInterval(seconds: controller?.updater.updateCheckInterval ?? UpdateCheckInterval.daily.seconds) }
        set { objectWillChange.send(); controller?.updater.updateCheckInterval = newValue.seconds }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyDownloadsUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? { controller?.updater.lastUpdateCheckDate }
}
