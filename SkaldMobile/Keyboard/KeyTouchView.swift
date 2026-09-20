import SwiftUI
import UIKit

/// Multi-touch input layer over the key grid. SwiftUI gestures are
/// single-touch and per-view, which breaks two-thumb typing and finger
/// glides; real keyboards track every UITouch against key frames instead.
///
/// The SwiftUI keys report their frames (in the "keyboard" coordinate space,
/// which equals this view's bounds) and stay purely visual. This view owns:
/// press/release, glide to another key, long-press pop-ups, backspace
/// repeat, and the space-bar cursor trackpad.
struct KeyTouchView: UIViewRepresentable {
    @ObservedObject var model: KeyboardModel
    let frames: [Key: CGRect]
    let bias: [Character: Double]

    func makeUIView(context: Context) -> KeyTouchUIView {
        let v = KeyTouchUIView()
        v.model = model
        v.frames = frames
        v.letterBias = bias
        return v
    }

    func updateUIView(_ uiView: KeyTouchUIView, context: Context) {
        uiView.model = model
        uiView.frames = frames
        uiView.letterBias = bias
    }
}

final class KeyTouchUIView: UIView {

    weak var model: KeyboardModel?
    var frames: [Key: CGRect] = [:] { didSet { if frames != oldValue { pitchCache = nil } } }
    /// Next-letter likelihood; a likely key's hidden hit area grows by up to
    /// 6 pt per side (Apple's dynamic key targets — the visuals never change).
    var letterBias: [Character: Double] = [:]

    private final class TouchState {
        let startKey: Key
        var currentKey: Key?
        var lastPoint: CGPoint
        var longPressWork: DispatchWorkItem?
        var popupShown = false
        var cursorMode = false
        var committed = false            // rollover: typed already by a second touch-down
        var popupCancelled = false
        var cursorAccumulator: CGFloat = 0
        var cursorAccumulatorY: CGFloat = 0
        var swiped = false
        let startPoint: CGPoint
        init(startKey: Key, point: CGPoint) { self.startKey = startKey; self.currentKey = startKey; self.lastPoint = point; self.startPoint = point }
    }

    private var touches: [UITouch: TouchState] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Only claim touches that land on a key (or anywhere while a pop-up /
    /// cursor mode owns the finger) so the top bar and emoji grid keep
    /// working as ordinary SwiftUI controls.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if !touches.isEmpty { return true }
        return key(at: point) != nil
    }

    /// Centre-to-centre distance between neighbouring letter keys (x: within
    /// a row, y: between rows), derived from the reported frames.
    private var pitchCache: (x: CGFloat, y: CGFloat)?
    private var pitch: (x: CGFloat, y: CGFloat) {
        if let p = pitchCache { return p }
        var xs: [CGFloat] = [], rowYs = Set<Int>()
        let letters = frames.filter { if case .char(let g) = $0.key { return g.count == 1 } else { return false } }.values
        for (_, fs) in Swift.Dictionary(grouping: letters, by: { Int($0.midY.rounded()) }) {
            let mids = fs.map(\.midX).sorted()
            for i in mids.indices.dropFirst() { xs.append(mids[i] - mids[i - 1]) }
        }
        for f in letters { rowYs.insert(Int(f.midY.rounded())) }
        let ys = rowYs.sorted()
        let dys = ys.indices.dropFirst().map { CGFloat(ys[$0] - ys[$0 - 1]) }
        let p = (x: xs.isEmpty ? 36 : xs.sorted()[xs.count / 2], y: dys.isEmpty ? 54 : dys.sorted()[dys.count / 2])
        pitchCache = p
        return p
    }

