import UIKit

/// Typo correction and word suggestions.
///
/// The system keyboard's autocorrect is a private language model, so parity
/// isn't possible from an extension. This gets close on the common case:
/// a frequency dictionary per language (OpenSubtitles 2018, top 50k words),
/// Norvig-style edit candidates weighted by how plausible the slip is on the
/// current layout (adjacent keys, transpositions), and the system spell
/// checker as a safety net so valid rarer words are left alone.
final class Autocorrect {

    static let shared = Autocorrect()

    struct Correction: Equatable {
        let original: String
        let replacement: String
    }

    // MARK: Dictionaries

    private final class Dictionary {
        let freq: [String: Int]
        let sorted: [String]          // for prefix completions
        let words: [String]           // id → word (file order, shared with the bigram file)
        let ids: [String: Int]
        let total: Double
        // Bigrams: (prevId << 32 | wordId) → count, plus per-prev totals and
        // a per-prev list of followers for next-word prediction.
        var bigrams: [UInt64: UInt32] = [:]
        var prevTotals: [UInt32] = []
        var followers: [Int32: [(Int32, UInt32)]] = [:]

        init(words: [String], freq: [String: Int]) {
            self.words = words
            self.freq = freq
            self.sorted = freq.keys.sorted()
            var ids: [String: Int] = [:]; ids.reserveCapacity(words.count)
            for (i, w) in words.enumerated() { ids[w] = i }
            self.ids = ids
            self.total = Double(freq.values.reduce(0, +))
        }

        func loadBigrams(url: URL) {
            guard let data = try? Data(contentsOf: url), data.count > 12,
                  data[0] == 0x53, data[1] == 0x4B, data[2] == 0x42, data[3] == 0x47 else { return }
            func u32(_ o: Int) -> UInt32 {
                UInt32(data[o]) | UInt32(data[o+1]) << 8 | UInt32(data[o+2]) << 16 | UInt32(data[o+3]) << 24
            }
            let v = Int(u32(4)), n = Int(u32(8))
            guard v == words.count, data.count >= 12 + v * 4 + n * 12 else { return }
            prevTotals = (0..<v).map { u32(12 + $0 * 4) }
            var b: [UInt64: UInt32] = [:]; b.reserveCapacity(n)
            var f: [Int32: [(Int32, UInt32)]] = [:]
            var o = 12 + v * 4
            for _ in 0..<n {
                let p = u32(o), w = u32(o + 4), c = u32(o + 8); o += 12
                b[UInt64(p) << 32 | UInt64(w)] = c
                if f[Int32(p), default: []].count < 12 { f[Int32(p), default: []].append((Int32(w), c)) }  // file is sorted by count
            }
            bigrams = b; followers = f
        }

        func pUni(_ w: String) -> Double { Double(freq[w] ?? 0) / total }

        /// Interpolated probability of `w` given the previous word (or just
        /// its unigram probability when there is no usable context).
        func p(_ w: String, after prev: String?) -> Double {
            let uni = pUni(w)
            guard let prev, let pi = ids[prev.lowercased()], let wi = ids[w], pi < prevTotals.count,
                  prevTotals[pi] >= 20 else { return uni }
            let c = Double(bigrams[UInt64(pi) << 32 | UInt64(wi)] ?? 0)
            let bi = c / Double(prevTotals[pi])
            return 0.75 * bi + 0.25 * uni
        }

        func nextWords(after prev: String, limit: Int) -> [String] {
            guard let pi = ids[prev.lowercased()], let list = followers[Int32(pi)] else { return [] }
            return list.prefix(limit).map { words[Int($0.0)] }
        }
    }

    private var dictionaries: [Language: Dictionary] = [:]
    private let lock = NSLock()

