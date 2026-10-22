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

extension EnvironmentValues {
    /// True inside the update film: views show sample readiness instead of reading this Mac's state.
    @Entry var filmSample = false
}
