import SwiftUI

/// Frame-indexed analogue grain shared by the TV glass and full-window transition.
/// A repeated frame index always produces the same native texture.
enum TVStaticTexture {
    static let width = 600
    static let height = 480
    private static var imageCache: [Int: CGImage] = [:]

    static func samples(frame: Int) -> [UInt8] {
        var state = UInt32(truncatingIfNeeded: frame &* 0x9E3779B9) | 1
        var samples = [UInt8]()
        samples.reserveCapacity(width * height)
        for _ in 0..<(width * height) {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            samples.append(UInt8(54 + state % 112))
        }
        return samples
    }

    static func image(frame: Int) -> CGImage? {
        if let cached = imageCache[frame] { return cached }
        let data = Data(samples(frame: frame))
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else { return nil }
        if imageCache.count >= 24 { imageCache.removeAll(keepingCapacity: true) }
        imageCache[frame] = image
        return image
    }
}

/// Full-bounds signal noise for transitions that leave the CRT scene.
/// No clipping or coordinate assumptions tie this overlay to the television.
struct TVStaticOverlay: View {
    let frame: Int
    var opacity = 1.0

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard opacity > 0, let image = TVStaticTexture.image(frame: frame) else { return }
            context.opacity = min(1, max(0, opacity))
            context.draw(Image(decorative: image, scale: 1),
                         in: CGRect(origin: .zero, size: size))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
