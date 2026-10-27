import Foundation

extension Bundle {
    /// Classic-SwiftPM `Bundle.module` skips Contents/Resources and traps on any Mac but the builder (2.0.0 crash).
    static let wffl: Bundle = {
        let name = "Wffl_Wffl.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let url = base?.appendingPathComponent(name), let bundle = Bundle(url: url) { return bundle }
        }
        // `swift run` and `swift test`: the build-path accessor is the one that works there.
        return .module
    }()
}
