import AppKit

/// Horizontal slider with a coloured gradient track, snapping to the
/// `Tone` values. Draws the track, thumb, and per-step tick labels in
/// its own `draw(_:)` so the gradient and typography come through
/// cleanly — NSSlider's native appearance fights this kind of custom
/// tinting.
final class ToneSlider: NSControl {

    private let tones: [Tone] = Tone.allCases

    /// Fired on every step change (drag across segment boundaries or tap).
    var onChange: ((Tone) -> Void)?

    private var currentIndex: Int = 0 {
        didSet {
            guard currentIndex != oldValue else { return }
            needsDisplay = true
            onChange?(tones[currentIndex])
        }
    }

    var selectedTone: Tone {
        get { tones[currentIndex] }
        set {
            currentIndex = newValue.rawValue
            needsDisplay = true
        }
    }

    // Visual sizing
    private let trackHeight:   CGFloat = 16
    private let thumbDiameter: CGFloat = 24
    private let labelBlock:    CGFloat = 14    // reserved for the bottom tick label
    private let trackLabelGap: CGFloat = 10    // breathing room between track and labels

    override var intrinsicContentSize: NSSize {
        NSSize(width: 440, height: thumbDiameter + trackLabelGap + labelBlock + 4)
    }

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: drawing

    private var trackRect: NSRect {
        NSRect(
            x: thumbDiameter / 2,
            y: labelBlock + trackLabelGap + (thumbDiameter - trackHeight) / 2,
            width: bounds.width - thumbDiameter,
            height: trackHeight
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let track = trackRect

        // --- Gradient track
        let colors    = tones.map { $0.color.cgColor }
        let locations = tones.indices.map { CGFloat($0) / CGFloat(tones.count - 1) }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: locations
        ) else { return }

        let trackPath = NSBezierPath(roundedRect: track,
                                     xRadius: track.height / 2,
                                     yRadius: track.height / 2)
        ctx.saveGState()
        trackPath.addClip()
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: track.minX, y: track.midY),
            end:   CGPoint(x: track.maxX, y: track.midY),
            options: []
        )
        ctx.restoreGState()

        NSColor(white: 0, alpha: 0.12).setStroke()
        trackPath.lineWidth = 0.5
        trackPath.stroke()

        // --- Thumb
        let thumbCX = stepCenterX(for: currentIndex)
        let thumbRect = NSRect(
            x: thumbCX - thumbDiameter / 2,
            y: track.midY - thumbDiameter / 2,
            width: thumbDiameter,
            height: thumbDiameter
        )
        let thumbPath = NSBezierPath(ovalIn: thumbRect)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor.white.setFill()
        thumbPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let innerRect = thumbRect.insetBy(dx: 6, dy: 6)
        tones[currentIndex].color.setFill()
        NSBezierPath(ovalIn: innerRect).fill()

        // --- Tick labels along the bottom
        let baselineY: CGFloat = 0
        for (idx, tone) in tones.enumerated() {
            let cx = stepCenterX(for: idx)
            let isActive = idx == currentIndex

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(
                    ofSize: 10,
                    weight: isActive ? .bold : .medium
                ),
                // Active label uses the tone's *text* colour so it stays
                // readable on both light and dark Settings backgrounds
                // (raw tone.color fails on one of the two modes).
                .foregroundColor: isActive
                    ? tone.textColor
                    : NSColor.secondaryLabelColor.withAlphaComponent(0.75),
                .kern: 0.5,
            ]
            let str = NSAttributedString(string: tone.shortLabel, attributes: attrs)
            let size = str.size()
            // Clamp to visible area so end labels don't clip off the edge.
            let x = max(0, min(bounds.width - size.width, cx - size.width / 2))
            str.draw(at: NSPoint(x: x, y: baselineY))
        }
    }

    private func stepCenterX(for index: Int) -> CGFloat {
        let track = trackRect
        let steps = CGFloat(tones.count - 1)
        let t = CGFloat(index) / steps
        return track.minX + track.width * t
    }

    // MARK: input

    override func mouseDown(with event: NSEvent)    { updateFromEvent(event) }
    override func mouseDragged(with event: NSEvent) { updateFromEvent(event) }

    private func updateFromEvent(_ event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let track = trackRect
        let local = pt.x - track.minX
        let t = max(0, min(1, local / track.width))
        let raw = Int((t * CGFloat(tones.count - 1)).rounded())
        currentIndex = max(0, min(tones.count - 1, raw))
    }

    override func accessibilityLabel() -> String? {
        "Translation tone: \(tones[currentIndex].displayName)"
    }
}
