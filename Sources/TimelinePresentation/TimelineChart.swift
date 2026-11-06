import AppKit
import SwiftUI
import ActivityCore

public struct TimelineChart: NSViewRepresentable {
    public let days: [TimelineDay]
    public let revision: UUID
    public let settings: AppSettings
    public let rules: [ClassificationRule]
    public let command: Int
    public let action: String
    public init(days: [TimelineDay], revision: UUID, settings: AppSettings, rules: [ClassificationRule], command: Int, action: String) {
        self.days = days; self.revision = revision; self.settings = settings; self.rules = rules
        self.command = command; self.action = action
    }
    public func makeNSView(context: Context) -> TimelineDrawingView { TimelineDrawingView() }
    public func updateNSView(_ view: TimelineDrawingView, context: Context) {
        if view.revision != revision {
            view.days = days; view.settings = settings; view.rules = rules; view.revision = revision
            view.invalidateChart()
        }
        if view.command != command {
            view.command = command
            switch action {
            case "in": view.viewport.zoom(by: 2)
            case "out": view.viewport.zoom(by: 0.5)
            case "left": view.viewport.pan(by: -view.viewport.span / 2)
            case "right": view.viewport.pan(by: view.viewport.span / 2)
            default: view.viewport = TimelineViewport()
            }
            view.invalidateChart()
        }
    }
}

public extension TimelineCategory {
    var color: NSColor {
        switch self {
        case .productiveActive: return NSColor(red: 0, green: 0.67, blue: 0.62, alpha: 1)
        case .productivePassive: return NSColor(red: 0.46, green: 0.83, blue: 0.79, alpha: 1)
        case .unproductiveActive: return .systemPurple
        case .unproductivePassive: return NSColor.systemPurple.blended(withFraction: 0.55, of: .windowBackgroundColor) ?? .systemPurple
        case .undefinedActive: return .darkGray
        case .undefinedPassive: return .lightGray
        case .ignored: return .systemBrown
        case .inactive: return NSColor.systemGray.withAlphaComponent(0.3)
        case .untracked: return .systemOrange
        }
    }
}

/// A finite, cached bitmap for the chart; pointer movement only redraws that bitmap and a small tooltip.
@MainActor public final class TimelineDrawingView: NSView {
    var days: [TimelineDay] = []
    var settings = AppSettings()
    var rules: [ClassificationRule] = []
    var revision: UUID?
    var command = 0
    var viewport = TimelineViewport()
    private var cached: NSImage?
    private var cachedSize = NSSize.zero
    private var tracking: NSTrackingArea?
    private var hover: (point: NSPoint, row: Interval)?
    private var dragging = false
    private let dateFormatter = DateFormatter()
    private let timeFormatter = DateFormatter()
    private let labelWidth: CGFloat = 166
    private let rowHeight: CGFloat = 74
    private let top: CGFloat = 8
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    private var plotWidth: CGFloat { max(1, bounds.width - labelWidth - 12) }

