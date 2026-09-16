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
    /// Words this session auto-corrected: replacement (lowercased) → what was typed.
    private var correctionHistory: [String: String] = [:]
    private var correctionOrder: [String] = []
    /// Set right after an automatic correction; backspace reverts it.
    private var lastAutocorrect: (original: String, replacement: String, separator: String)?

    // Translate mode: keystrokes go into `composer`, `preview` is the live
    // translation, Return inserts the preview into the document.
    @Published var translateMode = false
    @Published var showSettings = false
    /// Explicit "translate to" choice from the settings panel; nil = derived.
    @Published var targetOverride: Language?

    /// Source = language of the current layout; target = the configured
    /// "translate to" language, or the primary one when you're typing in it.
    var translatePair: LanguagePair {
        let src = currentLanguage
        if let t = targetOverride, t != src { return LanguagePair(source: src, target: t) }
        let t = src == settings.secondaryLanguage ? settings.primaryLanguage : settings.secondaryLanguage
        return LanguagePair(source: src, target: t)
    }

    func setTarget(_ l: Language) {
        targetOverride = l
        direction = translatePair
        if translateMode { schedulePreview() }
    }
    @Published var composer = ""
    @Published var preview = ""
    @Published var previewBusy = false
    private var previewFor = ""
    private var previewTask: Task<Void, Never>?

    @Published var emojiCategory: String = ""
    /// Texts sent for translation this session, newest first (max 5), for
    /// swiping through them in the translation field.
    private var sentHistory: [String] = []
    private var historyCursor = -1

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
        Autocorrect.shared.loadPersonal()
        Autocorrect.shared.preload(s.keyboardLanguages.first ?? s.primaryLanguage)
    }

    // MARK: - Languages / layouts

    var keyboardLanguages: [Language] { settings.keyboardLanguages }
    var currentLanguage: Language {
        let langs = keyboardLanguages
        return langs[min(languageIndex, langs.count - 1)]
    }
    var currentLayout: LetterLayout { LetterLayout.forLanguage(currentLanguage) }
    var hasLanguageKey: Bool { false }   // switching is a swipe on the space bar
    var showsGlobe: Bool { host?.needsInputModeSwitchKey ?? true }

    func nextLanguage() {
        languageIndex = (languageIndex + 1) % keyboardLanguages.count
        Autocorrect.shared.preload(currentLanguage)
    }

    /// Swipe on the space bar: left = next layout, right = previous.
    func swipeLanguage(_ delta: Int) {
        let n = keyboardLanguages.count
        guard n > 1 else { return }
        languageIndex = ((languageIndex + delta) % n + n) % n
        pressedKeys.remove(.space)
        if settings.hapticsEnabled { host?.playHaptic() }
        Autocorrect.shared.preload(currentLanguage)
        direction = translatePair
    }

    var returnLabel: String {
        if translateMode { return "go" }
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
            if translateMode {
                if composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { translate() } else { commitComposer() }
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

    /// Vertical trackpad movement: jump to the same column on the previous /
    /// next line. Works on real line breaks; soft-wrapped lines are invisible
    /// to a keyboard extension.
    func moveCursorLines(_ delta: Int) {
        guard let proxy = host?.proxy, delta != 0 else { return }
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        let column = before.reversed().prefix { $0 != "\n" }.count
        if delta < 0 {
            guard let nl = before.lastIndex(of: "\n") else { proxy.adjustTextPosition(byCharacterOffset: -column); return }
            let prevLine = before[..<nl]
            let prevLen = prevLine.reversed().prefix { $0 != "\n" }.count
            let target = min(column, prevLen)
            proxy.adjustTextPosition(byCharacterOffset: -(column + 1 + (prevLen - target)))
        } else {
            guard let nl = after.firstIndex(of: "\n") else { proxy.adjustTextPosition(byCharacterOffset: after.count); return }
            let restOfLine = after.distance(from: after.startIndex, to: nl)
            let nextLine = after[after.index(after: nl)...]
            let nextLen = nextLine.prefix { $0 != "\n" }.count
            proxy.adjustTextPosition(byCharacterOffset: restOfLine + 1 + min(column, nextLen))
        }
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
        if lastAutocorrect?.separator == s { return }   // text replacement already inserted it
        insertRaw(s)
    }

    // MARK: - Autocorrect

    /// Text before the caret, wherever typing currently goes.
    private var textBeforeCaret: String {
        translateMode ? composer : (host?.proxy.documentContextBeforeInput ?? "")
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c == "'" || c == "’" || c == "-" }

    /// The word the caret is in (letters only), or "" at a word boundary.
    private var currentWord: String {
        String(textBeforeCaret.reversed().prefix(while: Self.isWordChar).reversed())
    }

    /// Rest of the word after the caret (when the user tapped inside a word).
    private var wordAfterCaret: String {
        guard !translateMode, let after = host?.proxy.documentContextAfterInput else { return "" }
        return String(after.prefix(while: Self.isWordChar))
    }

    /// The word before the current one — context for the bigram model.
    private var previousWord: String? {
        var t = Substring(textBeforeCaret)
        while let l = t.last, Self.isWordChar(l) { t = t.dropLast() }
        while let l = t.last, l == " " { t = t.dropLast() }
        guard let l = t.last, Self.isWordChar(l) else { return nil }
        var w = ""
        while let c = t.last, Self.isWordChar(c) { w.insert(c, at: w.startIndex); t = t.dropLast() }
        return w
    }

    private func remember(original: String, replacement: String) {
        let key = replacement.lowercased()
        if correctionHistory[key] == nil { correctionOrder.append(key) }
        correctionHistory[key] = original
        if correctionOrder.count > 60 { correctionHistory.removeValue(forKey: correctionOrder.removeFirst()) }
    }

    private func replaceBeforeCaret(count: Int, with text: String) {
        let base = textBeforeCaret
        lastEditAt = Date()
        if translateMode {
            composer.removeLast(min(count, composer.count)); composer += text
            schedulePreview()
        } else {
            guard let proxy = host?.proxy else { return }
            for _ in 0..<count { proxy.deleteBackward() }
            proxy.insertText(text)
            clearUndoIfEdited()
            updateAutoShift(before: String(base.dropLast(min(count, base.count))) + text)
        }
    }

    /// Called when a word is finished with `separator`. Text replacements
    /// apply at once; dictionary correction runs in the background and is
    /// applied afterwards if the text still ends with that word — so typing
    /// never waits. Returns true when it inserted the separator itself.
    private var correctionGeneration = 0

    private func autocorrectCurrentWord(separator: String) {
        lastAutocorrect = nil
        guard page == .letters, !correctionsDisabled else { return }
        let word = currentWord
        guard !word.isEmpty else { return }
        if let rep = lexicon[word.lowercased()] {
            replaceBeforeCaret(count: word.count, with: rep + separator)
            lastAutocorrect = (word, rep, separator)
            suggestions = []
            textDidChange()
            return
        }
        guard settings.autocorrectEnabled else { return }
        correctionGeneration += 1
        let gen = correctionGeneration
        let language = currentLanguage, layout = currentLayout, prev = previousWord
        let inTranslateMode = translateMode
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let fix = Autocorrect.shared.correction(for: word, prev: prev, language: language, layout: layout)
            DispatchQueue.main.async {
                guard let self, gen == self.correctionGeneration, self.translateMode == inTranslateMode else { return }
                guard let fix else {
                    if Autocorrect.shared.correctionWouldHaveConsidered(word, language: language) {
                        Autocorrect.shared.noteUnknownKept(word)
                    }
                    return
                }
                // Still "word + separator" right before the caret?
                let tail = word + separator
                guard self.textBeforeCaret.hasSuffix(tail) else { return }
                self.replaceBeforeCaret(count: tail.count, with: fix.replacement + separator)
                self.lastAutocorrect = (word, fix.replacement, separator)
                self.remember(original: word, replacement: fix.replacement)
                self.suggestions = []
                self.textDidChange()
            }
        }
    }

    /// Backspace right after an autocorrect puts the original word back.
    private func revertAutocorrectIfNeeded() -> Bool {
        guard let ac = lastAutocorrect else { return false }
        lastAutocorrect = nil
        let before = textBeforeCaret
        guard before.hasSuffix(ac.replacement + ac.separator) else { return false }
        replaceBeforeCaret(count: ac.replacement.count + ac.separator.count, with: ac.original + ac.separator)
        Autocorrect.shared.learnWord(ac.original)
        correctionHistory.removeValue(forKey: ac.replacement.lowercased())
        textDidChange()
        return true
    }

    /// Tap on a suggestion in the top bar: replace the word at the caret
    /// (both halves, when the caret is inside it).
    func acceptSuggestion(_ s: String) {
        host?.playClick()
        if settings.hapticsEnabled { host?.playHaptic() }
        let before = currentWord
        let after = wordAfterCaret
        var text = s
        if text.hasPrefix("\""), text.hasSuffix("\"") { text = String(text.dropFirst().dropLast()) }   // keep as typed
        if !after.isEmpty, let proxy = host?.proxy {
            proxy.adjustTextPosition(byCharacterOffset: after.count)
        }
        let whole = before + after
        // Replacing an auto-corrected word with the original: don't append a space
        // when the caret was inside the word (system behaviour); otherwise do.
        let trailing = after.isEmpty && translateMode == false && (host?.proxy.documentContextAfterInput ?? "").first.map { !($0 == " ") } ?? true ? " " : ""
        replaceBeforeCaret(count: whole.count, with: text + trailing)
        if s.hasPrefix("\"") || correctionHistory[whole.lowercased()]?.lowercased() == text.lowercased() {
            Autocorrect.shared.learnWord(text)              // "keep what I typed"
        } else {
            Autocorrect.shared.learnFix(typed: correctionHistory[whole.lowercased()] ?? whole, fix: text)
        }
        remember(original: whole, replacement: text)
        lastAutocorrect = nil
        lastSpaceTap = .distantPast
        textDidChange()
    }

    private var suggestionGeneration = 0

    private func updateSuggestions() {
        guard settings.suggestionsEnabled, !correctionsDisabled, page == .letters, status == .idle || translateMode else {
            suggestions = []; return
        }
        let before = currentWord
        let after = wordAfterCaret
        let word = before + after
        let t = textBeforeCaret
        let prev = previousWord
        let prevForPrediction = t.hasSuffix(" ") ? previousWordForPrediction(t) : nil
        let history = correctionHistory[word.lowercased()]
        let language = currentLanguage, layout = currentLayout
        suggestionGeneration += 1
        let gen = suggestionGeneration
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var next: [String]
            if word.isEmpty {
                next = prevForPrediction.map { Autocorrect.shared.nextWords(after: $0, language: language) } ?? []
            } else {
                next = Autocorrect.shared.suggestions(forPartial: word, prev: prev, language: language,
                                                      layout: layout, alwaysFixes: !after.isEmpty)
                if let original = history, original.lowercased() != word.lowercased() {
                    next.removeAll { $0 == original }
                    next.insert(original, at: 0)
                    if next.count > 3 { next.removeLast(next.count - 3) }
                }
            }
            DispatchQueue.main.async {
                guard let self, gen == self.suggestionGeneration else { return }
                if next != self.suggestions { self.suggestions = next }
            }
        }
    }

    private func previousWordForPrediction(_ text: String) -> String? {
        var t = Substring(text)
        while let l = t.last, l == " " { t = t.dropLast() }
        guard let l = t.last, Self.isWordChar(l) else { return nil }
        var w = ""
        while let c = t.last, Self.isWordChar(c) { w.insert(c, at: w.startIndex); t = t.dropLast() }
        return w
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
                textDidChange()
            } else {
                host?.proxy.deleteBackward()
                host?.proxy.insertText(". ")
                clearUndoIfEdited()
                afterLocalEdit(before: String(before.dropLast()) + ". ")
            }
            lastSpaceTap = .distantPast
            lastInsertWasPunctuation = false
            lastAutocorrect = nil
            return
        }
        if page != .letters, lastInsertWasPunctuation {
            page = .letters
        }
        lastInsertWasPunctuation = false
        lastSpaceTap = now
        autocorrectCurrentWord(separator: " ")
        if lastAutocorrect != nil { return }             // text replacement inserted the space
        insertRaw(" ")
    }

    /// Inserts text where typing currently goes: the composer in translate
    /// mode, the document otherwise.
    private func insertRaw(_ s: String) {
        let base = textBeforeCaret
        lastEditAt = Date()
        if translateMode {
            composer += s
            schedulePreview()
        } else {
            host?.proxy.insertText(s)
            clearUndoIfEdited()
        }
        afterLocalEdit(before: base + s)
    }

    /// After one of our own edits the host's context may lag or come back
    /// empty, and iOS doesn't always send textDidChange for the keyboard's
    /// own insertions — so auto-capitalisation is decided from the text we
    /// know we produced.
    private func afterLocalEdit(before: String) {
        if !translateMode { updateAutoShift(before: before) }
        textDidChange()
    }

    func insertEmoji(_ e: String) {
        host?.playClick()
        if settings.hapticsEnabled { host?.playHaptic() }
        settings.recordEmoji(e)
        insertRaw(e)
    }

    private func backspaceOnce() {
        lastEditAt = Date()
        if revertAutocorrectIfNeeded() { return }
        let base = textBeforeCaret
        if translateMode, !composer.isEmpty {
            composer.removeLast()
            schedulePreview()
            textDidChange()
        } else {
            host?.proxy.deleteBackward()
            clearUndoIfEdited()
            afterLocalEdit(before: String(base.dropLast()))
        }
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

    /// When we last edited the document ourselves. Right after a burst of
    /// deletes + inserts (autocorrect) the host may briefly report an empty
    /// context, which must not be mistaken for "start of text".
    private var lastEditAt = Date.distantPast

    /// `fromHost` = called from the system's textDidChange/selectionDidChange,
    /// i.e. the document context is settled. Auto-capitalisation is decided
    /// only then (or on the local composer), never on our own intermediate
    /// state.
    func textDidChange(fromHost: Bool = false) {
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
            if fromHost {
                let suspiciousEmpty = before.isEmpty && Date().timeIntervalSince(lastEditAt) < 0.5
                if !suspiciousEmpty { updateAutoShift(before: before) }
            }
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

    func setEngine(_ e: Engine) {
        host?.playClick()
        settings.engine = e
        objectWillChange.send()
        if translateMode { schedulePreview() }
    }

    func setAdaptStyle(_ on: Bool) {
        host?.playClick()
        settings.adaptStyleEnabled = on
        objectWillChange.send()
        if translateMode { schedulePreview() }
    }

    func setTone(_ t: Tone) {
        host?.playClick()
        settings.adaptStyleEnabled = true
        settings.tone = t
        objectWillChange.send()
        if translateMode { schedulePreview() }
    }

    func cycleTone() {
        let all = Tone.allCases
        let idx = all.firstIndex(of: settings.tone) ?? 2
        settings.tone = all[(idx + 1) % all.count]
        objectWillChange.send()
    }

    // MARK: - Translate mode

    func toggleTranslateMode() {
        if translateMode { exitTranslateMode() } else { enterTranslateMode() }
    }

    func enterTranslateMode() {
        host?.playClick()
        translateMode = true
        historyCursor = -1
        showSettings = false
        composer = ""; preview = ""; previewFor = ""; previewBusy = false
        if case .error = status { status = .idle }
        if page == .emoji { page = .letters }
        direction = translatePair
        textDidChange()
    }

    func exitTranslateMode() {
        host?.playClick()
        translateMode = false
        previewTask?.cancel()
        composer = ""; preview = ""; previewFor = ""; previewBusy = false
        if case .error = status { status = .idle }
        textDidChange()
    }

    /// Swipe in the translation field: left = older sent text, right = newer.
    func swipeHistory(_ delta: Int) {
        guard translateMode, !sentHistory.isEmpty else { return }
        let next = historyCursor + delta
        if next < 0 { historyCursor = -1; composer = ""; return }
        guard next < sentHistory.count else { return }
        historyCursor = next
        composer = sentHistory[next]
        host?.playClick()
        textDidChange()
    }

    func toggleSettings() {
        host?.playClick()
        showSettings.toggle()
        if showSettings { hideKeyPreview(); popup = nil }
    }

    private func checkAccess(_ engine: Engine) -> Bool {
        if engine.needsNetwork, host?.hasFullAccess == false {
            status = .error(TranslateFailure(TranslateError.noFullAccess, engine: engine).keyboardLine)
            return false
        }
        return true
    }

    /// No live translation: typing only updates the field. Translation runs
    /// when the user sends it with ↑ (see `commitComposer`).
    private func schedulePreview() {
        previewTask?.cancel()
        preview = ""; previewFor = ""; previewBusy = false
        direction = translatePair
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
        let pair = translatePair
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
        sentHistory.removeAll { $0 == source }
        sentHistory.insert(source, at: 0)
        if sentHistory.count > 5 { sentHistory.removeLast(sentHistory.count - 5) }
        historyCursor = -1
        composer = ""; preview = ""; previewFor = ""; previewBusy = false
        status = .done
        translateMode = false           // the field collapses back to suggestions
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
        if let restore = undo.composerRestore {
            translateMode = true
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
