import SwiftUI
import UIKit

/// What the model needs from the input view controller.
@MainActor
protocol KeyboardHost: AnyObject {
    var proxy: UITextDocumentProxy { get }
    var hasFullAccess: Bool { get }
    var needsInputModeSwitchKey: Bool { get }
    func advanceToNextInputMode()
    func playClick()
}

enum ShiftState { case off, on, caps }

struct UndoRecord {
    let original: String        // text to put back into the document
    let translated: String      // text to delete from the document
    var composerRestore: String? // translate mode: source to put back in the composer
}

enum TranslateStatus: Equatable {
    case idle
    case busy
    case done
    case error(String)
}

/// Long-press popup: character alternates, or the keyboard-language picker.
struct KeyPopup: Equatable {
    enum Kind: Equatable { case characters, languages }
    let kind: Kind
    let options: [String]
    let keyFrame: CGRect       // in the keyboard's coordinate space
    var selected: Int = 0
}

@MainActor
final class KeyboardModel: ObservableObject {

    weak var host: KeyboardHost?
    let settings = SkaldSettings.shared

    @Published var page: KeyboardPage = .letters
    @Published var shift: ShiftState = .on
    @Published var languageIndex = 0
    @Published var status: TranslateStatus = .idle
    @Published var direction: LanguagePair
    @Published private(set) var undo: UndoRecord?
    @Published var popup: KeyPopup?

    // Translate mode: keystrokes go into `composer`, `preview` is the live
    // translation, Return inserts the preview into the document.
    @Published var translateMode = false
    @Published var composer = ""
    @Published var preview = ""
    @Published var previewBusy = false
    private var previewFor = ""
    private var previewTask: Task<Void, Never>?

    @Published var emojiCategory: String = ""

    private var shiftIsAuto = true
    private var lastShiftTap: Date = .distantPast
    private var repeatTimer: Timer?
    private var task: Task<Void, Never>?

    init() {
        let s = SkaldSettings.shared
        direction = LanguagePair(source: s.primaryLanguage, target: s.secondaryLanguage)
        emojiCategory = s.recentEmoji.isEmpty ? (EmojiData.categories.first?.id ?? "") : "recent"
    }

    // MARK: - Languages / layouts

    var keyboardLanguages: [Language] { settings.keyboardLanguages }
    var currentLanguage: Language {
        let langs = keyboardLanguages
        return langs[min(languageIndex, langs.count - 1)]
    }
    var currentLayout: LetterLayout { LetterLayout.forLanguage(currentLanguage) }
    var hasLanguageKey: Bool { keyboardLanguages.count > 1 }
    var showsGlobe: Bool { host?.needsInputModeSwitchKey ?? true }

    func nextLanguage() {
        languageIndex = (languageIndex + 1) % keyboardLanguages.count
    }

    var returnLabel: String {
        if translateMode, !composer.trimmingCharacters(in: .whitespaces).isEmpty { return "insert" }
        switch host?.proxy.returnKeyType ?? .default {
        case .send:     return "send"
        case .search:   return "search"
        case .go:       return "go"
        case .done:     return "done"
        case .next:     return "next"
        case .join:     return "join"
        case .continue: return "continue"
        default:        return "return"
        }
    }

    var showsTonePill: Bool { settings.engine == .claude && settings.adaptStyleEnabled }

    // MARK: - Key handling

