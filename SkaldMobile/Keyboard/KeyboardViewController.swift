import Combine
import SwiftUI
import UIKit

/// Container view that lets UIKit play the standard key click.
final class ClickableInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

final class KeyboardViewController: UIInputViewController, KeyboardHost {

    private let model = KeyboardModel()
    private var hosting: UIHostingController<KeyboardView>?
    private var heightConstraint: NSLayoutConstraint?
    private var cancellables: Set<AnyCancellable> = []

    private var keyboardHeight: CGFloat { KeyboardMetrics.totalHeight(translateMode: model.translateMode) }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Swap in an input view that plays the system key click; the system
        // still owns its width, we only pin the height below.
        inputView = ClickableInputView(frame: .zero, inputViewStyle: .keyboard)
        model.host = self
        AppleTranslator.hostView = view

        let hc = UIHostingController(rootView: KeyboardView(model: model))
        hc.view.backgroundColor = .clear
        addChild(hc)
        view.addSubview(hc.view)
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hc.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hc.view.topAnchor.constraint(equalTo: view.topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hc.didMove(toParent: self)
        hosting = hc

        // Translate mode adds the composer strip: grow/shrink the keyboard.
        model.$translateMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let h = self.heightConstraint else { return }
                h.constant = self.keyboardHeight
                UIView.animate(withDuration: 0.2) { self.view.superview?.layoutIfNeeded() }
            }
            .store(in: &cancellables)
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        guard heightConstraint == nil, view.window != nil else { return }
        let h = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        h.priority = .init(999)
        h.isActive = true
        heightConstraint = h
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyAppearance()
        model.textDidChange()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        applyAppearance()
        model.textDidChange()
    }

    private func applyAppearance() {
        // Respect the host field's requested keyboard appearance.
        switch textDocumentProxy.keyboardAppearance {
        case .dark:  overrideUserInterfaceStyle = .dark
        case .light: overrideUserInterfaceStyle = .light
        default:     overrideUserInterfaceStyle = .unspecified
        }
    }

    // MARK: KeyboardHost

    var proxy: UITextDocumentProxy { textDocumentProxy }

    func playClick() {
        UIDevice.current.playInputClick()
    }

    // UIFeedbackGenerator only fires inside a keyboard extension when the
    // user granted Full Access; without it the call is a silent no-op.
    private lazy var haptic: UIImpactFeedbackGenerator = {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.prepare()
        return g
    }()

    func playHaptic() {
        guard hasFullAccess else { return }
        haptic.impactOccurred(intensity: 0.8)
        haptic.prepare()
    }
}
