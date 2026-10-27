import AppKit
import SwiftUI

/// Coordinates measured against the approved 1672 × 941 photographic composite.
enum CRTTelevisionGeometry {
    static func photo(in size: CGSize) -> CGRect {
        let scale = max(size.width / 1672, size.height / 941)
        return CGRect(x: (size.width - 1672 * scale) / 2, y: (size.height - 941 * scale) / 2,
                      width: 1672 * scale, height: 941 * scale)
    }

    /// The approved slow push is unchanged; the quick pullback begins only at 8.5s.
    static func zoom(at elapsed: Double) -> Double {
        let push = 1 + 0.22 * MotionCurve.segment(elapsed, 0.50, WelcomeOpeningTiming.pushEnd)
        let pullback = MotionCurve.segment(elapsed, WelcomeOpeningTiming.pushEnd,
                                           WelcomeOpeningTiming.pullbackEnd)
        return push + (0.90 - 1.22) * pullback
    }
}

enum CRTPhotograph {
    static let image: NSImage? = {
        var bundles = [Bundle.module, Bundle.main]
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Wffl_Wffl.bundle"),
           let bundle = Bundle(url: url) { bundles.append(bundle) }
        return bundles.lazy.compactMap {
            $0.url(forResource: "television-approved", withExtension: "png", subdirectory: "Resources/Opening")
        }.compactMap { NSImage(contentsOf: $0) }.first
    }()
}

/// The old design remains a photographic object through the slow push and quick pullback.
/// Full-window static and correction are separate scenes after this view leaves.
struct CRTTelevision: View {
    let elapsed: Double

    var body: some View {
        GeometryReader { geometry in
            Canvas(rendersAsynchronously: false) { context, size in
                guard let photograph = CRTPhotograph.image else { return }
                context.draw(Image(nsImage: photograph), in: CRTTelevisionGeometry.photo(in: size))
            }
            .scaleEffect(CRTTelevisionGeometry.zoom(at: elapsed), anchor: UnitPoint(x: 0.5075, y: 0.4255))
            .clipped()
        }
    }
}
