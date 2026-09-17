import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SkaldSettings
    @State private var deepLKey  = ""
    @State private var claudeKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Languages") {
                    Picker("I write in", selection: binding(\.primaryLanguage)) {
                        ForEach(Language.allCases) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Picker("Translate to", selection: binding(\.secondaryLanguage)) {
                        ForEach(Language.allCases) { Text("\($0.flag) \($0.displayName)").tag($0) }
                    }
                    Text("Direction is detected automatically: text in \(settings.secondaryLanguage.displayName) is translated back into \(settings.primaryLanguage.displayName).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(Language.allCases.filter { LetterLayout.hasLayout($0) }) { lang in
                        Toggle(isOn: Binding(
                            get: { settings.keyboardLanguages.contains(lang) },
                            set: { on in
                                var list = settings.keyboardLanguages
                                if on { if !list.contains(lang) { list.append(lang) } }
                                else if list.count > 1 { list.removeAll { $0 == lang } }
                                settings.keyboardLanguages = list
                            })) {
                            Text("\(lang.flag) \(lang.displayName)")
                        }
                    }
                } header: {
                    Text("Keyboard layouts")
                } footer: {
                    Text("The language key on the Skald keyboard cycles through these, so you can remove the matching system keyboards.")
                }

                Section {
                    Toggle("Auto-correction", isOn: binding(\.autocorrectEnabled))
                    Toggle("Suggestions", isOn: binding(\.suggestionsEnabled))
                    Toggle("Haptic feedback", isOn: binding(\.hapticsEnabled))
                    Button("Reset learned words", role: .destructive) {
                        settings.learnedWords = [:]
                        settings.learnedFixes = [:]
                    }
                } header: {
                    Text("Typing")
                } footer: {
                    Text("Corrections use the system spelling dictionaries for the layout language. Backspace right after a correction restores what you typed. Haptics need Allow Full Access.")
                }

                Section("Engine") {
                    Picker("Engine", selection: binding(\.engine)) {
                        ForEach(Engine.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if settings.engine == .claude {
                    Section("Claude") {
                        SecureField("Anthropic API key (sk-ant-…)", text: $claudeKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { settings.setApiKey(claudeKey, for: .claude) }
                            .onChange(of: claudeKey) { _, v in settings.setApiKey(v, for: .claude) }
                        Picker("Model", selection: binding(\.claudeModel)) {
                            ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0) }
                        }
                        keyStatus(for: .claude)
                    }

                    Section {
                        Toggle("Adapt style", isOn: binding(\.adaptStyleEnabled))
                        if settings.adaptStyleEnabled {
                            ForEach(Tone.allCases) { tone in
                                Button { settings.tone = tone } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: tone.symbolName)
                                            .foregroundStyle(tone.color)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(tone.displayName).foregroundStyle(.primary)
                                            Text(tone.subtitle).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if settings.tone == tone {
                                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Style")
                    } footer: {
                        Text("Only Claude can change register. Other engines translate as-is.")
                    }
                }

                if settings.engine == .deepl {
                    Section("DeepL") {
                        SecureField("DeepL API key", text: $deepLKey)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: deepLKey) { _, v in settings.setApiKey(v, for: .deepl) }
                        keyStatus(for: .deepl)
                        Text("Keys ending in :fx use the free api-free.deepl.com endpoint.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if settings.engine == .apple {
                    Section {
                        Text("Runs fully offline on your device. The first translation for a language pair asks you to download that pack — do it here in the app; the keyboard can't show the download prompt.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Link("Mac version & support", destination: URL(string: "https://panic-kit.com/skald")!)
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                deepLKey  = settings.apiKey(for: .deepl)  ?? ""
                claudeKey = settings.apiKey(for: .claude) ?? ""
            }
        }
    }

    private func keyStatus(for engine: Engine) -> some View {
        HStack {
            Image(systemName: settings.hasApiKey(for: engine) ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .foregroundStyle(settings.hasApiKey(for: engine) ? .green : .orange)
            Text(settings.hasApiKey(for: engine) ? "Key saved to the shared keychain" : "No key yet")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<SkaldSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }
}
