import AppKit
import Foundation

let size: CGFloat = 1024
let corner: CGFloat = 230

func makeContext() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    return rep
}

func finish(_ rep: NSBitmapImageRep, _ path: String) {
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("saved \(path)")
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawBackground(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat, shadow: Bool) {
    if shadow {
        NSGraphicsContext.saveGraphicsState()
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(0.35)
        s.shadowBlurRadius = 24
        s.shadowOffset = NSSize(width: 0, height: -10)
        s.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGradient(colors: colors)!.draw(in: path, angle: angle)
}

func drawWave(centerY: CGFloat, barWidth: CGFloat, gap: CGFloat, heights: [CGFloat], color: NSColor) {
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (size - totalWidth) / 2
    for h in heights {
        let rect = NSRect(x: x, y: centerY - h / 2, width: barWidth, height: h)
        color.setFill()
        roundedRect(rect, radius: barWidth / 2).fill()
        x += barWidth + gap
    }
}

func drawMic(centerY: CGFloat, scale: CGFloat, color: NSColor) {
    let bodyWidth: CGFloat = 150 * scale
    let bodyHeight: CGFloat = 260 * scale
    let bodyRect = NSRect(
        x: (size - bodyWidth) / 2,
        y: centerY - bodyHeight / 2 + 40 * scale,
        width: bodyWidth,
        height: bodyHeight
    )
    color.setFill()
    roundedRect(bodyRect, radius: bodyWidth / 2).fill()

    // microphone holder arc
    let arcPath = NSBezierPath()
    arcPath.appendArc(
        withCenter: NSPoint(x: size / 2, y: centerY + 10 * scale),
        radius: 170 * scale,
        startAngle: 200, endAngle: 340
    )
    arcPath.lineWidth = 34 * scale
    color.setStroke()
    arcPath.stroke()

    // stand
    let stand = NSRect(
        x: size / 2 - 17 * scale,
        y: centerY - 240 * scale,
        width: 34 * scale,
        height: 90 * scale
    )
    roundedRect(stand, radius: 17 * scale).fill()
}

// MARK: - A: navy background + white waveform

do {
    let rep = makeContext()
    let path = roundedRect(NSRect(x: 32, y: 32, width: size - 64, height: size - 64), radius: corner)
    drawBackground(
        path,
        colors: [NSColor(calibratedRed: 0.16, green: 0.30, blue: 0.58, alpha: 1),
                 NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.24, alpha: 1)],
        angle: -90, shadow: true
    )
    drawWave(
        centerY: size / 2,
        barWidth: 58, gap: 34,
        heights: [140, 260, 400, 300, 520, 300, 400, 260, 140],
        color: .white
    )
    finish(rep, "design/icon-a.png")
}

// MARK: - B: blue-violet background + microphone

do {
    let rep = makeContext()
    let path = roundedRect(NSRect(x: 32, y: 32, width: size - 64, height: size - 64), radius: corner)
    drawBackground(
        path,
        colors: [NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.95, alpha: 1),
                 NSColor(calibratedRed: 0.52, green: 0.24, blue: 0.78, alpha: 1)],
        angle: -90, shadow: true
    )
    drawMic(centerY: size / 2 + 10, scale: 1.15, color: .white)
    finish(rep, "design/icon-b.png")
}

// MARK: - C: light background + graphite waveform

do {
    let rep = makeContext()
    let path = roundedRect(NSRect(x: 32, y: 32, width: size - 64, height: size - 64), radius: corner)
    drawBackground(
        path,
        colors: [NSColor(calibratedWhite: 0.98, alpha: 1),
                 NSColor(calibratedWhite: 0.89, alpha: 1)],
        angle: -90, shadow: true
    )
    let heights: [CGFloat] = [120, 220, 340, 250, 430, 250, 340, 220, 120]
    drawWave(centerY: size / 2, barWidth: 56, gap: 32, heights: heights,
             color: NSColor(calibratedWhite: 0.18, alpha: 1))
    // single red bar
    let barWidth: CGFloat = 56, gap: CGFloat = 32
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let x = (size - total) / 2 + 4 * (barWidth + gap)
    NSColor(calibratedRed: 0.86, green: 0.25, blue: 0.18, alpha: 1).setFill()
    roundedRect(NSRect(x: x, y: size / 2 - 215, width: barWidth, height: 430), radius: barWidth / 2).fill()
    finish(rep, "design/icon-c.png")
}

// MARK: - D: dark theme (same drawing, inverted bars)

do {
    let rep = makeContext()
    let path = roundedRect(NSRect(x: 32, y: 32, width: size - 64, height: size - 64), radius: corner)
    drawBackground(
        path,
        colors: [NSColor(calibratedWhite: 0.20, alpha: 1),
                 NSColor(calibratedWhite: 0.09, alpha: 1)],
        angle: -90, shadow: true
    )
    let heights: [CGFloat] = [120, 220, 340, 250, 430, 250, 340, 220, 120]
    drawWave(centerY: size / 2, barWidth: 56, gap: 32, heights: heights,
             color: NSColor(calibratedWhite: 0.93, alpha: 1))
    let barWidth: CGFloat = 56, gap: CGFloat = 32
    let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let x = (size - total) / 2 + 4 * (barWidth + gap)
    NSColor(calibratedRed: 0.86, green: 0.25, blue: 0.18, alpha: 1).setFill()
    roundedRect(NSRect(x: x, y: size / 2 - 215, width: barWidth, height: 430), radius: barWidth / 2).fill()
    finish(rep, "design/icon-c-dark.png")
}
