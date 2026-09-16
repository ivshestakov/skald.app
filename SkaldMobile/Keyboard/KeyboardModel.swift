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
    func playHaptic()
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

/// Magnified key shown while a character key is held (system "Character Preview").
struct KeyPreview: Equatable {
    let glyph: String
    let key: Key
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
    @Published var keyPreview: KeyPreview?
    @Published var suggestions: [String] = []
    @Published var pressedKeys: Set<Key> = []
    @Published var cursorMode = false
    @Published var metrics = KeyboardMetrics.portrait
    // Host text-field traits (UIKeyboardType & co.)
    @Published var numberPadStyle: NumberPadStyle?
    @Published var bottomExtras: [String] = []       // e.g. ["@", "."] for e-mail fields
    @Published var returnKeyTinted = false
    private var correctionsDisabled = false
    /// User's Settings → Keyboard → Text Replacement shortcuts.
    var lexicon: [String: String] = [:]
    /// Set right after an automatic correction; backspace reverts it.
    private var lastAutocorrect: (original: String, replacement: String, separator: String)?

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
    private var lastSpaceTap: Date = .distantPast
    private var lastInsertWasPunctuation = false
    private var repeatTimer: Timer?
    private var task: Task<Void, Never>?

    init() {
        let s = SkaldSettings.shared
        direction = LanguagePair(source: s.primaryLanguage, target: s.secondaryLanguage)
        emojiCategory = s.recentEmoji.isEmpty ? (EmojiData.categories.first?.id ?? "") : "recent"
        Autocorrect.shared.preload(s.keyboardLanguages)
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

    /// Programmatic key press (emoji panel's ABC/backspace, tests).
    func tap(_ key: Key) {
        host?.playClick()
        if settings.hapticsEnabled { host?.playHaptic() }
        perform(key)
    }

    private func perform(_ key: Key) {
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
            tapSpace()
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

    // MARK: - Touch API (driven by KeyTouchUIView)

    private var pageBeforeGlide: KeyboardPage?

    func keyDown(_ key: Key) {
        host?.playClick()
        if settings.hapticsEnabled { host?.playHaptic() }
        pressedKeys.insert(key)
        switch key {
        case .char(let g):
            showKeyPreview(g, keyFrame: nil)
        case .backspace:
            backspaceOnce()
            backspaceCount = 1
        case .numbers, .symbols, .letters:
            // Switch on touch-down so a glide to a digit works.
            pageBeforeGlide = page
            perform(key)
        default:
            break
        }
    }

    /// Finger slid from one key to another without lifting.
    func keyMoved(from: Key?, to: Key?, start: Key) {
        if let from { pressedKeys.remove(from) }
        if let to { pressedKeys.insert(to) }
        if case .char(let g)? = to { showKeyPreview(g, keyFrame: nil) } else { keyPreview = nil }
    }

    func keyReleased(_ key: Key, releasedOn: Key?, start: Key) {
        pressedKeys.remove(key)
        if let r = releasedOn { pressedKeys.remove(r) }
        hideKeyPreviewSoon()
        stopBackspaceRepeat()
        guard let target = releasedOn else { pageBeforeGlide = nil; return }

        switch (start, target) {
        case (.backspace, _), (.numbers, .numbers), (.symbols, .symbols), (.letters, .letters):
            break                                   // acted on touch-down
        case (.shift, .char(let g)):
            // Glide from shift: one capital, shift state untouched.
            let keep = shift
            shift = .on
            insert(g)
            shift = keep
        case (.numbers, .char), (.symbols, .char), (.letters, .char):
            // Glide from a page key: type the key under the finger, go back.
            perform(target)
            if start == .numbers, let back = pageBeforeGlide { page = back }
        case (.shift, .shift):
            perform(.shift)
        case (_, .shift), (_, .numbers), (_, .symbols), (_, .letters):
            break                                   // slid onto a mode key: nothing
        default:
            perform(target)
        }
        pageBeforeGlide = nil
    }

    func keyCancelled(_ key: Key, current: Key?) {
        pressedKeys.remove(key)
        if let current { pressedKeys.remove(current) }
        keyPreview = nil
        stopBackspaceRepeat()
    }

    /// Long-press on a character or the language key.
    func longPress(_ key: Key, frame: CGRect) -> Bool {
        switch key {
        case .char(let g):  return showAlternates(for: g, keyFrame: frame)
        case .language:     return showLanguages(keyFrame: frame)
        default:            return false
        }
    }

    // MARK: Cursor trackpad (space bar long-press)

    func beginCursorMode() -> Bool {
        guard !translateMode else { return false }
        cursorMode = true
        keyPreview = nil
        if settings.hapticsEnabled { host?.playHaptic() }
        return true
    }

    func moveCursor(by n: Int) {
        host?.proxy.adjustTextPosition(byCharacterOffset: n)
    }

    func endCursorMode() {
        cursorMode = false
        textDidChange()
    }

    private static let punctuation: Set<Character> = [".", ",", "?", "!", ";", ":"]

    private func insert(_ raw: String) {
        var s = raw
        if page == .letters, shift != .off {
            s = s.uppercased()
            if shift == .on { shift = .off; shiftIsAuto = false }
        }
        lastInsertWasPunctuation = raw.count == 1 && Self.punctuation.contains(raw.first!)
        lastSpaceTap = .distantPast
        if lastInsertWasPunctuation { autocorrectCurrentWord(separator: s) }
        if lastAutocorrect?.separator == s { return }   // autocorrect already inserted it
        lastAutocorrect = nil
        insertRaw(s)
    }

    // MARK: - Autocorrect

    /// Text before the caret, wherever typing currently goes.
    private var textBeforeCaret: String {
        translateMode ? composer : (host?.proxy.documentContextBeforeInput ?? "")
    }

    /// The word the caret is in (letters only), or "" at a word boundary.
    private var currentWord: String {
        String(textBeforeCaret.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }.reversed())
    }

    private func replaceBeforeCaret(count: Int, with text: String) {
        if translateMode {
            composer.removeLast(min(count, composer.count)); composer += text
            schedulePreview()
        } else {
            guard let proxy = host?.proxy else { return }
            for _ in 0..<count { proxy.deleteBackward() }
            proxy.insertText(text)
            clearUndoIfEdited()
        }
    }

    /// Called when a word is finished with `separator`. Replaces the word if
    /// the spell checker has a confident fix; inserts the separator itself in
    /// that case (so the caller must not).
    private func autocorrectCurrentWord(separator: String) {
        lastAutocorrect = nil
        guard page == .letters, !correctionsDisabled else { return }
        let word = currentWord
        guard !word.isEmpty else { return }
        // Text replacements from Settings → Keyboard → Text Replacement win.
        if let rep = lexicon[word.lowercased()] {
            replaceBeforeCaret(count: word.count, with: rep + separator)
            lastAutocorrect = (word, rep, separator)
            suggestions = []
            textDidChange()
            return
        }
        guard settings.autocorrectEnabled else { return }
        guard let fix = Autocorrect.shared.correction(for: word, language: currentLanguage, layout: currentLayout) else { return }
        replaceBeforeCaret(count: word.count, with: fix.replacement + separator)
        lastAutocorrect = (word, fix.replacement, separator)
        suggestions = []
        textDidChange()
    }

    /// Backspace right after an autocorrect puts the original word back.
    private func revertAutocorrectIfNeeded() -> Bool {
        guard let ac = lastAutocorrect else { return false }
        lastAutocorrect = nil
        let before = textBeforeCaret
        guard before.hasSuffix(ac.replacement + ac.separator) else { return false }
        replaceBeforeCaret(count: ac.replacement.count + ac.separator.count, with: ac.original + ac.separator)
        textDidChange()
        return true
    }

    /// Tap on a suggestion in the top bar: replace the current word.
    func acceptSuggestion(_ s: String) {
        host?.playClick()
        if settings.hapticsEnabled { host?.playHaptic() }
        let word = currentWord
        var text = s
        if text.hasPrefix("\""), text.hasSuffix("\"") { text = String(text.dropFirst().dropLast()) }   // keep as typed
        replaceBeforeCaret(count: word.count, with: text + " ")
        lastAutocorrect = nil
        lastSpaceTap = .distantPast
        textDidChange()
    }

    private func updateSuggestions() {
        guard settings.suggestionsEnabled, !correctionsDisabled, page == .letters, status == .idle || translateMode else { suggestions = []; return }
        let word = currentWord
        let next = word.isEmpty ? [] : Autocorrect.shared.suggestions(forPartial: word, language: currentLanguage, layout: currentLayout)
        if next != suggestions { suggestions = next }
    }

    /// Space with the two system shortcuts: a quick double space after a
    /// word becomes ". ", and space after punctuation typed on the numbers
    /// or symbols page jumps back to the letters page.
    private func tapSpace() {
        let now = Date()
        // Consecutive space presses (nothing typed in between) — the system
        // keyboard doesn't time them either, it only requires a word before.
        let quick = lastSpaceTap != .distantPast
        let before = translateMode ? composer : (host?.proxy.documentContextBeforeInput ?? "")
        let wordEnd: Bool = {
            // "…word " → last char is one space, char before it is a letter/number
            guard before.hasSuffix(" "), before.count >= 2 else { return false }
            let prev = before[before.index(before.endIndex, offsetBy: -2)]
            return prev.isLetter || prev.isNumber || prev == ")" || prev == "\"" || prev == "'"
        }()
        if quick && wordEnd {
            if translateMode {
                composer.removeLast(); composer += ". "
                schedulePreview()
            } else {
                host?.proxy.deleteBackward()
                host?.proxy.insertText(". ")
                clearUndoIfEdited()
            }
            lastSpaceTap = .distantPast
            lastInsertWasPunctuation = false
            lastAutocorrect = nil
            textDidChange()
            return
        }
        if page != .letters, lastInsertWasPunctuation {
            page = .letters
        }
        lastInsertWasPunctuation = false
        lastSpaceTap = now
        autocorrectCurrentWord(separator: " ")
        if lastAutocorrect != nil { return }
        insertRaw(" ")
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
        if settings.hapticsEnabled { host?.playHaptic() }
        settings.recordEmoji(e)
        insertRaw(e)
    }

    private func backspaceOnce() {
        if revertAutocorrectIfNeeded() { return }
        if translateMode, !composer.isEmpty {
            composer.removeLast()
            schedulePreview()
        } else {
            host?.proxy.deleteBackward()
            clearUndoIfEdited()
        }
        textDidChange()
    }

    private var backspaceCount = 0

    /// Long-press on backspace: repeat, then after a while delete whole words.
    func startBackspaceRepeat() {
        stopBackspaceRepeat()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.backspaceCount += 1
                if self.backspaceCount > 14 { self.deleteWordBackward() } else { self.backspaceOnce() }
            }
        }
    }

    func stopBackspaceRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        backspaceCount = 0
    }

    private func deleteWordBackward() {
        let before = textBeforeCaret
        guard !before.isEmpty else { return }
        let trailing = before.reversed().prefix { $0.isWhitespace || $0.isNewline }.count
        let word = before.dropLast(trailing).reversed().prefix { !($0.isWhitespace || $0.isNewline) }.count
        let n = max(1, trailing + word)
        if translateMode {
            composer.removeLast(min(n, composer.count)); schedulePreview()
        } else {
            for _ in 0..<n { host?.proxy.deleteBackward() }
            clearUndoIfEdited()
        }
        lastAutocorrect = nil
        textDidChange()
    }

    private func clearUndoIfEdited() {
        if undo != nil { undo = nil; if status == .done { status = .idle } }
    }

    // MARK: - Context tracking

    /// Called by the controller on textDidChange and after our own edits.
    /// Read the host text field's traits: keyboard type, autocorrection,
    /// secure entry, return key. Called whenever the document changes.
    func applyHostTraits() {
        guard let proxy = host?.proxy else { return }
        let style: NumberPadStyle?
        switch proxy.keyboardType {
        case .numberPad?, .asciiCapableNumberPad?: style = .plain
        case .decimalPad?: style = .decimal
        case .phonePad?, .namePhonePad?: style = proxy.keyboardType == .phonePad ? .phone : nil
        default: style = nil
        }
        if style != numberPadStyle {
            numberPadStyle = style
            if style != nil { page = .numberPad } else if page == .numberPad { page = .letters }
        }
        let extras: [String]
        switch proxy.keyboardType {
        case .emailAddress?: extras = ["@", "."]
        case .URL?, .webSearch?: extras = [".", "/"]
        case .twitter?: extras = ["@", "#"]
        default: extras = []
        }
        if extras != bottomExtras { bottomExtras = extras }
        correctionsDisabled = (proxy.isSecureTextEntry ?? false) || proxy.autocorrectionType == .no
            || proxy.keyboardType == .emailAddress || proxy.keyboardType == .URL
        let tintTypes: [UIReturnKeyType] = [.go, .search, .send, .done, .join, .route, .emergencyCall, .continue]
        let hasText = !(proxy.documentContextBeforeInput ?? "").isEmpty || !(proxy.documentContextAfterInput ?? "").isEmpty
        let tinted = tintTypes.contains(proxy.returnKeyType ?? .default) && (!(proxy.enablesReturnKeyAutomatically ?? false) || hasText)
        if tinted != returnKeyTinted { returnKeyTinted = tinted }
    }

    func textDidChange() {
        guard let proxy = host?.proxy else { return }
        applyHostTraits()
        defer { updateSuggestions() }
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
        let capType = host?.proxy.autocapitalizationType ?? .sentences
        if capType == .none {
            if shift == .on, shiftIsAuto { shift = .off }
            return
        }
        if capType == .allCharacters {
            if shift == .off { shift = .on; shiftIsAuto = true }
            return
        }
        if capType == .words {
            let start = before.isEmpty || before.last!.isWhitespace || before.last!.isNewline
            if start, shift == .off { shift = .on; shiftIsAuto = true }
            else if !start, shift == .on, shiftIsAuto { shift = .off }
            return
        }
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

    // MARK: - Key preview (magnified key while pressed)

    func showKeyPreview(_ glyph: String, keyFrame: CGRect?) {
        guard page != .emoji else { return }
        let cased = page == .letters && shift != .off ? glyph.uppercased() : glyph
        previewToken += 1
        keyPreview = KeyPreview(glyph: cased, key: .char(glyph))
    }

    private var previewToken = 0

    /// Keep the pop-up ~100 ms after release like the system, so quick taps
    /// still flash it.
    func hideKeyPreviewSoon() {
        previewToken += 1
        let token = previewToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.previewToken == token else { return }
            self.keyPreview = nil
        }
    }

    func hideKeyPreview() { previewToken += 1; keyPreview = nil }

    // MARK: - Long-press popups

    func showAlternates(for glyph: String, keyFrame: CGRect) -> Bool {
        let alts = KeyAlternates.alternates(for: glyph)
        guard !alts.isEmpty else { return false }
        let cased = page == .letters && shift != .off
        let options = ([glyph] + alts).map { cased ? $0.uppercased() : $0 }
        popup = KeyPopup(kind: .characters, options: options, keyFrame: keyFrame)
        hideKeyPreview()
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
    func updatePopupSelection(x: CGFloat) {
        guard var p = popup else { return }
        let layout = KeyPopupView.layout(for: p, keyHeight: metrics.rowHeight)
        let idx = Int(((x - layout.frame.minX) / layout.optionWidth).rounded(.down))
        p.selected = min(max(idx, 0), p.options.count - 1)
        if p != popup { popup = p }
    }

    func commitPopup() {
        guard let p = popup else { return }
        popup = nil
        host?.playClick()
        if settings.hapticsEnabled { host?.playHaptic() }
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
