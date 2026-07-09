// Renders the Meetily app icon (rounded-rect gradient + waveform + mic) to PNG.
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

// Background: rounded rect with vertical gradient (deep indigo -> teal)
let inset: CGFloat = size * 0.06
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: size * 0.2, cornerHeight: size * 0.2, transform: nil)
ctx.addPath(path)
ctx.clip()
let colors = [NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.42, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.10, green: 0.55, blue: 0.55, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: size/2, y: size), end: CGPoint(x: size/2, y: 0), options: [])

// Waveform bars
let barCount = 9
let barWidth = size * 0.045
let gap = size * 0.035
let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
let startX = (size - totalW) / 2
let heights: [CGFloat] = [0.18, 0.32, 0.48, 0.62, 0.72, 0.62, 0.48, 0.32, 0.18]
ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
for i in 0..<barCount {
    let h = size * heights[i]
    let x = startX + CGFloat(i) * (barWidth + gap)
    let y = (size - h) / 2
    let bar = CGPath(roundedRect: CGRect(x: x, y: y, width: barWidth, height: h),
                     cornerWidth: barWidth/2, cornerHeight: barWidth/2, transform: nil)
    ctx.addPath(bar)
    ctx.fillPath()
}

image.unlockFocus()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError() }
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