    /// Loads the list for `language` (cached). ~50k lines, a few ms.
    private func dictionary(for language: Language) -> Dictionary? {
        lock.lock(); defer { lock.unlock() }
        if let d = dictionaries[language] { return d }
        guard let url = Bundle.main.url(forResource: "freq_\(language.rawValue)", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var freq: [String: Int] = [:]
        var words: [String] = []
        freq.reserveCapacity(50_000); words.reserveCapacity(50_000)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, let c = Int(parts[1]) {
                let w = String(parts[0]); freq[w] = c; words.append(w)
            }
        }
        let d = Dictionary(words: words, freq: freq)
        if let b = Bundle.main.url(forResource: "bigrams_\(language.rawValue)", withExtension: "bin") {
            d.loadBigrams(url: b)
        }
        dictionaries[language] = d
        evictIfNeeded(keeping: language)
        return d
    }

    /// Warm the cache off the main thread when the keyboard appears. Only the
    /// current layout's language: each loaded language costs ~10 MB and the
    /// extension's memory budget is small.
    func preload(_ language: Language) {
        DispatchQueue.global(qos: .userInitiated).async { _ = self.dictionary(for: language) }
    }

    /// Drop other languages once more than two are resident.
    private func evictIfNeeded(keeping language: Language) {
        guard dictionaries.count > 2 else { return }
        for k in dictionaries.keys where k != language { dictionaries.removeValue(forKey: k); break }
    }

    // MARK: Personal lexicon (learns from you)

    /// Words you kept after Skald tried to change them, or typed repeatedly
    /// while unknown: never auto-corrected again, offered in suggestions.
    private(set) var personalWords: [String: Int] = [:]
    /// Fixes you picked from the suggestion bar: typed (lowercased) → chosen.
    private(set) var personalFixes: [String: String] = [:]
    /// Unknown words typed once — the second time they graduate to personalWords.
    private var seenUnknown: [String: Int] = [:]

    private let settings = SkaldSettings.shared

    func loadPersonal() {
        personalWords = settings.learnedWords
        personalFixes = settings.learnedFixes
    }

    /// The user rejected a correction (backspace revert, "keep as typed").
    func learnWord(_ word: String) {
        let w = word.lowercased()
        guard w.count >= 2 else { return }
        personalWords[w, default: 0] += 2
        personalFixes.removeValue(forKey: w)
        settings.learnedWords = personalWords
        settings.learnedFixes = personalFixes
    }

    /// The user picked `fix` for `typed` from the bar.
    func learnFix(typed: String, fix: String) {
        let t = typed.lowercased(), f = fix.lowercased()
        guard t != f, t.count >= 2 else { return }
        personalFixes[t] = f
        personalWords.removeValue(forKey: t)
        settings.learnedFixes = personalFixes
        settings.learnedWords = personalWords
    }

    /// An unknown word was left as typed (no correction applied). Twice → learned.
    func noteUnknownKept(_ word: String) {
        let w = word.lowercased()
        seenUnknown[w, default: 0] += 1
        if seenUnknown[w]! >= 2 { learnWord(w); seenUnknown.removeValue(forKey: w) }
    }

    private func isPersonal(_ lower: String) -> Bool { personalWords[lower] != nil }

    /// True when `word` is unknown to every dictionary (so leaving it as typed
    /// is a signal worth learning from).
    func correctionWouldHaveConsidered(_ word: String, language: Language) -> Bool {
        let lower = word.lowercased()
        guard word.count >= 3, !isPersonal(lower), let dict = dictionary(for: language) else { return false }
        return dict.freq[lower] == nil && !isKnownToSystem(word, language: language)
    }

    // MARK: System spell checker (validity only)

    private let checker = UITextChecker()

    private static func checkerLanguage(for language: Language) -> String? {
        let available = UITextChecker.availableLanguages
        if available.contains(language.rawValue) { return language.rawValue }
        return available.first { $0.hasPrefix(language.rawValue + "_") || $0.hasPrefix(language.rawValue + "-") }
    }