    func invalidateChart() { cached = nil; hover = nil; needsDisplay = true }
    public override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); invalidateChart() }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    private func text(_ value: String, at point: NSPoint, size: CGFloat = 11, color: NSColor = .secondaryLabelColor) {
        (value as NSString).draw(at: point, withAttributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color])
    }
    private func x(_ time: Int64, day: TimelineDay) -> CGFloat {
        let fraction = Double(time - day.start.epochMS) / Double(day.end.epochMS - day.start.epochMS)
        return labelWidth + CGFloat((fraction - viewport.start) / viewport.span) * plotWidth
    }
    private func seconds(_ value: Double) -> String {
        let whole = max(0, Int(value))
        return "\(whole / 3600)h \(whole % 3600 / 60)m \(whole % 60)s"
    }
    func renderBase() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
        dateFormatter.calendar = settings.calendar; dateFormatter.timeZone = settings.calendar.timeZone
        dateFormatter.dateFormat = "EEE, MMM d"
        timeFormatter.calendar = settings.calendar; timeFormatter.timeZone = settings.calendar.timeZone
        timeFormatter.dateFormat = viewport.span < 0.01 ? "HH:mm:ss" : "HH:mm"
        for (index, day) in days.enumerated() {
            let y = top + CGFloat(index) * rowHeight
            text(dateFormatter.string(from: day.start), at: NSPoint(x: 10, y: y + 15), size: 12, color: .labelColor)
            text("\(Metrics.duration(day.productive)) productive", at: NSPoint(x: 10, y: y + 35))
            let daySeconds = day.end.timeIntervalSince(day.start)
            if daySeconds != 86400 { text("\(Int(daySeconds / 3600))-hour day", at: NSPoint(x: 10, y: y + 52), size: 9) }
            let bar = NSRect(x: labelWidth, y: y + 28, width: plotWidth, height: 22)
            NSColor.controlBackgroundColor.setFill(); bar.fill()
            // At most seven ticks per row, independent of zoom or day length.
            for tick in 0...6 {
                let fraction = viewport.start + viewport.span * Double(tick) / 6
                let px = labelWidth + plotWidth * CGFloat(tick) / 6
                let date = day.start.addingTimeInterval(daySeconds * fraction)
                let title = timeFormatter.string(from: date)
                text(title, at: NSPoint(x: min(bounds.width - 48, max(labelWidth, px - 16)), y: y + 7), size: 10)
                NSColor.separatorColor.setFill(); NSRect(x: px, y: y + 24, width: 0.5, height: 32).fill()
            }
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: bar).addClip()
            let firstTime = day.start.epochMS + Int64(Double(day.end.epochMS - day.start.epochMS) * viewport.start)
            let endTime = day.start.epochMS + Int64(Double(day.end.epochMS - day.start.epochMS) * (viewport.start + viewport.span))
            var i = day.index(at: firstTime)
            while i < day.intervals.count && day.intervals[i].start < endTime {
                let row = day.intervals[i]
                let left = x(row.start, day: day), right = x(row.end, day: day)
                TimelineCategory.category(row).color.setFill()
                NSRect(x: left, y: bar.minY, width: max(0.5, right - left), height: bar.height).fill()
                // Collapse subpixel observations only in the overview rendering. Hit testing stays exact.
                let pixelEnd = floor(max(labelWidth, right)) + 1
                let fraction = viewport.start + Double((pixelEnd - labelWidth) / plotWidth) * viewport.span
                let nextPixelTime = day.start.epochMS + Int64(Double(day.end.epochMS - day.start.epochMS) * fraction)
                i = max(i + 1, day.index(at: nextPixelTime))
            }
            NSGraphicsContext.restoreGraphicsState()
            if settings.workdays.contains(settings.calendar.component(.weekday, from: day.start)) {
                for hour in [settings.startHour, settings.endHour] {
                    let time = hour == 24 ? day.end : settings.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start)!
                    let px = x(time.epochMS, day: day)
                    if px >= labelWidth && px <= labelWidth + plotWidth {
                        NSColor.labelColor.withAlphaComponent(0.7).setFill()
                        NSRect(x: px, y: y + 24, width: 1.5, height: 31).fill()
                    }
                }
            }
            if day.intervals.isEmpty { text("No retained observations", at: NSPoint(x: labelWidth + 8, y: y + 52), size: 10) }
            NSColor.separatorColor.setFill(); NSRect(x: 0, y: y + rowHeight - 1, width: bounds.width, height: 0.5).fill()
        }
        return image
    }
    public override func draw(_ dirtyRect: NSRect) {
        if cached == nil || cachedSize != bounds.size { cached = renderBase(); cachedSize = bounds.size }
        cached?.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        if let hover { drawTooltip(hover.row, point: hover.point) }
    }
    func interval(at point: NSPoint) -> Interval? {
        guard point.x >= labelWidth, point.x <= labelWidth + plotWidth, point.y >= top else { return nil }
        let index = Int((point.y - top) / rowHeight)
        guard index < days.count else { return nil }
        let localY = point.y - top - CGFloat(index) * rowHeight
        guard (24...56).contains(localY) else { return nil }
        let day = days[index]
        let fraction = viewport.start + Double((point.x - labelWidth) / plotWidth) * viewport.span
        let time = day.start.epochMS + Int64(Double(day.end.epochMS - day.start.epochMS) * fraction)
        return day.interval(at: time)
    }
    private func drawTooltip(_ row: Interval, point: NSPoint) {
        let formatter = timeFormatter
        formatter.dateFormat = "HH:mm:ss z"
        let source = row.source.privateBrowsing ? "Private browsing excluded" : ActivityLabel.label(for: row.source, rules: rules)
        let observed = row.activity == .inactive ? "Last observed: " : ""
        let detail = "\(TimelineCategory.category(row).rawValue) · \(seconds(row.seconds))\n\(formatter.string(from: Date(epochMS: row.start))) – \(formatter.string(from: Date(epochMS: row.end)))\n\(observed)\(source)\nReason: \(row.reason)"
        let area = visibleRect
        let width = min(380, max(100, area.width - 16)), height: CGFloat = 98
        let left = min(max(area.minX + 8, point.x + 12), area.maxX - width - 8)
        let above = point.y - height - 10
        let y = max(area.minY + 4, min(above >= area.minY ? above : point.y + 14, area.maxY - height - 4))
        let rect = NSRect(x: left, y: y, width: width, height: height)
        NSColor.windowBackgroundColor.setFill(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        NSColor.separatorColor.setStroke(); NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).stroke()
        (detail as NSString).draw(in: rect.insetBy(dx: 10, dy: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
    }
    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hover = interval(at: point).map { (point, $0) }; needsDisplay = true
    }
    public override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
    public override func mouseDown(with event: NSEvent) { dragging = true; hover = nil }
    public override func mouseDragged(with event: NSEvent) {
        guard dragging else { return }
        viewport.pan(by: -Double(event.deltaX / plotWidth) * viewport.span); invalidateChart()
    }
    public override func mouseUp(with event: NSEvent) { dragging = false }
    public override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        viewport.zoom(by: max(0.1, 1 + Double(event.magnification)), anchor: Double((point.x - labelWidth) / plotWidth)); invalidateChart()
    }
    public override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || event.modifierFlags.contains(.shift) {
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            viewport.pan(by: -Double(delta / plotWidth) * viewport.span); invalidateChart()
        } else { super.scrollWheel(with: event) }
    }
}
