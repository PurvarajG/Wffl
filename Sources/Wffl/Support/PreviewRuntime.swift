import Foundation
import SwiftUI

enum PreviewRuntime {
    static var isUIPreview: Bool {
        #if DEBUG
        return !(ProcessInfo.processInfo.environment["WFFL_UI_PREVIEW_DATA_DIR"] ?? "").isEmpty
        #else
        return false
        #endif
    }

    static var forcedAppearance: String? {
        #if DEBUG
        guard isUIPreview else { return nil }
        return ProcessInfo.processInfo.environment["WFFL_UI_PREVIEW_APPEARANCE"]
        #else
        return nil
        #endif
    }

    static var forceReduceMotion: Bool {
        #if DEBUG
        return isUIPreview && ProcessInfo.processInfo.environment["WFFL_UI_PREVIEW_REDUCE_MOTION"] == "1"
        #else
        return false
        #endif
    }

    static var isRecordingFixture: Bool {
        #if DEBUG
        return isUIPreview && ProcessInfo.processInfo.environment["WFFL_UI_PREVIEW_RECORDING"] == "1"
        #else
        return false
        #endif
    }
}

extension PreviewRuntime {
    /// Sample library used by the update film. It never touches the real database.
    static func sampleMeetings(now: Date = Date()) -> [Meeting] {
        func meeting(_ title: String, daysAgo: Double, minutes: Double) -> Meeting {
            var m = Meeting.new(title: title)
            m.createdAt = now.addingTimeInterval(-daysAgo * 86_400)
            m.updatedAt = m.createdAt
            m.durationSeconds = minutes * 60
            return m
        }
        return [meeting("Weekly product sync", daysAgo: 0, minutes: 24),
                meeting("Design review", daysAgo: 1, minutes: 41),
                meeting("Interview notes", daysAgo: 3, minutes: 33)]
    }
}

extension EnvironmentValues {
    /// True inside the update film: views show sample readiness instead of reading this Mac's state.
    @Entry var filmSample = false
}