    private func isKnownToSystem(_ word: String, language: Language) -> Bool {
        guard let lang = Self.checkerLanguage(for: language) else { return false }
        let r = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: (word as NSString).length),
                                              startingAt: 0, wrap: false, language: lang)
        return r.location == NSNotFound
    }

    // MARK: Correction

    /// Best correction for a finished word, or nil to leave it alone.
    /// `prev` is the word before it (context for the bigram model).
    func correction(for word: String, prev: String?, language: Language, layout: LetterLayout) -> Correction? {
        guard word.count >= 3, let dict = dictionary(for: language) else { return nil }
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }) else { return nil }
        if word == word.uppercased() { return nil }                         // acronyms
        let lower = word.lowercased()
        if isPersonal(lower) { return nil }                                  // you told us to keep it
        if let f = personalFixes[lower], dict.freq[f] != nil || isPersonal(f) {
            return Correction(original: word, replacement: Self.matchCase(of: word, to: f))
        }
        let known = dict.freq[lower] != nil
        if !known, isKnownToSystem(word, language: language) { return nil } // rarer but valid
        // Known and reasonably common: leave it. Known but rare, lowercase,
        // ≥4 letters: still a candidate for a context fix ("тепер" → "теперь").
        if known, (dict.freq[lower]! >= 300 || word.first!.isUppercase || word.count < 4) { return nil }

        let adjacency = Self.adjacency(for: layout)
        let alphabet = Self.alphabet(for: layout)
        var best: (word: String, score: Double)?
        func consider(_ cand: String, weight: Double) {
            guard dict.freq[cand] != nil else { return }
            let s = dict.p(cand, after: prev) * weight
            if best == nil || s > best!.score { best = (cand, s) }
        }
        for (cand, weight) in Self.edits1(lower, alphabet: alphabet, adjacency: adjacency) {
            consider(cand, weight: weight)
        }
        if best == nil, !known, lower.count >= 5 {
            // Second edit restricted to neighbouring keys: ~10× fewer candidates.
            var seen = Set<String>()
            for (e1, w1) in Self.edits1(lower, alphabet: alphabet, adjacency: adjacency) {
                for (e2, w2) in Self.edits1(e1, alphabet: alphabet, adjacency: adjacency, narrow: true) where !seen.contains(e2) {
                    seen.insert(e2)
                    consider(e2, weight: w1 * w2 * 0.05)
                }
            }
        }
        guard let b = best, b.word != lower else { return nil }
        guard let f = dict.freq[b.word], f >= 30 else { return nil }         // nothing obscure
        if known {
            // Only override a real word when context makes the fix far likelier.
            guard b.score > dict.p(lower, after: prev) * 40 else { return nil }
        }
        return Correction(original: word, replacement: Self.matchCase(of: word, to: b.word))
    }

    /// Likely next words after `prev` (for the suggestion bar when the caret
    /// sits after a space).
    func nextWords(after prev: String, language: Language, limit: Int = 3) -> [String] {
        guard let dict = dictionary(for: language) else { return [] }
        return dict.nextWords(after: prev, limit: limit)
    }

    /// Suggestions for the word at the caret: the word itself (quoted) when it
    /// isn't known, then the likeliest fixes/completions by context-aware
    /// probability. `alwaysFixes` also offers alternatives for known words
    /// (tap-on-word).
    func suggestions(forPartial word: String, prev: String?, language: Language, layout: LetterLayout,
                     alwaysFixes: Bool = false, limit: Int = 3) -> [String] {
        guard !word.isEmpty, let dict = dictionary(for: language) else { return [] }
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }) else { return [] }
        let lower = word.lowercased()
        var out: [String] = []
        let known = dict.freq[lower] != nil || isPersonal(lower) || isKnownToSystem(word, language: language)
        if !known, word.count >= 2 { out.append("\"\(word)\"") }
        if let f = personalFixes[lower] { out.append(Self.matchCase(of: word, to: f)) }

        var scored: [(String, Double)] = []
        let s = dict.sorted
        var lo = 0, hi = s.count
        while lo < hi { let m = (lo + hi) / 2; if s[m] < lower { lo = m + 1 } else { hi = m } }
        var i = lo
        while i < s.count, s[i].hasPrefix(lower), scored.count < 400 {
            if s[i] != lower {
                scored.append((s[i], dict.p(s[i], after: prev) * (s[i].count <= lower.count + 4 ? 1 : 0.3)))
            }
            i += 1
        }
        if (!known || alwaysFixes), word.count >= 3 {
            let adjacency = Self.adjacency(for: layout)
            for (cand, w) in Self.edits1(lower, alphabet: Self.alphabet(for: layout), adjacency: adjacency) {
                if dict.freq[cand] != nil, cand != lower { scored.append((cand, dict.p(cand, after: prev) * w * 2)) }
            }
        }
        var seen = Set<String>()
        for (w, _) in scored.sorted(by: { $0.1 > $1.1 }) where out.count < limit {
            let cased = Self.matchCase(of: word, to: w)
            if !seen.contains(w), cased != word { seen.insert(w); out.append(cased) }
        }
        return out
    }

    // MARK: Edits

    /// Single-edit candidates with a plausibility weight (higher = likelier slip).
    private static func edits1(_ w: String, alphabet: [Character], adjacency: [Character: Set<Character>],
                               narrow: Bool = false) -> [(String, Double)] {
        let chars = Array(w)
        var out: [(String, Double)] = []
        out.reserveCapacity(chars.count * (alphabet.count * 2 + 2))
        for i in 0...chars.count {
            // deletion
            if i < chars.count {
                var d = chars; d.remove(at: i); out.append((String(d), 1.0))
            }
            // transposition
            if i < chars.count - 1 {
                var t = chars; t.swapAt(i, i + 1); out.append((String(t), 2.0))
            }
            let letters: [Character] = narrow
                ? Array((i < chars.count ? adjacency[chars[i]] ?? [] : []).union(i > 0 ? adjacency[chars[i - 1]] ?? [] : []))
                : alphabet
            for c in letters {
                // substitution — much likelier when the keys are neighbours
                if i < chars.count, c != chars[i] {
                    var s = chars; s[i] = c
                    let near = adjacency[chars[i]]?.contains(c) ?? false
                    out.append((String(s), near ? 3.0 : 0.7))
                }
                // insertion
                var ins = chars; ins.insert(c, at: i); out.append((String(ins), 1.0))
            }
        }
        return out
    }

    private static var alphabetCache: [String: [Character]] = [:]
    private static var adjacencyCache: [String: [Character: Set<Character>]] = [:]

    private static func alphabet(for layout: LetterLayout) -> [Character] {
        if let a = alphabetCache[layout.id] { return a }
        var set = Set<Character>()
        for row in layout.rows { for k in row { for ch in k { set.insert(ch) } } }
        for (_, alts) in KeyAlternates.table { for a in alts { if let ch = a.first, ch.isLetter, set.contains(a.lowercased().first!) == false { set.insert(ch) } } }
        let a = Array(set).sorted()
        alphabetCache[layout.id] = a
        return a
    }

    /// Keys touching each other on the layout (same row ±1, rows above/below ±1).
    private static func adjacency(for layout: LetterLayout) -> [Character: Set<Character>] {
        if let a = adjacencyCache[layout.id] { return a }
        var adj: [Character: Set<Character>] = [:]
        let rows = layout.rows.map { $0.compactMap { $0.first } }
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                var n = Set<Character>()
                for dc in [-1, 1] where row.indices.contains(c + dc) { n.insert(row[c + dc]) }
                for dr in [-1, 1] where rows.indices.contains(r + dr) {
                    let other = rows[r + dr]
                    // rows are offset by about half a key; take the two nearest
                    let shift = other.count < row.count ? -1 : 0
                    for dc in [0, 1] { let j = c + dc + shift; if other.indices.contains(j) { n.insert(other[j]) } }
                }
                adj[ch] = n
            }
        }
        adjacencyCache[layout.id] = adj
        return adj
    }

    static func matchCase(of source: String, to target: String) -> String {
        guard let first = source.first, first.isUppercase else { return target }
        if source == source.uppercased(), source.count > 1 { return target.uppercased() }
        return target.prefix(1).uppercased() + target.dropFirst()
    }
}
