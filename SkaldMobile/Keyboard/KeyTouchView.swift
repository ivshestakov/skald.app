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

    func makeUIView(context: Context) -> KeyTouchUIView {
        let v = KeyTouchUIView()
        v.model = model
        v.frames = frames
        return v
    }

    func updateUIView(_ uiView: KeyTouchUIView, context: Context) {
        uiView.model = model
        uiView.frames = frames
    }
}

final class KeyTouchUIView: UIView {

    weak var model: KeyboardModel?
    var frames: [Key: CGRect] = [:]

    private final class TouchState {
        let startKey: Key
        var currentKey: Key?
        var lastPoint: CGPoint
        var longPressWork: DispatchWorkItem?
        var popupShown = false
        var cursorMode = false
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

    private func key(at p: CGPoint) -> Key? {
        // Keys are laid out with gaps; treat the gap as belonging to the
        // nearest key so slightly-off taps still register, like the system.
        if let exact = frames.first(where: { $0.value.contains(p) })?.key { return exact }
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
        case .char, .language, .space: delay = 0.35
        case .backspace: delay = 0.4
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
            guard let state = self.touches[t] else { continue }
            let p = t.location(in: self)
            if state.popupShown {
                model.updatePopupSelection(x: p.x)
            } else if state.cursorMode {
                // Like the system trackpad: ~8 pt per character, ~28 pt per
                // line, and a line move only when the finger is clearly
                // going up/down (otherwise sideways drift would change lines).
                let dx = p.x - state.lastPoint.x, dy = p.y - state.lastPoint.y
                if abs(dy) > abs(dx) * 1.5 {
                    state.cursorAccumulatorY += dy
                    state.cursorAccumulator = 0
                } else {
                    state.cursorAccumulator += dx
                    state.cursorAccumulatorY *= 0.5
                }
                let step: CGFloat = 8, stepY: CGFloat = 28
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
            if state.popupShown {
                model.commitPopup()
                model.keyReleased(state.startKey, releasedOn: nil, start: state.startKey)
            } else if state.cursorMode {
                model.endCursorMode()
                model.keyReleased(state.startKey, releasedOn: nil, start: state.startKey)
            } else if state.swiped {
                model.keyReleased(state.startKey, releasedOn: nil, start: state.startKey)
            } else {
                model.keyReleased(state.startKey, releasedOn: state.currentKey, start: state.startKey)
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
