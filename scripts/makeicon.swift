// Renders the Wffl app icon (SPEC Part 3, option A "Ink"): 824pt continuous-corner body on a
// 1024 grid, tile #1B1B1B -> #0A0A0A, eight #F2F2F0 capsule bars (heights match WMarkView and the
// website favicon). No baked shadow or hairline: macOS draws its own edge.
// Usage: swift scripts/makeicon.swift <out-dir>
//   writes icon_<16|32|64|128|256|512|1024>.png and bars.svg (the layer in Support/AppIcon.icon).
// Support/AppIcon.icns = iconutil over those PNGs (16x16=16, 16x16@2x=32, 32x32=32, 32x32@2x=64,
// 128x128=128, 128x128@2x=256, 256x256=256, 256x256@2x=512, 512x512=512, 512x512@2x=1024).
import SwiftUI

let heights8: [CGFloat] = [1, 0.67, 0.33, 0.67, 0.87, 0.67, 0.33, 1]
// Below 64 px eight bars blur no matter how they are drawn, so 32 gets six bars and 16 gets five,
// snapped to whole pixels (same W silhouette; six at 16 px touch the tile edge).
let heights6: [CGFloat] = [1, 0.33, 0.87, 0.87, 0.33, 1]
let heights5: [CGFloat] = [1, 0.33, 0.87, 0.33, 1]
let barColor = Color(red: 0.949, green: 0.949, blue: 0.941)

struct Icon: View {
    let px: CGFloat
    var body: some View {
        let u = px / 1024
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 185 * u, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.106, green: 0.106, blue: 0.106),
                                              Color(red: 0.039, green: 0.039, blue: 0.039)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824 * u, height: 824 * u)
                .offset(x: 100 * u, y: 100 * u)
            if px < 64 {
                let w: CGFloat = px == 16 ? 1 : 2, gap: CGFloat = 1
                let hs = px == 16 ? heights5 : heights6
                let x0 = ((px - (CGFloat(hs.count) * w + CGFloat(hs.count - 1) * gap)) / 2).rounded(.down)
                ForEach(hs.indices, id: \.self) { i in
                    let h = (384 * u * hs[i]).rounded()
                    Rectangle().fill(barColor).frame(width: w, height: h)
                        .offset(x: x0 + CGFloat(i) * (w + gap), y: ((px - h) / 2).rounded(.down))
                }
            } else {
                ForEach(0..<8, id: \.self) { i in
                    Capsule().fill(barColor).frame(width: 44 * u, height: 384 * u * heights8[i])
                        .offset(x: (266 + 64 * CGFloat(i)) * u, y: (512 - 192 * heights8[i]) * u)
                }
            }
        }
        .frame(width: px, height: px, alignment: .topLeading)
    }
}

@MainActor func render(_ px: Int, to url: URL) {
    let r = ImageRenderer(content: Icon(px: CGFloat(px)))
    r.scale = 1
    guard let cg = r.cgImage else { fatalError("render failed at \(px)") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
MainActor.assumeIsolated {
    for px in [16, 32, 64, 128, 256, 512, 1024] { render(px, to: out.appendingPathComponent("icon_\(px).png")) }
}
let bars = heights8.enumerated().map { i, h in
    String(format: "<rect x=\"%d\" y=\"%.1f\" width=\"44\" height=\"%.1f\" rx=\"22\" fill=\"#F2F2F0\"/>", 266 + 64 * i, 512 - 192 * h, 384 * h)
}.joined()
try! "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 1024\">\(bars)</svg>"
    .write(to: out.appendingPathComponent("bars.svg"), atomically: true, encoding: .utf8)
print("wrote icon PNGs and bars.svg to \(out.path)")
