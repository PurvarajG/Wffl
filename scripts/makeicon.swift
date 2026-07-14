// Renders the Wffl app icon to PNG: cream rounded tile with the geometric
// ink "W" monogram (a quiet valley). Per the design handoff README.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

// Tile: rounded rect, warm cream with a very subtle top-light gradient.
let inset: CGFloat = size * 0.08
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: size * 0.19, cornerHeight: size * 0.19, transform: nil)

// Soft drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.03,
              color: NSColor.black.withAlphaComponent(0.18).cgColor)
ctx.addPath(path)
ctx.setFillColor(NSColor(calibratedRed: 0.949, green: 0.929, blue: 0.882, alpha: 1).cgColor) // #F2EDE1
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.973, green: 0.957, blue: 0.925, alpha: 1).cgColor,  // lighter top
              NSColor(calibratedRed: 0.925, green: 0.902, blue: 0.847, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: size/2, y: size), end: CGPoint(x: size/2, y: 0), options: [])

// Hairline inner border
ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: size * 0.004, dy: size * 0.004),
                   cornerWidth: size * 0.185, cornerHeight: size * 0.185, transform: nil))
ctx.setStrokeColor(NSColor(calibratedRed: 0.173, green: 0.149, blue: 0.11, alpha: 0.08).cgColor)
ctx.setLineWidth(size * 0.008)
ctx.strokePath()

// The W monogram — SVG path M22 32 L36 70 L50 46 L64 70 L78 32 (viewBox 100).
// Note: CG origin is bottom-left, SVG is top-left, so flip Y.
let pts: [(CGFloat, CGFloat)] = [(22, 32), (36, 70), (50, 46), (64, 70), (78, 32)]
// Scale the 100-unit box into the middle of the tile.
let boxScale = size * 0.62 / 100
let boxOrigin = CGPoint(x: (size - 100 * boxScale) / 2, y: (size - 100 * boxScale) / 2)
func mapPt(_ p: (CGFloat, CGFloat)) -> CGPoint {
    CGPoint(x: boxOrigin.x + p.0 * boxScale, y: boxOrigin.y + (100 - p.1) * boxScale)
}
ctx.setStrokeColor(NSColor(calibratedRed: 0.173, green: 0.149, blue: 0.11, alpha: 1).cgColor) // ink #2C261C
ctx.setLineWidth(size * 0.055)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: mapPt(pts[0]))
for p in pts.dropFirst() { ctx.addLine(to: mapPt(p)) }
ctx.strokePath()
ctx.restoreGState()

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError() }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
