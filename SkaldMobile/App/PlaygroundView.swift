import SwiftUI

/// In-app translator: a place to test engines and keys, and a text field
/// to try the keyboard itself once it's enabled.
struct PlaygroundView: View {
    @EnvironmentObject private var settings: SkaldSettings
    @State private var input = ""
    @State private var output = ""
    @State private var errorText: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Type something…", text: $input, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                    HStack {
                        Button(action: run) {
                            if busy { ProgressView() } else { Label("Translate", systemImage: "arrow.right.circle.fill") }
                        }
                        .disabled(busy || input.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        Text(directionLabel).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("\(settings.engine.shortName) engine")
                } footer: {
                    Text("Once the keyboard is enabled, switch to it here with 🌐 to try Translate in place.")
                }

                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }

                if !output.isEmpty {
                    Section("Translation") {
                        Text(output).textSelection(.enabled)
                        Button {
                            UIPasteboard.general.string = output
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }
                }

                if !settings.history.isEmpty {
                    Section("Recent") {
                        ForEach(settings.history.prefix(20)) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.source).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                Text(item.target).lineLimit(3)
                            }
                            .contextMenu {
                                Button("Copy translation") { UIPasteboard.general.string = item.target }
                            }
                        }
                        Button("Clear history", role: .destructive) { settings.history = [] }
                    }
                }
            }
            .navigationTitle("Translate")
        }
    }

    private var directionLabel: String {
        let pair = LanguageDetector.pair(for: input, settings: settings)
        return "\(pair.source.flag) → \(pair.target.flag)"
    }

    private func run() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        busy = true; errorText = nil; output = ""
        focused = false
        Task {
            do {
                let result = try await TranslationService.translate(text, settings: settings)
                output = result
                settings.recordHistory(source: text, target: result, engine: settings.engine)
            } catch {
                let f = TranslateFailure(error, engine: settings.engine)
                errorText = "\(f.title). \(f.detail)"
                NSLog("Skald: translate error: %@", String(describing: error))
            }
            busy = false
        }
    }
}
