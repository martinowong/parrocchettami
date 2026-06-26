import AppKit

guard CommandLine.arguments.count == 4,
      let renderScale = Int(CommandLine.arguments[3]),
      renderScale == 1 || renderScale == 2 else {
    fputs("usage: make-dmg-background.swift <base.png> <output.png> <1|2>\n", stderr)
    exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let canvasSize = NSSize(width: 660, height: 460)

guard let source = NSImage(contentsOf: inputURL),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width) * renderScale,
        pixelsHigh: Int(canvasSize.height) * renderScale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ) else {
    fputs("unable to load or create background image\n", stderr)
    exit(1)
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let canvas = NSRect(origin: .zero, size: canvasSize)
NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
canvas.fill()

let sourceSize = source.size
let imageScale = max(canvas.width / sourceSize.width, canvas.height / sourceSize.height)
let drawnSize = NSSize(width: sourceSize.width * imageScale, height: sourceSize.height * imageScale)
let drawnRect = NSRect(
    x: (canvas.width - drawnSize.width) / 2,
    y: (canvas.height - drawnSize.height) / 2,
    width: drawnSize.width,
    height: drawnSize.height
)
source.draw(in: drawnRect, from: .zero, operation: .sourceOver, fraction: 1)

let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 21, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.28, blue: 0.22, alpha: 0.92),
    .paragraphStyle: titleStyle
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.36, blue: 0.29, alpha: 0.68),
    .paragraphStyle: titleStyle
]

NSString(string: "1. Drag to Applications").draw(
    in: NSRect(x: 40, y: 384, width: 580, height: 30),
    withAttributes: titleAttributes
)
NSString(string: "2. Control-click the app in Applications → Open").draw(
    in: NSRect(x: 40, y: 357, width: 580, height: 22),
    withAttributes: subtitleAttributes
)

let arrowColor = NSColor(calibratedRed: 0.28, green: 0.48, blue: 0.34, alpha: 0.72)
let arrow = NSBezierPath()
arrow.lineWidth = 4
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 266, y: 250))
arrow.line(to: NSPoint(x: 394, y: 250))
arrow.move(to: NSPoint(x: 374, y: 265))
arrow.line(to: NSPoint(x: 394, y: 250))
arrow.line(to: NSPoint(x: 374, y: 235))
arrowColor.setStroke()
arrow.stroke()

let instructionsPanel = NSBezierPath(ovalIn: NSRect(x: 252, y: 14, width: 156, height: 156))
NSColor(calibratedWhite: 1, alpha: 0.62).setFill()
instructionsPanel.fill()
NSColor(calibratedRed: 0.34, green: 0.50, blue: 0.39, alpha: 0.18).setStroke()
instructionsPanel.lineWidth = 1
instructionsPanel.stroke()

let guideLabelStyle = NSMutableParagraphStyle()
guideLabelStyle.alignment = .left
let guideLabelAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
    .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.31, blue: 0.24, alpha: 0.82),
    .paragraphStyle: guideLabelStyle
]
NSString(string: "Full Guide").draw(
    in: NSRect(x: 420, y: 82, width: 140, height: 20),
    withAttributes: guideLabelAttributes
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode background PNG\n", stderr)
    exit(1)
}
try png.write(to: outputURL, options: .atomic)
