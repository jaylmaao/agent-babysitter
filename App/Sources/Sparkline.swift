import AppKit

/// Tiny 7-day cost trend for the menu bar. Drawn as a template image so it
/// follows the menu bar's light/dark appearance, and embedded in the label's
/// concatenated Text (MenuBarExtra labels render reliably only as one Text,
/// which fortunately can interpolate images).
enum Sparkline {

    /// nil when there's nothing worth drawing (fewer than 2 days, or all
    /// zeros) — callers fall back to the plain status label.
    static func image(dailyDollars: [Double],
                      barWidth: CGFloat = 3, gap: CGFloat = 1.5,
                      height: CGFloat = 11) -> NSImage? {
        let values = Array(dailyDollars.suffix(7))
        guard values.count >= 2, let peak = values.max(), peak > 0 else { return nil }
        let width = CGFloat(values.count) * (barWidth + gap) - gap
        let image = NSImage(size: NSSize(width: width, height: height),
                            flipped: false) { rect in
            for (index, value) in values.enumerated() {
                // A floor keeps zero-spend days visible as a tick, so the
                // trend reads as "quiet day", not "missing data".
                let barHeight = max(1.5, CGFloat(value / peak) * rect.height)
                let bar = NSRect(x: CGFloat(index) * (barWidth + gap), y: 0,
                                 width: barWidth, height: barHeight)
                NSColor.black.setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
