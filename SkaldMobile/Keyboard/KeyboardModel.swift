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
    func playClick(_ kind: KeyClick)
    func playHaptic()
}

enum KeyClick { case letter, modifier, delete }

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
    private var periodShortcutDisabled = false
    private var lastDocumentID: UUID?
    private var languageIndexBeforeASCII: Int?
    /// User's Settings → Keyboard → Text Replacement shortcuts.
    var lexicon: [String: String] = [:]
    /// Words this session auto-corrected: replacement (lowercased) → what was typed.
    private var correctionHistory: [String: String] = [:]
    private var correctionOrder: [String] = []
    /// Set right after an automatic correction; backspace reverts it.
    private var lastAutocorrect: (original: String, replacement: String, separator: String)?
    /// Native rule: after the user deletes back into a corrected word, retyping
    /// the same word does not trigger the same correction again.
    private var retypeGuard: String?
    /// Correction computed while typing for the word at the caret. The bar
    /// shows it highlighted; the next separator applies exactly this.
    private var pendingWord: String?
    private var pendingFix: Autocorrect.Correction?
    /// Index into `suggestions` of the candidate a separator will apply.
    @Published var applyIndex: Int?
    /// Where the finger actually landed for each letter of the word being
    /// typed: letter → proximity of nearby keys. Feeds the corrector.
    private var touchTrail: [(typed: Character, prox: [Character: Double])] = []
    private var pendingProximity: [Character: Double]?
    /// Context in which the user turned shift off by hand; auto-shift stays
    /// off until the text changes.
    private var shiftOffContext: String?

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
    /// Emoji search: the top bar becomes a search field, keys type into it.
    @Published var emojiSearchActive = false
    @Published var emojiQuery = ""
    @Published var emojiResults: [String] = []
    /// Skin-tone variants shown for a long-pressed emoji.
    @Published var emojiVariants: [String]?
    /// Next-letter likelihood for the word being typed (dynamic hit targets).
    @Published var letterBias: [Character: Double] = [:]
    /// Return key disabled: enablesReturnKeyAutomatically with an empty field.
    @Published var returnKeyDisabled = false
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
        if let last = s.lastKeyboardLanguage, let i = s.keyboardLanguages.firstIndex(of: last) {
            languageIndex = i
        }
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
        rememberLanguage()
        Autocorrect.shared.preload(currentLanguage)
    }

    /// Persist a user-initiated layout choice (not the ASCII-field override).
    private func rememberLanguage() {
        guard languageIndexBeforeASCII == nil else { return }
        settings.lastKeyboardLanguage = currentLanguage
    }

    /// Swipe on the space bar: left = next layout, right = previous.
    func swipeLanguage(_ delta: Int) {
        let n = keyboardLanguages.count
        guard n > 1 else { return }
        languageIndex = ((languageIndex + delta) % n + n) % n
        rememberLanguage()
        pressedKeys.remove(.space)
        if settings.hapticsEnabled { host?.playHaptic() }
        Autocorrect.shared.preload(currentLanguage)
        direction = translatePair
    }

    var returnLabel: String {
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
        host?.playClick(clickKind(for: key))
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
            shiftOffContext = shift == .off ? textBeforeCaret : nil
            lastShiftTap = now
        case .backspace:
            backspaceOnce()
        case .space:
            tapSpace()
        case .ret:
            if emojiSearchActive {
                if let first = emojiResults.first { insertEmoji(first) }
                return
            }
            guard !returnKeyDisabled else { return }
            if translateMode {
                if composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { translate() } else { commitComposer() }
            } else {
                lastSpaceTap = .distantPast
                lastInsertWasPunctuation = false
                if autocorrectCurrentWord(separator: "\n") { touchTrail.removeAll(); return }
                touchTrail.removeAll()
                insertRaw("\n")
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

    private func clickKind(for key: Key) -> KeyClick {
        switch key {
        case .char, .space: return .letter
        case .backspace:    return .delete
        default:            return .modifier
        }
    }

    func keyDown(_ key: Key) {
        host?.playClick(clickKind(for: key))
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

    func keyReleased(_ key: Key, releasedOn: Key?, start: Key, proximity: [Character: Double]? = nil) {
        pendingProximity = proximity
        defer { pendingProximity = nil }
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
            if let back = pageBeforeGlide { page = back }
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

    /// Approximate characters per visual line: a keyboard extension can't see
    /// the host's layout, so long paragraphs are treated as wrapped every
    /// `charsPerLine` characters. Tuned for the default body font in portrait.
    private var charsPerLine: Int { metrics == .landscape ? 80 : 38 }

    /// Vertical trackpad movement: one visual line up or down, keeping the
    /// column. Uses real line breaks plus the wrap estimate above.
    func moveCursorLines(_ delta: Int) {
        guard let proxy = host?.proxy, delta != 0 else { return }
        let n = charsPerLine
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        let paraBefore = before.reversed().prefix { $0 != "\n" }.count      // chars since paragraph start
        let column = paraBefore % n
        if delta < 0 {
            if paraBefore >= n {                                              // previous visual line, same paragraph
                proxy.adjustTextPosition(byCharacterOffset: -n)
                return
            }
            guard let nl = before.lastIndex(of: "\n") else {                  // first line of the text
                proxy.adjustTextPosition(byCharacterOffset: -paraBefore); return
            }
            let prevLen = before[..<nl].reversed().prefix { $0 != "\n" }.count
            let lastLineStart = prevLen == 0 ? 0 : (prevLen - 1) / n * n
            let target = min(lastLineStart + column, prevLen)
            proxy.adjustTextPosition(byCharacterOffset: -(paraBefore + 1 + (prevLen - target)))
        } else {
            let rest = after.prefix { $0 != "\n" }.count                       // chars to paragraph end
            let roomOnThisLine = n - column
            if rest > roomOnThisLine {                                          // next visual line, same paragraph
                proxy.adjustTextPosition(byCharacterOffset: min(n, rest))
                return
            }
            guard let nl = after.firstIndex(of: "\n") else {
                proxy.adjustTextPosition(byCharacterOffset: rest); return
            }
            let nextLen = after[after.index(after: nl)...].prefix { $0 != "\n" }.count
            proxy.adjustTextPosition(byCharacterOffset: rest + 1 + min(column, nextLen))
        }
    }

    func endCursorMode() {
        cursorMode = false
        textDidChange()
    }

    private static let punctuation: Set<Character> = [".", ",", "?", "!", ";", ":"]

    private func insert(_ raw: String) {
        var s = raw
        if page == .letters, shift != .off, !emojiSearchActive {
            s = s.uppercased()
            if shift == .on { shift = .off; shiftIsAuto = false }
        }
        lastInsertWasPunctuation = raw.count == 1 && Self.punctuation.contains(raw.first!)
        lastSpaceTap = .distantPast
        if lastInsertWasPunctuation {
            touchTrail.removeAll()
            if autocorrectCurrentWord(separator: s) { return }
        }
        if let smart = smartPunctuation(for: raw) {
            switch smart {
            case .replace(let text): insertRaw(text); return
            case .dash: replaceBeforeCaret(count: 1, with: "—"); textDidChange(); return
            }
        }
        if page == .letters, raw.count == 1, let c = s.lowercased().first, Self.isWordChar(c) {
            touchTrail.append((c, pendingProximity ?? [:]))
        } else if !(raw.count == 1 && Self.isWordChar(raw.first!)) {
            touchTrail.removeAll()
        }
        insertRaw(s)
    }

    private enum SmartPunct { case replace(String), dash }

    /// Smart Punctuation like the system's: curly quotes by language, an
    /// apostrophe that opens or closes by context, and "--" → em dash.
    private func smartPunctuation(for raw: String) -> SmartPunct? {
        guard !correctionsDisabled, page != .emoji, !emojiSearchActive, let proxy = host?.proxy else { return nil }
        let before = textBeforeCaret
        let opening = before.isEmpty || before.last!.isWhitespace || before.last!.isNewline || "([{«“‘".contains(before.last!)
        switch raw {
        case "\"":
            guard proxy.smartQuotesType != .no else { return nil }
            let cyrillic = currentLanguage == .russian || currentLanguage == .ukrainian
            let pair = cyrillic ? ("«", "»") : ("“", "”")
            return .replace(opening ? pair.0 : pair.1)
        case "'":
            guard proxy.smartQuotesType != .no else { return nil }
            return .replace(opening ? "‘" : "’")
        case "-":
            guard proxy.smartDashesType != .no, before.hasSuffix("-"), !before.hasSuffix("--") else { return nil }
            return .dash
        default:
            return nil
        }
    }

    /// Touch data for the word at the caret, when it matches what we typed.
    private func touchesForCurrentWord(_ word: String) -> [[Character: Double]]? {
        guard touchTrail.count == word.count else { return nil }
        for (t, c) in zip(touchTrail, word.lowercased()) where t.typed != c { return nil }
        return touchTrail.map { $0.prox }
    }

    /// Straight → typographic apostrophe when the host wants smart quotes.
    private func styled(_ text: String) -> String {
        guard host?.proxy.smartQuotesType != .no, !correctionsDisabled else { return text }
        return text.replacingOccurrences(of: "'", with: "’")
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
    /// apply at once. The dictionary correction was computed while the word
    /// was being typed (`pendingFix`, shown highlighted in the bar) and is
    /// applied synchronously; if it isn't ready yet (very fast typing) it is
    /// computed in the background and applied afterwards if the text still
    /// ends with that word. Returns true when it inserted the separator itself.
    private var correctionGeneration = 0

    @discardableResult
    private func autocorrectCurrentWord(separator: String) -> Bool {
        lastAutocorrect = nil
        guard page == .letters, !correctionsDisabled, !emojiSearchActive else { return false }
        let word = currentWord
        guard !word.isEmpty else { return false }
        if let g = retypeGuard {
            retypeGuard = nil
            if g == word.lowercased() { return false }
        }
        if let rep = lexicon[word.lowercased()] {
            replaceBeforeCaret(count: word.count, with: rep + separator)
            lastAutocorrect = (word, rep, separator)
            suggestions = []; applyIndex = nil
            textDidChange()
            return true
        }
        guard settings.autocorrectEnabled else { return false }

        if pendingWord == word {
            let fix = pendingFix
            pendingWord = nil; pendingFix = nil
            touchTrail.removeAll()
            guard let fix else {
                if Autocorrect.shared.correctionWouldHaveConsidered(word, language: currentLanguage) {
                    Autocorrect.shared.noteUnknownKept(word)
                }
                return false
            }
            replaceBeforeCaret(count: word.count, with: styled(fix.replacement) + separator)
            lastAutocorrect = (word, fix.replacement, separator)
            remember(original: word, replacement: fix.replacement)
            suggestions = []; applyIndex = nil
            textDidChange()
            return true
        }

        correctionGeneration += 1
        let gen = correctionGeneration
        let language = currentLanguage, layout = currentLayout, prev = previousWord
        let inTranslateMode = translateMode
        let touches = touchesForCurrentWord(word)
        touchTrail.removeAll()
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let fix = Autocorrect.shared.correction(for: word, prev: prev, language: language, layout: layout, touches: touches)
            DispatchQueue.main.async {
                guard let self, gen == self.correctionGeneration, self.translateMode == inTranslateMode else { return }
                guard let fix else {
                    if Autocorrect.shared.correctionWouldHaveConsidered(word, language: language) {
                        Autocorrect.shared.noteUnknownKept(word)
                    }
                    return
                }
                let tail = word + separator
                guard self.textBeforeCaret.hasSuffix(tail) else { return }
                self.replaceBeforeCaret(count: tail.count, with: self.styled(fix.replacement) + separator)
                self.lastAutocorrect = (word, fix.replacement, separator)
                self.remember(original: word, replacement: fix.replacement)
                self.suggestions = []; self.applyIndex = nil
                self.textDidChange()
            }
        }
        return false
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

    /// Rebuilds the bar in the background. While a word is being typed this
    /// also decides the correction the next separator will apply, so the
    /// bar can show it highlighted (native layout: "typed" · fix · other).
    private func updateSuggestions() {
        guard settings.suggestionsEnabled || settings.autocorrectEnabled, !correctionsDisabled, page == .letters,
              !emojiSearchActive, status == .idle || translateMode else {
            suggestions = []; applyIndex = nil; pendingWord = nil; pendingFix = nil
            if !letterBias.isEmpty { letterBias = [:] }
            return
        }
        let before = currentWord
        let after = wordAfterCaret
        let word = before + after
        let t = textBeforeCaret
        let prev = previousWord
        let prevForPrediction = t.hasSuffix(" ") ? previousWordForPrediction(t) : nil
        let history = correctionHistory[word.lowercased()]
        let language = currentLanguage, layout = currentLayout
        let wantFix = settings.autocorrectEnabled && after.isEmpty && !word.isEmpty
            && lexicon[word.lowercased()] == nil && retypeGuard != word.lowercased()
        let touches = wantFix ? touchesForCurrentWord(word) : nil
        let showBar = settings.suggestionsEnabled
        suggestionGeneration += 1
        let gen = suggestionGeneration
        let wantBias = after.isEmpty
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let fix = wantFix ? Autocorrect.shared.correction(for: word, prev: prev, language: language, layout: layout, touches: touches) : nil
            let bias: [Character: Double] = wantBias
                ? Autocorrect.shared.nextLetterDistribution(prefix: word, prev: word.isEmpty ? prevForPrediction : nil, language: language)
                : [:]
            var next: [String] = []
            var apply: Int? = nil
            if showBar {
                if word.isEmpty {
                    next = prevForPrediction.map { Autocorrect.shared.nextWords(after: $0, language: language) } ?? []
                } else if let fix {
                    // "typed" · ★fix · one alternative
                    let alts = Autocorrect.shared.suggestions(forPartial: word, prev: prev, language: language,
                                                              layout: layout, alwaysFixes: true, limit: 4)
                        .filter { !$0.hasPrefix("\"") && $0 != fix.replacement && $0 != word }
                    next = ["\"\(word)\"", fix.replacement] + alts.prefix(1)
                    apply = 1
                } else {
                    next = Autocorrect.shared.suggestions(forPartial: word, prev: prev, language: language,
                                                          layout: layout, alwaysFixes: !after.isEmpty)
                    if let original = history, original.lowercased() != word.lowercased() {
                        // What the user typed, quoted like the native bar; tapping
                        // it keeps and learns the word.
                        let quoted = "\"\(original)\""
                        next.removeAll { $0 == original || $0 == quoted }
                        next.insert(quoted, at: 0)
                        if next.count > 3 { next.removeLast(next.count - 3) }
                    }
                }
            }
            DispatchQueue.main.async {
                guard let self, gen == self.suggestionGeneration else { return }
                if wantFix { self.pendingWord = word; self.pendingFix = fix } else { self.pendingWord = nil; self.pendingFix = nil }
                if next != self.suggestions { self.suggestions = next }
                if apply != self.applyIndex { self.applyIndex = apply }
                if bias != self.letterBias { self.letterBias = bias }
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
        if emojiSearchActive { insertRaw(" "); return }
        let now = Date()
        // Consecutive space presses (nothing typed in between) — the system
        // keyboard doesn't time them either, it only requires a word before.
        let quick = lastSpaceTap != .distantPast && !periodShortcutDisabled
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
        if autocorrectCurrentWord(separator: " ") { touchTrail.removeAll(); return }
        touchTrail.removeAll()
        insertRaw(" ")
    }

    /// Inserts text where typing currently goes: the composer in translate
    /// mode, the document otherwise.
    private func insertRaw(_ s: String) {
        if emojiSearchActive {
            emojiQuery += s
            emojiResults = EmojiIndex.shared.search(emojiQuery)
            return
        }
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
        host?.playClick(.letter)
        if settings.hapticsEnabled { host?.playHaptic() }
        settings.recordEmoji(e)
        emojiVariants = nil
        if emojiSearchActive {
            // Results go into the document, not the query.
            let base = textBeforeCaret
            lastEditAt = Date()
            if translateMode { composer += e; schedulePreview() } else { host?.proxy.insertText(e); clearUndoIfEdited() }
            afterLocalEdit(before: base + e)
            return
        }
        insertRaw(e)
    }

    private var languageIndexBeforeSearch: Int?

    func startEmojiSearch() {
        host?.playClick(.modifier)
        emojiSearchActive = true
        emojiQuery = ""; emojiResults = []
        emojiVariants = nil
        page = .letters
        // Emoji names are English: search on a Latin layout, lowercase.
        if LetterLayout.forLanguage(currentLanguage) != .latin,
           let latin = keyboardLanguages.firstIndex(where: { LetterLayout.forLanguage($0) == .latin }) {
            languageIndexBeforeSearch = languageIndex
            languageIndex = latin
        }
        shift = .off; shiftIsAuto = false
        hideKeyPreview()
    }

    func endEmojiSearch(backToEmoji: Bool) {
        host?.playClick(.modifier)
        emojiSearchActive = false
        emojiQuery = ""; emojiResults = []
        if let back = languageIndexBeforeSearch, back < keyboardLanguages.count { languageIndex = back }
        languageIndexBeforeSearch = nil
        page = backToEmoji ? .emoji : .letters
        textDidChange()
    }

    func showEmojiVariants(_ e: String) {
        let v = EmojiIndex.shared.variants(of: e)
        guard !v.isEmpty else { return }
        if settings.hapticsEnabled { host?.playHaptic() }
        emojiVariants = [e] + v
    }

    private func backspaceOnce() {
        if emojiSearchActive {
            if !emojiQuery.isEmpty { emojiQuery.removeLast() }
            emojiResults = EmojiIndex.shared.search(emojiQuery)
            return
        }
        lastEditAt = Date()
        if !touchTrail.isEmpty { touchTrail.removeLast() }
        if let ac = lastAutocorrect {
            // Native: Delete after a correction just removes the separator; the
            // typed word comes back as the quoted option in the bar (see
            // correctionHistory) and the same correction won't fire again if
            // the user deletes into the word and retypes it.
            lastAutocorrect = nil
            if textBeforeCaret.hasSuffix(ac.replacement + ac.separator) { retypeGuard = ac.original.lowercased() }
        }
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

    /// Long-press on backspace: ≈100 ms per character for ~20 characters,
    /// then whole words at ≈350 ms — the system's three speeds.
    func startBackspaceRepeat() {
        stopBackspaceRepeat()
        scheduleBackspaceRepeat(interval: 0.1)
    }

    private func scheduleBackspaceRepeat(interval: TimeInterval) {
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.host?.playClick(.delete)
                if self.settings.hapticsEnabled { self.host?.playHaptic() }
                self.backspaceCount += 1
                if self.backspaceCount > 20 {
                    self.deleteWordBackward()
                    if self.backspaceCount == 21 { self.scheduleBackspaceRepeat(interval: 0.35) }
                } else {
                    self.backspaceOnce()
                }
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
        touchTrail.removeAll()
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
        periodShortcutDisabled = [.emailAddress, .URL, .webSearch].contains(proxy.keyboardType ?? .default)

        // Per-field one-offs, applied when the host document changes.
        let docID = proxy.documentIdentifier
        if docID != lastDocumentID {
            lastDocumentID = docID
            let asciiTypes: [UIKeyboardType] = [.asciiCapable, .emailAddress, .URL, .webSearch, .twitter]
            let wantsASCII = asciiTypes.contains(proxy.keyboardType ?? .default)
            if wantsASCII, LetterLayout.forLanguage(currentLanguage) != .latin,
               let latin = keyboardLanguages.firstIndex(where: { LetterLayout.forLanguage($0) == .latin }) {
                languageIndexBeforeASCII = languageIndex
                languageIndex = latin
            } else if !wantsASCII, let back = languageIndexBeforeASCII {
                languageIndexBeforeASCII = nil
                if back < keyboardLanguages.count { languageIndex = back }
            }
            if proxy.keyboardType == .numbersAndPunctuation, page == .letters { page = .numbers }
        }
        let tintTypes: [UIReturnKeyType] = [.go, .search, .send, .done, .join, .route, .emergencyCall, .continue]
        let hasText = !(proxy.documentContextBeforeInput ?? "").isEmpty || !(proxy.documentContextAfterInput ?? "").isEmpty
        let tinted = tintTypes.contains(proxy.returnKeyType ?? .default) && (!(proxy.enablesReturnKeyAutomatically ?? false) || hasText)
        if tinted != returnKeyTinted { returnKeyTinted = tinted }
        let disabled = (proxy.enablesReturnKeyAutomatically ?? false) && !hasText && !translateMode
        if disabled != returnKeyDisabled { returnKeyDisabled = disabled }
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
        guard page == .letters, shift != .caps, !emojiSearchActive else { return }
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
            if let ctx = shiftOffContext, ctx != before { shiftOffContext = nil }
            if start, shift == .off, shiftOffContext == nil { shift = .on; shiftIsAuto = true }
            else if !start, shift == .on, shiftIsAuto { shift = .off }
            return
        }
        let atSentenceStart: Bool = {
            if before.isEmpty { return true }
            // Strip trailing whitespace and opening quotes/brackets; a newline
            // anywhere in that tail is a sentence start on its own.
            var t = Substring(before)
            var sawGap = false
            while let l = t.last, l.isWhitespace || l.isNewline || "«\"“‘'([".contains(l) {
                if l.isNewline { return true }
                if l.isWhitespace { sawGap = true }
                t = t.dropLast()
            }
            if t.isEmpty { return true }
            guard sawGap, let last = t.last else { return false }
            return ".!?".contains(last)
        }()
        if let ctx = shiftOffContext, ctx != before { shiftOffContext = nil }
        if atSentenceStart, shift == .off {
            if shiftOffContext == nil { shift = .on; shiftIsAuto = true }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            guard let self, self.previewToken == token else { return }
            self.keyPreview = nil
        }
    }

    func hideKeyPreview() { previewToken += 1; keyPreview = nil }

    // MARK: - Long-press popups

    func showAlternates(for glyph: String, keyFrame: CGRect) -> Bool {
        var alts = KeyAlternates.alternates(for: glyph)
        if glyph == ".", [.URL, .emailAddress, .webSearch].contains(host?.proxy.keyboardType ?? .default) {
            alts = [".com", ".net", ".org", ".ua", ".ru", ".edu"]
        }
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
            rememberLanguage()
            page = .letters
        }
    }

    func cancelPopup() { popup = nil }

    func setEngine(_ e: Engine) {
        host?.playClick()
        settings.engine = e
        if e == .claude { settings.adaptStyleEnabled = true }   // style is always on with Claude
        keyMessage = nil
        objectWillChange.send()
        if translateMode { schedulePreview() }
    }

    /// Feedback line under the engine row after Paste key / Clear.
    @Published var keyMessage: String?

    /// API key entry inside the keyboard: from the clipboard (needs Full Access).
    func pasteAPIKey(for engine: Engine) {
        host?.playClick()
        guard host?.hasFullAccess == true else { keyMessage = "Allow Full Access to read the clipboard, or add the key in the Skald app."; return }
        let raw = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { keyMessage = "Clipboard is empty — copy the API key first."; return }
        let looksRight: Bool
        switch engine {
        case .claude: looksRight = raw.hasPrefix("sk-ant-") && raw.count > 20
        case .deepl:  looksRight = raw.count >= 36 && raw.contains("-")
        default:      looksRight = false
        }
        guard looksRight else { keyMessage = "That doesn't look like a \(engine.shortName) key."; return }
        settings.setApiKey(raw, for: engine)
        keyMessage = "\(engine.shortName) key saved."
        objectWillChange.send()
    }

    func clearAPIKey(for engine: Engine) {
        host?.playClick()
        settings.setApiKey(nil, for: engine)
        keyMessage = "\(engine.shortName) key removed."
        objectWillChange.send()
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

    /// ↑ next to the translation field: translate what's in the field, or the
    /// text already before the cursor when the field is empty.
    func sendTranslation() {
        if composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { translate() } else { commitComposer() }
    }

    /// Settings panel: add/remove a layout language (at least one stays).
    func toggleKeyboardLanguage(_ l: Language) {
        host?.playClick()
        var list = settings.keyboardLanguages
        if let i = list.firstIndex(of: l) {
            guard list.count > 1 else { return }
            list.remove(at: i)
        } else {
            list.append(l)
        }
        settings.keyboardLanguages = list
        languageIndex = min(languageIndex, list.count - 1)
        rememberLanguage()
        objectWillChange.send()
        Autocorrect.shared.preload(currentLanguage)
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
