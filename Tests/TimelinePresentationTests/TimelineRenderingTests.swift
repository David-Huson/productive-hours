import AppKit
import Testing
import ActivityCore
@testable import TimelinePresentation

@Test @MainActor func denseTimelineRenderingAndHitTestingStayBounded() throws {
    _ = NSApplication.shared
    var settings = AppSettings(); settings.timezone = "UTC"
    let start = Date(timeIntervalSince1970: 1_793_577_600)
    let source = Source(app: "com.example.Editor", productivity: .productive)
    let rows = (0..<200_000).map { i in
        Interval(start: start.epochMS + Int64(i * 3000), end: start.epochMS + Int64((i + 1) * 3000),
                 source: source, activity: i.isMultiple(of: 2) ? .active : .passive)
    }
    let began = ProcessInfo.processInfo.systemUptime
    let days = ActivityTimeline.days(intervals: rows, from: start, through: start.addingTimeInterval(6 * 86400), calendar: settings.calendar)
    let preparation = ProcessInfo.processInfo.systemUptime - began
    let view = TimelineDrawingView(frame: NSRect(x: 0, y: 0, width: 1100, height: 534))
    view.days = days; view.settings = settings
    let renderStart = ProcessInfo.processInfo.systemUptime
    let image = view.renderBase()
    let rendering = ProcessInfo.processInfo.systemUptime - renderStart
    let hitStart = ProcessInfo.processInfo.systemUptime
    for i in 0..<10_000 { _ = view.interval(at: NSPoint(x: 166 + CGFloat(i % 922), y: 45)) }
    let hitTesting = ProcessInfo.processInfo.systemUptime - hitStart
    print("Timeline benchmark: 200k intervals; prepare=\(preparation)s render=\(rendering)s 10k hits=\(hitTesting)s")
    #expect(preparation < 3)
    #expect(rendering < 0.5)
    #expect(hitTesting < 0.2)
    #expect(view.interval(at: NSPoint(x: 200, y: 45)) != nil)
    #expect(view.interval(at: NSPoint(x: 100, y: 45)) == nil)
    let redrawStart = ProcessInfo.processInfo.systemUptime
    for _ in 0..<10 {
        view.viewport.zoom(by: 1.1)
        _ = view.renderBase()
    }
    let redrawAverage = (ProcessInfo.processInfo.systemUptime - redrawStart) / 10
    print("Timeline dense zoom redraw average=\(redrawAverage)s")
    #expect(redrawAverage < 0.1)
    let bitmap = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/worktempo-timeline-render.png"))
}

@Test @MainActor func timelineMixedStatesAndTooltipRender() throws {
    _ = NSApplication.shared
    var settings = AppSettings(); settings.timezone = "UTC"
    let start = Date(timeIntervalSince1970: 1_793_577_600)
    let categories: [(ProductivityClass, ActivityState)] = [(.productive, .active), (.productive, .passive), (.unproductive, .active), (.unproductive, .passive), (.undefined, .active), (.undefined, .passive), (.ignored, .active), (.productive, .inactive), (.undefined, .unknown)]
    var rows: [Interval] = []
    for day in 0..<4 {
        for (index, pair) in categories.enumerated() {
            let time = start.epochMS + Int64(day * 86_400_000 + 9 * 3_600_000 + index * 3_000_000)
            rows.append(Interval(start: time, end: time + 2_400_000,
                source: Source(app: "com.example.Editor", productivity: pair.0), activity: pair.1,
                reason: pair.1 == .unknown ? "paused" : "observed"))
        }
    }
    let view = TimelineDrawingView(frame: NSRect(x: 0, y: 0, width: 1100, height: 312))
    view.days = ActivityTimeline.days(intervals: rows, from: start, through: start.addingTimeInterval(3 * 86400), calendar: settings.calendar)
    view.settings = settings
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    // Simulate the same pointer path used by the actual view, with no external app interaction.
    let event = try #require(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 520, y: 45), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
    view.mouseMoved(with: event)
    let began = ProcessInfo.processInfo.systemUptime
    for _ in 0..<100 { view.cacheDisplay(in: view.bounds, to: bitmap) }
    let average = (ProcessInfo.processInfo.systemUptime - began) / 100
    print("Timeline cached tooltip redraw average=\(average)s")
    #expect(average < 0.02)
    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/worktempo-timeline-tooltip.png"))
}