    /// Gaussian touch likelihood (0…1) of the point for every letter key
    /// within reach, in key-pitch units with σ = 0.45 pitch — the touch
    /// model behind Apple's corrector. The corrector weighs a substitution
    /// by the ratio of the intended key's likelihood to the typed key's, so
    /// a tap on a key boundary makes the neighbour as likely as the key that
    /// registered, and a tap in the middle of a key rules its neighbours
    /// out (≈ 0.09) and the rest of the keyboard out entirely.
    private func touchLikelihood(at p: CGPoint) -> [Character: Double] {
        let (px, py) = pitch
        var out: [Character: Double] = [:]
        for (k, f) in frames {
            guard case .char(let g) = k, g.count == 1, let ch = g.lowercased().first, ch.isLetter else { continue }
            let dx = Double((p.x - f.midX) / px), dy = Double((p.y - f.midY) / py)
            let likelihood = exp(-(dx * dx + dy * dy) / (2 * 0.45 * 0.45))
            if likelihood >= 0.001 { out[ch] = likelihood }
        }
        return out
    }

    /// Where the finger meant to land: the touch-down point, unless the
    /// finger slid to another key on purpose (then the release point).
    private func aimPoint(_ state: TouchState) -> CGPoint {
        state.currentKey == state.startKey ? state.startPoint : state.lastPoint
    }

    private func key(at p: CGPoint) -> Key? {
        // 1. A likely next letter claims the touch when it lands in its
        //    expanded (hidden) hit area, even if that is inside a neighbour.
        var expandedHit: (Key, Double)?
        if !letterBias.isEmpty {
            for (k, f) in frames {
                guard case .char(let g) = k, let ch = g.lowercased().first, let b = letterBias[ch], b > 0.15 else { continue }
                let grown = f.insetBy(dx: -6 * b, dy: -4 * b)
                if grown.contains(p), expandedHit == nil || b > expandedHit!.1 { expandedHit = (k, b) }
            }
        }
        // 2. Otherwise the key under the finger; gaps belong to the nearest key.
        let exact = frames.first(where: { $0.value.contains(p) })?.key
        if let (k, b) = expandedHit {
            // Only override the exact key when the finger is near its edge.
            if let exact, exact != k, let f = frames[exact] {
                let inset = f.insetBy(dx: 6 * b, dy: 4 * b)
                if inset.contains(p) { return exact }
            }
            return k
        }
        if let exact { return exact }
        var best: (Key, CGFloat)?
        for (k, f) in frames {
            let dx = max(f.minX - p.x, 0, p.x - f.maxX)
            let dy = max(f.minY - p.y, 0, p.y - f.maxY)
            let d = dx * dx + dy * dy
            if d <= 8 * 8, best == nil || d < best!.1 { best = (k, d) }
        }
        return best?.0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for t in touches {
            let p = t.location(in: self)
            guard let key = key(at: p) else { continue }
            // Rollover typing: a new touch-down commits any character key still
            // held by another finger, so letters land in touch-down order.
            for (_, other) in self.touches where !other.committed && !other.popupShown && !other.cursorMode {
                if case .char? = other.currentKey {
                    other.longPressWork?.cancel()
                    other.committed = true
                    model.keyReleased(other.startKey, releasedOn: other.currentKey, start: other.startKey,
                                      proximity: touchLikelihood(at: aimPoint(other)))
                }
            }
            let state = TouchState(startKey: key, point: p)
            self.touches[t] = state
            model.keyDown(key)
            scheduleLongPress(for: t, state: state, key: key)
        }
    }

