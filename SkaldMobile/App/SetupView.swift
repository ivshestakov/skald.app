import SwiftUI
import UIKit

struct SetupView: View {
    @EnvironmentObject private var settings: SkaldSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = KeyboardStatus.isEnabled
    @State private var tryText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: enabled ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.title)
                            .foregroundStyle(enabled ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(enabled ? "Skald keyboard is enabled" : "Skald keyboard is not enabled yet")
                                .font(.headline)
                            Text(enabled
                                 ? "Hold 🌐 on any keyboard and pick Skald."
                                 : "Follow the steps below, then come back.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("Enable the keyboard") {
                    step(1, "Open **Settings → General → Keyboard → Keyboards**.")
                    step(2, "Tap **Add New Keyboard…** and choose **Skald**.")
                    step(3, "Tap **Skald** in the list and turn on **Allow Full Access** — needed for Google, DeepL and Claude. The Apple engine works without it.")
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "arrow.up.forward.app")
                    }
                }

                Section("How it works") {
                    step("⌨️", "Type your message with the Skald keyboard in any app — it has \(settings.primaryLanguage.displayName) and \(settings.secondaryLanguage.displayName) layouts.")
                    step("🏳️", "Tap the **flag** at the top right, type, then hit the blue **↑**: the translation goes into the app. Swipe the space bar to switch layouts.")
                    step("↩️", "Not happy? **Undo** brings your original back.")
                }

                Section("Try it") {
                    TextField("Switch to Skald with 🌐 and type here", text: $tryText, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Text("Full Access lets the keyboard reach the internet. Skald sends only the text you translate, only to the engine you picked, and never stores or forwards anything else.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Skald")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { enabled = KeyboardStatus.isEnabled }
            }
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        step(String(n), text)
    }

    private func step(_ badge: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(badge)
                .font(.subheadline.weight(.semibold))
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
