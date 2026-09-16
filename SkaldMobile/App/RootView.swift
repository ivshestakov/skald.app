import SwiftUI
import UIKit

struct RootView: View {
    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "keyboard") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .background(AppleTranslatorHost())
    }
}

/// Registers a live UIView as the host for Apple on-device translation
/// requests made from the app (see `AppleTranslator.hostView`).
struct AppleTranslatorHost: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        AppleTranslator.hostView = v
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {
        AppleTranslator.hostView = uiView
    }
}

/// Whether the Skald keyboard is enabled in Settings → Keyboards. iOS writes
/// enabled keyboards' bundle IDs into the standard defaults `AppleKeyboards`.
enum KeyboardStatus {
    static var isEnabled: Bool {
        let list = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String] ?? []
        return list.contains(SkaldSettings.keyboardBundleID)
    }
}
