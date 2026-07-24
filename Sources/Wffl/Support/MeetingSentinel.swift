import Foundation
import CoreAudio
import AppKit

/// Notices a meeting starting/ending using two cheap signals — no window-
/// title polling, which is expensive and fragile across app updates:
///
/// 1. Primary: CoreAudio's `kAudioDevicePropertyDeviceIsRunningSomewhere` on
///    the default input device, polled every ~3s. Flips true the instant
///    *any* process opens the mic — the same low-level layer AudioDevices
///    already speaks.
/// 2. Disambiguator: a known meeting app in `NSWorkspace.runningApplications`.
///    A recognized app (Zoom, Teams, Webex, Discord, Slack, FaceTime) is a
///    confirmed signal; a browser running is only a "maybe" — mic-busy could
///    just as easily be dictation or a voice note, so browsers never trigger
///    auto-start, only a nudge.
///
/// Both signals must hold for 5s (debounce, so a Siri blip doesn't fire a
/// false positive) before `onMeetingDetected` fires; the mic signal must
/// clear for 30s before `onMeetingEnded` fires, since a brief mid-call mute
/// shouldn't look like the meeting ending.
final class MeetingSentinel {
    static let shared = MeetingSentinel()

    struct Detection {
        let appName: String
        /// A known meeting app (not just a browser) is running — safe to
        /// auto-start. Browsers are always low-confidence.
        let confident: Bool
        /// Bundle id of the detected app, if it's a recognized meeting app
        /// (nil for the browser-only "maybe" case). Used to watch for the
        /// call actually ending — see `watchApp`.
        let bundleID: String?
    }

    private static let meetingAppBundleIDs: Set<String> = [
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.cisco.webexmeetingsapp", "com.hnc.Discord",
        "com.tinyspeck.slackmacgap", "com.apple.FaceTime"
    ]
    private static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
        "com.microsoft.edgemac", "company.thebrowser.Browser"
    ]

    private static let startDebounce: TimeInterval = 5
    private static let endDebounce: TimeInterval = 30
    private static let pollInterval: TimeInterval = 3

    var onMeetingDetected: ((Detection) -> Void)?
    var onMeetingEnded: (() -> Void)?
    /// Sentinel goes quiet while a recording is in progress — never trigger
    /// off Wffl's own mic use, and no point detecting a meeting we're
    /// already capturing.
    var isRecording = false {
        didSet {
            guard oldValue != isRecording, !isRecording else { return }
            // Recording just ended — start the next detection cycle clean.
            reset()
        }
    }

    private var timer: DispatchSourceTimer?
    private var micBusySince: Date?
    private var micIdleSince: Date?
    private var firedStart = false
    /// Bundle id to watch for quitting while `isRecording` is true — see
    /// `watchApp`. Once Wffl itself opens the mic, `DeviceIsRunningSomewhere`
    /// stays true regardless of whether the *other* app's call ended, so
    /// "meeting ended" while recording has to key off the app quitting
    /// instead of the mic signal.
    private var watchedAppBundleID: String?

    private init() {}

    /// Call once a recording starts because of (or alongside) a detection,
    /// so the sentinel can later notice that app quitting and prompt to stop
    /// — "Quit Zoom → stop prompt" even though our own mic use masks the mic
    /// signal for the rest of the recording.
    func watchApp(bundleID: String?) {
        watchedAppBundleID = bundleID
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "wffl.meetingsentinel"))
        t.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        reset()
    }

    private func reset() {
        micBusySince = nil
        micIdleSince = nil
        firedStart = false
        watchedAppBundleID = nil
    }

    private func tick() {
        if isRecording {
            // Even in "off" mode, a recording that's already being watched
            // (started before the user flipped the pref) should still get
            // its stop prompt — only fresh detection is gated on the pref.
            checkWatchedAppStillRunning()
            return
        }
        guard Prefs.autoRecordMode != .off else { reset(); return }

        if Self.micInUseBySomeoneElse() {
            micIdleSince = nil
            let now = Date()
            if micBusySince == nil { micBusySince = now }
            guard !firedStart, now.timeIntervalSince(micBusySince!) >= Self.startDebounce,
                  let detection = Self.detect() else { return }
            firedStart = true
            let onDetected = onMeetingDetected
            DispatchQueue.main.async { onDetected?(detection) }
        } else {
            micBusySince = nil
            guard firedStart else { return }
            let now = Date()
            if micIdleSince == nil { micIdleSince = now }
            guard now.timeIntervalSince(micIdleSince!) >= Self.endDebounce else { return }
            firedStart = false
            micIdleSince = nil
            let onEnded = onMeetingEnded
            DispatchQueue.main.async { onEnded?() }
        }
    }

    private static func detect() -> Detection? {
        let running = NSWorkspace.shared.runningApplications
        if let app = running.first(where: { $0.bundleIdentifier.map(meetingAppBundleIDs.contains) ?? false }) {
            return Detection(appName: app.localizedName ?? "Meeting app", confident: true, bundleID: app.bundleIdentifier)
        }
        if running.contains(where: { $0.bundleIdentifier.map(browserBundleIDs.contains) ?? false }) {
            return Detection(appName: "Meeting", confident: false, bundleID: nil)
        }
        return nil
    }

    /// While we're the one recording, "meeting ended" means the watched app
    /// quit — not the mic clearing, which our own capture keeps busy.
    private func checkWatchedAppStillRunning() {
        guard let bundleID = watchedAppBundleID else { return }
        let stillRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
        guard !stillRunning else { return }
        watchedAppBundleID = nil
        let onEnded = onMeetingEnded
        DispatchQueue.main.async { onEnded?() }
    }

    private static func micInUseBySomeoneElse() -> Bool {
        guard let deviceID = AudioDevices.defaultInputDeviceID() else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning) == noErr else { return false }
        return isRunning != 0
    }
}