    private func scheduleLongPress(for touch: UITouch, state: TouchState, key: Key) {
        state.longPressWork?.cancel()
        let delay: Double
        switch key {
        case .char, .language: delay = 0.45
        case .space: delay = 0.45
        case .backspace: delay = 0.5
        default: return
        }
        let work = DispatchWorkItem { [weak self, weak model] in
            guard let self, let model, self.touches[touch] === state, state.currentKey == key else { return }
            let frame = self.frames[key] ?? .zero
            switch key {
            case .space:
                if model.beginCursorMode() { state.cursorMode = true }
            case .backspace:
                model.startBackspaceRepeat()
            default:
                if model.longPress(key, frame: frame) { state.popupShown = true }
            }
        }
        state.longPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for t in touches {
            guard let state = self.touches[t], !state.committed else { continue }
            let p = t.location(in: self)
            if state.popupShown {
                // Sliding well below the key cancels the callout (system rule).
                if let f = frames[state.startKey], p.y > f.maxY + 40 {
                    state.popupShown = false
                    state.popupCancelled = true
                    model.cancelPopup()
                } else {
                    model.updatePopupSelection(x: p.x)
                }
            } else if state.popupCancelled {
                // finger is lifting away: nothing more to do
            } else if state.cursorMode {
                // Like the system trackpad: relative movement with a gain that
                // grows with finger speed (~6 pt per character when slow),
                // ~28 pt per line, and a line move only when the finger is
                // clearly going up/down.
                let dx = p.x - state.lastPoint.x, dy = p.y - state.lastPoint.y
                let gain = min(3, max(1, abs(dx) / 8))
                if abs(dy) > abs(dx) * 1.5 {
                    state.cursorAccumulatorY += dy
                    state.cursorAccumulator = 0
                } else {
                    state.cursorAccumulator += dx * gain
                    state.cursorAccumulatorY *= 0.5
                }
                let step: CGFloat = 6, stepY: CGFloat = 28
                let n = Int(state.cursorAccumulator / step)
                if n != 0 {
                    model.moveCursor(by: n)
                    state.cursorAccumulator -= CGFloat(n) * step
                }
                let m = Int(state.cursorAccumulatorY / stepY)
                if m != 0 {
                    model.moveCursorLines(m > 0 ? 1 : -1)
                    state.cursorAccumulatorY -= CGFloat(m) * stepY
                }
            } else if state.startKey == .space, !state.swiped {
                // Quick horizontal swipe on the space bar switches the layout.
                let dx = p.x - state.startPoint.x
                if abs(dx) > 36, abs(p.y - state.startPoint.y) < 30 {
                    state.swiped = true
                    state.longPressWork?.cancel()
                    model.swipeLanguage(dx < 0 ? 1 : -1)
                }
            } else if state.swiped {
                // ignore further movement
            } else {
                let k = key(at: p)
                if k != state.currentKey {
                    // Leaving the key cancels its long-press; backspace repeat
                    // keeps going while the finger stays down.
                    if state.startKey != .backspace { state.longPressWork?.cancel() }
                    model.keyMoved(from: state.currentKey, to: k, start: state.startKey)
                    state.currentKey = k
                    if let k, state.startKey != .backspace, k == state.startKey {
                        scheduleLongPress(for: t, state: state, key: k)
                    }
                }
            }
            state.lastPoint = p
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for t in touches {
            guard let state = self.touches.removeValue(forKey: t) else { continue }
            state.longPressWork?.cancel()
            if state.committed { continue }
            if state.popupCancelled {
                model.keyReleased(state.startKey, releasedOn: nil, start: state.startKey)
            } else if state.popupShown {
                model.commitPopup()
                model.keyReleased(state.startKey, releasedOn: nil, start: state.startKey)
            } else if state.cursorMode {
                model.endCursorMode()
                model.keyReleased(state.startKey, releasedOn: nil, start: state.startKey)
            } else if state.swiped {
                model.keyReleased(state.startKey, releasedOn: nil, start: state.startKey)
            } else {
                let prox: [Character: Double]? = { if case .char? = state.currentKey { return touchLikelihood(at: aimPoint(state)) } else { return nil } }()
                model.keyReleased(state.startKey, releasedOn: state.currentKey, start: state.startKey, proximity: prox)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model else { return }
        for t in touches {
            guard let state = self.touches.removeValue(forKey: t) else { continue }
            state.longPressWork?.cancel()
            if state.cursorMode { model.endCursorMode() }
            model.cancelPopup()
            model.keyCancelled(state.startKey, current: state.currentKey)
        }
    }
}