    func tap(_ key: Key) {
        host?.playClick()
        switch key {
        case .char(let s):
            insert(s)
        case .shift:
            let now = Date()
            if now.timeIntervalSince(lastShiftTap) < 0.3 {
                shift = .caps
            } else {
                shift = shift == .off ? .on : .off
            }
            shiftIsAuto = false
            lastShiftTap = now
        case .backspace:
            backspaceOnce()
        case .space:
            insert(" ")
        case .ret:
            if translateMode, !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                commitComposer()
            } else {
                host?.proxy.insertText("\n")
                textDidChange()
            }
        case .numbers:  page = .numbers
        case .letters:  page = .letters
        case .symbols:  page = .symbols
        case .emoji:    page = .emoji
        case .globe:    host?.advanceToNextInputMode()
        case .language: nextLanguage()
        }
    }

    private func insert(_ raw: String) {
        var s = raw
        if page == .letters, shift != .off {
            s = s.uppercased()
            if shift == .on { shift = .off; shiftIsAuto = false }
        }
        insertRaw(s)
    }

    /// Inserts text where typing currently goes: the composer in translate
    /// mode, the document otherwise.
    private func insertRaw(_ s: String) {
        if translateMode {
            composer += s
            schedulePreview()
        } else {
            host?.proxy.insertText(s)
            clearUndoIfEdited()
        }
        textDidChange()
    }

    func insertEmoji(_ e: String) {
        host?.playClick()
        settings.recordEmoji(e)
        insertRaw(e)
    }

    private func backspaceOnce() {
        if translateMode, !composer.isEmpty {
            composer.removeLast()
            schedulePreview()
        } else {
            host?.proxy.deleteBackward()
            clearUndoIfEdited()
        }
        textDidChange()
    }

    /// Long-press on backspace: repeat until released.
    func startBackspaceRepeat() {
        stopBackspaceRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.backspaceOnce() }
        }
    }

    func stopBackspaceRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    private func clearUndoIfEdited() {
        if undo != nil { undo = nil; if status == .done { status = .idle } }
    }

    // MARK: - Context tracking

    /// Called by the controller on textDidChange and after our own edits.
    func textDidChange() {
        guard let proxy = host?.proxy else { return }
        if translateMode {
            updateAutoShift(before: composer)
            if composer.trimmingCharacters(in: .whitespaces).isEmpty {
                updateDirection(text: proxy.documentContextBeforeInput ?? "")
            }
        } else {
            let before = proxy.documentContextBeforeInput ?? ""
            updateAutoShift(before: before)
            updateDirection(text: (proxy.selectedText?.isEmpty == false) ? proxy.selectedText! : before)
        }
    }

    private func updateAutoShift(before: String) {
        guard page == .letters, shift != .caps else { return }
        let atSentenceStart: Bool = {
            let t = before
            if t.isEmpty { return true }
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            guard let last = trimmed.last, t.last?.isWhitespace == true || t.last?.isNewline == true else {
                return false
            }
            return ".!?".contains(last)
        }()
        if atSentenceStart, shift == .off {
            shift = .on; shiftIsAuto = true
        } else if !atSentenceStart, shift == .on, shiftIsAuto {
            shift = .off
        }
    }

    private func updateDirection(text: String) {
        let pair = LanguageDetector.pair(for: text, settings: settings)
        if pair.source != direction.source || pair.target != direction.target {
            direction = pair
        }
    }

    // MARK: - Long-press popups

    func showAlternates(for glyph: String, keyFrame: CGRect) -> Bool {
        let alts = KeyAlternates.alternates(for: glyph)
        guard !alts.isEmpty else { return false }
        let cased = page == .letters && shift != .off
        let options = ([glyph] + alts).map { cased ? $0.uppercased() : $0 }
        popup = KeyPopup(kind: .characters, options: options, keyFrame: keyFrame)
        return true
    }

    func showLanguages(keyFrame: CGRect) -> Bool {
        guard hasLanguageKey else { return false }
        popup = KeyPopup(kind: .languages,
                         options: keyboardLanguages.map { "\($0.flag) \($0.shortCode)" },
                         keyFrame: keyFrame,
                         selected: languageIndex)
        return true
    }

    /// Drag tracking while the popup is up: `x` is in keyboard coordinates.
    func updatePopupSelection(x: CGFloat, optionWidth: CGFloat, popupMinX: CGFloat) {
        guard var p = popup else { return }
        let idx = Int(((x - popupMinX) / optionWidth).rounded(.down))
        p.selected = min(max(idx, 0), p.options.count - 1)
        if p != popup { popup = p }
    }

    func commitPopup() {
        guard let p = popup else { return }
        popup = nil
        host?.playClick()
        switch p.kind {
        case .characters:
            insertRaw(p.options[p.selected])
            if page == .letters, shift == .on { shift = .off; shiftIsAuto = false }
        case .languages:
            languageIndex = p.selected
            page = .letters
        }
    }

    func cancelPopup() { popup = nil }

    func cycleTone() {
        let all = Tone.allCases
        let idx = all.firstIndex(of: settings.tone) ?? 2
        settings.tone = all[(idx + 1) % all.count]
        objectWillChange.send()
    }

    // MARK: - Translate mode

    func toggleTranslateMode() {
        host?.playClick()
        translateMode.toggle()
        previewTask?.cancel()
        composer = ""; preview = ""; previewFor = ""; previewBusy = false
        if case .error = status { status = .idle }
        if page == .emoji { page = .letters }
        textDidChange()
    }

    private func checkAccess(_ engine: Engine) -> Bool {
        if engine.needsNetwork, host?.hasFullAccess == false {
            status = .error(TranslateFailure(TranslateError.noFullAccess, engine: engine).keyboardLine)
            return false
        }
        return true
    }

    /// Debounced live translation of the composer.
    private func schedulePreview() {
        previewTask?.cancel()
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            preview = ""; previewFor = ""; previewBusy = false
            return
        }
        direction = LanguageDetector.pair(for: text, settings: settings)
        let engine = settings.engine
        let pair = direction
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.checkAccess(engine) else { return }
            self.previewBusy = true
            defer { if !Task.isCancelled { self.previewBusy = false } }
            do {
                let t = try await TranslationService.translate(text, engine: engine, pair: pair, settings: self.settings)
                guard !Task.isCancelled else { return }
                self.preview = t
                self.previewFor = text
                if case .error = self.status { self.status = .idle }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                NSLog("Skald keyboard: preview error: %@", String(describing: error))
                self.preview = ""
                self.status = .error(TranslateFailure(error, engine: engine).keyboardLine)
            }
        }
    }

    /// Return / Insert in translate mode: put the translation into the
    /// document and clear the composer.
    func commitComposer() {
        let text = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, status != .busy else { return }
        let trailing = String(composer.suffix(composer.count - (composer.lastIndex(where: { !$0.isWhitespace })
            .map { composer.distance(from: composer.startIndex, to: $0) + 1 } ?? composer.count)))

        if previewFor == text, !preview.isEmpty {
            finishCommit(source: text, translated: preview, trailing: trailing)
            return
        }
        previewTask?.cancel()
        let engine = settings.engine
        guard checkAccess(engine) else { return }
        let pair = LanguageDetector.pair(for: text, settings: settings)
        direction = pair
        status = .busy
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let t = try await TranslationService.translate(text, engine: engine, pair: pair, settings: settings)
                guard !Task.isCancelled else { return }
                self.finishCommit(source: text, translated: t, trailing: trailing)
            } catch is CancellationError {
                self.status = .idle
            } catch {
                NSLog("Skald keyboard: translate error: %@", String(describing: error))
                self.status = .error(TranslateFailure(error, engine: engine).keyboardLine)
            }
        }
    }

    private func finishCommit(source: String, translated: String, trailing: String) {
        host?.proxy.insertText(translated + trailing)
        undo = UndoRecord(original: "", translated: translated + trailing, composerRestore: composer)
        settings.recordHistory(source: source, target: translated, engine: settings.engine)
        composer = ""; preview = ""; previewFor = ""; previewBusy = false
        status = .done
        textDidChange()
    }

    /// Insert the composer text untranslated.
    func insertComposerAsIs() {
        guard !composer.isEmpty else { return }
        host?.playClick()
        previewTask?.cancel()
        host?.proxy.insertText(composer)
        composer = ""; preview = ""; previewFor = ""; previewBusy = false
        status = .idle
        textDidChange()
    }

    // MARK: - One-shot translate in place (text already in the document)

    func translate() {
        guard status != .busy, let host else { return }
        let proxy = host.proxy

        let selection = proxy.selectedText ?? ""
        let usingSelection = !selection.isEmpty
        let raw = usingSelection ? selection : (proxy.documentContextBeforeInput ?? "")

        let isBlank: (Character) -> Bool = { $0.isWhitespace || $0.isNewline }
        let trailingCount = raw.reversed().prefix(while: isBlank).count
        let leadingCount  = raw.prefix(while: isBlank).count
        let trailing = String(raw.suffix(trailingCount))
        let core = String(raw.dropFirst(leadingCount).dropLast(trailingCount))
        guard !core.isEmpty else {
            status = .error("Type something first, or select text")
            return
        }
        let toDelete = usingSelection ? 0 : (core.count + trailing.count)

        let engine = settings.engine
        guard checkAccess(engine) else { return }

        status = .busy
        let pair = LanguageDetector.pair(for: core, settings: settings)
        direction = pair

        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let translated = try await TranslationService.translate(core, engine: engine, pair: pair, settings: settings)
                guard !Task.isCancelled, let host = self.host else { return }
                let proxy = host.proxy
                if usingSelection {
                    proxy.insertText(translated)
                } else {
                    for _ in 0..<toDelete { proxy.deleteBackward() }
                    proxy.insertText(translated + trailing)
                }
                self.undo = UndoRecord(original: core + (usingSelection ? "" : trailing),
                                       translated: translated + (usingSelection ? "" : trailing))
                self.status = .done
                self.settings.recordHistory(source: core, target: translated, engine: engine)
                self.textDidChange()
            } catch is CancellationError {
                self.status = .idle
            } catch {
                NSLog("Skald keyboard: translate error: %@", String(describing: error))
                self.status = .error(TranslateFailure(error, engine: engine).keyboardLine)
            }
        }
    }

    func undoTranslation() {
        guard let undo, let proxy = host?.proxy else { return }
        for _ in 0..<undo.translated.count { proxy.deleteBackward() }
        if !undo.original.isEmpty { proxy.insertText(undo.original) }
        if let restore = undo.composerRestore, translateMode {
            composer = restore
            schedulePreview()
        }
        self.undo = nil
        status = .idle
        host?.playClick()
        textDidChange()
    }

    func dismissError() {
        if case .error = status { status = .idle }
    }
}
