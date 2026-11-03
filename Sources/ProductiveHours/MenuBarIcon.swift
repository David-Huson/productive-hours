import AppKit
import ActivityCore

enum MenuBarIconComposer {
    static func make(indicator: MenuBarActivityIndicator) -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pointSize: CGFloat = 18
        let pixelSize = pointSize * scale
        let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
        image.lockFocus()
        defer { image.unlockFocus() }
        if let base = baseLogo() {
            base.draw(
                in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
                from: NSRect(origin: .zero, size: base.size),
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
        if indicator != .hidden {
            let dotDiameter = pixelSize * 0.36
            let inset = pixelSize * 0.04
            let dot = NSRect(
                x: pixelSize - dotDiameter - inset,
                y: inset,
                width: dotDiameter,
                height: dotDiameter
            )
            fillColor(for: indicator).setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = max(1, scale * 0.5)
            ring.stroke()
        }
        image.size = NSSize(width: pointSize, height: pointSize)
        image.isTemplate = false
        return image
    }

    private static func fillColor(for indicator: MenuBarActivityIndicator) -> NSColor {
        switch indicator {
        case .active: NSColor.systemGreen
        case .passive: NSColor.systemBlue
        case .inactive: NSColor.systemYellow
        case .unproductive: NSColor.systemRed
        case .hidden: .clear
        }
    }

    private static func baseLogo() -> NSImage? {
        if let url = Bundle.main.url(forResource: "Worktempo", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        if let image = NSImage(named: "Worktempo") { return image }
        return NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Worktempo")
    }
}
