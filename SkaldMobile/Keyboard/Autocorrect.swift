import UIKit

/// Typo correction and word suggestions.
///
/// The system keyboard's autocorrect is a private language model, so parity
/// isn't possible from an extension. This gets close on the common case:
/// a frequency dictionary per language (OpenSubtitles 2018, top 50k words),
/// Norvig-style edit candidates weighted by a touch model (how likely the
/// finger that produced each letter was actually aiming at the proposed
/// one), the system spell checker as a safety net so valid rarer words are
/// left alone, and the system dictionary's own guesses for word forms the
/// 50k list lacks.
final class Autocorrect {

    static let shared = Autocorrect()

    struct Correction: Equatable {
        let original: String
        let replacement: String
    }

    // MARK: Thresholds

    /// Frequency thresholds as a share of the corpus, so they mean the same
    /// for every language: the Ukrainian list has 30× fewer tokens than the
    /// Russian one, and absolute counts left half of its typos "too obscure
    /// to fix". Calibrated on the Russian list (300 and 30 occurrences in
    /// 144 M tokens).
    private static let commonP = 2.1e-6      // trusted as is, no need to ask the system checker
    private static let floorP  = 2.1e-7      // least frequency worth correcting into

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
            return list.lazy.map { self.words[Int($0.0)] }.filter { self.freq[$0] != nil }.prefix(limit).map { $0 }
        }
    }

    private var dictionaries: [Language: Dictionary] = [:]
    private let lock = NSLock()

    /// Lines of the subtitle lists that belong to the other language (the
    /// Ukrainian corpus is full of Russian subtitles): kept for bigram id
    /// alignment, never offered or protected.
    private static func isJunk(_ word: String, for language: Language) -> Bool {
        switch language {
        case .ukrainian: return word.contains { "ыэъё".contains($0) }
        case .russian:   return word.contains { "іїєґ".contains($0) }
        default:         return false
        }
    }

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
                let w = String(parts[0])
                words.append(w)
                if !Self.isJunk(w, for: language) { freq[w] = c }
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
    /// Unknown words left as typed — the third time they graduate to personalWords.
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

    /// An unknown word was left as typed (no correction applied). Three
    /// times → learned, unless the system dictionary has a one-edit fix for
    /// it: that is a typo we failed to place, not vocabulary. The checker
    /// call runs off the main thread; the lexicon is touched on it.
    func noteUnknownKept(_ word: String, language: Language) {
        let w = word.lowercased()
        guard w.count >= 2 else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            if let guesses = systemGuesses(w, language: language),
               guesses.contains(where: { Self.editDistance($0.lowercased(), w, limit: 1) <= 1 }) { return }
            DispatchQueue.main.async {
                self.seenUnknown[w, default: 0] += 1
                if self.seenUnknown[w]! >= 3 { self.learnWord(w); self.seenUnknown.removeValue(forKey: w) }
            }
        }
    }

    /// Names from Contacts and words protected via Text Replacement (blank
    /// shortcut), delivered by UILexicon: never corrected, offered as known.
    private var externalWords: Set<String> = []
    func setExternalWords(_ words: Set<String>) { externalWords = words }

    private func isPersonal(_ lower: String) -> Bool { personalWords[lower] != nil || externalWords.contains(lower) }

    /// English contractions the system fixes without a dictionary lookup.
    private static let contractionsEN: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've", "dont": "don't", "cant": "can't", "wont": "won't",
        "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't", "werent": "weren't", "didnt": "didn't",
        "doesnt": "doesn't", "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't",
        "couldnt": "couldn't", "wouldnt": "wouldn't", "shouldnt": "shouldn't", "mustnt": "mustn't",
        "youre": "you're", "youll": "you'll", "youve": "you've", "youd": "you'd",
        "theyre": "they're", "theyll": "they'll", "theyve": "they've", "theyd": "they'd",
        "weve": "we've", "thats": "that's", "whats": "what's", "hes": "he's", "shes": "she's",
        "theres": "there's", "heres": "here's", "wheres": "where's", "whos": "who's", "hows": "how's",
        "i'm": "I'm", "i've": "I've", "i'll": "I'll", "i'd": "I'd",
    ]

    /// True when `word` is unknown to every dictionary (so leaving it as typed
    /// is a signal worth learning from).
    func correctionWouldHaveConsidered(_ word: String, language: Language) -> Bool {
        let lower = word.lowercased()
        guard word.count >= 3, !isPersonal(lower), let dict = dictionary(for: language) else { return false }
        return dict.freq[lower] == nil && !isKnownToSystem(word, language: language)
    }

    // MARK: System spell checker (validity + guesses)

    private let checker = UITextChecker()
    private let checkerLock = NSLock()      // UITextChecker is not documented thread-safe
    private static var checkerLanguages: [Language: String?] = [:]

    private static func checkerLanguage(for language: Language) -> String? {
        if let cached = checkerLanguages[language] { return cached }
        let available = UITextChecker.availableLanguages
        let found: String? = available.contains(language.rawValue) ? language.rawValue
            : available.first { $0.hasPrefix(language.rawValue + "_") || $0.hasPrefix(language.rawValue + "-") }
        checkerLanguages[language] = found
        return found
    }

    private func isKnownToSystem(_ word: String, language: Language) -> Bool {
        guard let lang = Self.checkerLanguage(for: language) else { return false }
        checkerLock.lock(); defer { checkerLock.unlock() }
        let r = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: (word as NSString).length),
                                              startingAt: 0, wrap: false, language: lang)
        return r.location == NSNotFound
    }

    /// The system dictionary's own fixes for a misspelled word. Covers the
    /// forms the 50k list lacks (most of Ukrainian's inflections); ranked
    /// by the system, re-scored here with the touch model.
    private func systemGuesses(_ word: String, language: Language) -> [String]? {
        guard let lang = Self.checkerLanguage(for: language) else { return nil }
        checkerLock.lock(); defer { checkerLock.unlock() }
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.guesses(forWordRange: range, in: word, language: lang)
    }

    // MARK: Correction

    /// Best correction for a finished word, or nil to leave it alone.
    /// `prev` is the word before it (context for the bigram model);
    /// `touches` the touch likelihoods recorded per typed letter.
    func correction(for word: String, prev: String?, language: Language, layout: LetterLayout,
                    touches: [[Character: Double]]? = nil) -> Correction? {
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }) else { return nil }
        if word == word.uppercased(), word.count > 1 { return nil }          // acronyms
        let lower = word.lowercased().replacingOccurrences(of: "’", with: "'")
        if isPersonal(lower) { return nil }                                  // you told us to keep it
        if language == .english, let c = Self.contractionsEN[lower] {
            let cased = c.hasPrefix("I") ? c : Self.matchCase(of: word, to: c)
            if cased != word { return Correction(original: word, replacement: cased) }
            return nil
        }
        guard word.count >= 3, let dict = dictionary(for: language) else { return nil }
        if let f = personalFixes[lower], dict.freq[f] != nil || isPersonal(f) {
            return Correction(original: word, replacement: Self.matchCase(of: word, to: f))
        }
        // A word the corpus or the system dictionary vouches for is never
        // replaced — like the system keyboard, alternatives go to the bar.
        // A rare corpus entry the system rejects is subtitle junk or a typo
        // that made it into the corpus ("утебя", "наете"): corrected like an
        // unknown word, with a margin.
        let known = dict.freq[lower] != nil
        if known, dict.pUni(lower) >= Self.commonP || word.first!.isUppercase || word.count < 4 { return nil }
        if isKnownToSystem(word, language: language) { return nil }

        let adjacency = Self.adjacency(for: layout)
        let alphabet = Self.alphabet(for: layout)
        let touchMaps = (touches?.count == lower.count) ? touches : nil
        var best: (word: String, score: Double, inDictionary: Bool)?
        func consider(_ cand: String, p: Double, weight: Double, inDictionary: Bool) {
            let s = p * weight
            if best == nil || s > best!.score { best = (cand, s, inDictionary) }
        }
        let first = Self.edits1(lower, alphabet: alphabet, adjacency: adjacency, touches: touchMaps)
        for (cand, weight) in first where dict.freq[cand] != nil {
            consider(cand, p: dict.p(cand, after: prev), weight: weight, inDictionary: true)
        }
        if best == nil, !known, lower.count >= 5 {
            // Second edit restricted to neighbouring keys: ~10× fewer candidates.
            var seen = Set<String>()
            for (e1, w1) in first {
                for (e2, w2) in Self.edits1(e1, alphabet: alphabet, adjacency: adjacency, narrow: true)
                where !seen.contains(e2) && dict.freq[e2] != nil {
                    seen.insert(e2)
                    consider(e2, p: dict.p(e2, after: prev), weight: w1 * w2 * 0.05, inDictionary: true)
                }
            }
        }
        // System-dictionary candidates: forms the list lacks. An unknown form
        // competes like the rarest word we would still correct into, decaying
        // down the system's ranking; the touch model decides between them.
        if word.count >= 4, let guesses = systemGuesses(word, language: language) {
            var firstWeight: [String: Double] = [:]
            for (c, w) in first { firstWeight[c] = max(firstWeight[c] ?? 0, w) }
            for (rank, guess) in guesses.prefix(6).enumerated() {
                let g = guess.lowercased().replacingOccurrences(of: "’", with: "'")
                guard g != lower, !g.isEmpty else { continue }
                let weight: Double
                if let w = firstWeight[g] { weight = w }
                else if g.replacingOccurrences(of: " ", with: "") == lower { weight = 0.12 }   // утебя → у тебя
                else if Self.editDistance(g, lower, limit: 2) == 2 { weight = 0.005 }
                else { continue }
                let inDict = dict.freq[g] != nil
                let p = inDict ? dict.p(g, after: prev) : Self.floorP * pow(0.6, Double(rank))
                consider(g, p: p, weight: weight, inDictionary: inDict)
            }
        }
        guard let b = best, b.word != lower else { return nil }
        if b.inDictionary, dict.pUni(b.word) < Self.floorP { return nil }     // nothing obscure
        if known {
            // Rare corpus entry the system rejects: still needs a clear margin.
            guard b.score > dict.p(lower, after: prev) * 10 else { return nil }
        }
        return Correction(original: word, replacement: Self.matchCase(of: word, to: b.word))
    }

    /// Likelihood (0…1, max-normalised) of each next letter given the word
    /// prefix typed so far — or, at a word start, the first letters of the
    /// likely next words. Drives the dynamic key hit areas.
    func nextLetterDistribution(prefix: String, prev: String?, language: Language) -> [Character: Double] {
        guard let dict = dictionary(for: language) else { return [:] }
        var acc: [Character: Double] = [:]
        let lower = prefix.lowercased()
        if lower.isEmpty {
            guard let prev else { return [:] }
            for (i, w) in dict.nextWords(after: prev, limit: 12).enumerated() {
                if let c = w.first { acc[c, default: 0] += Double(12 - i) }
            }
        } else {
            let s = dict.sorted
            var lo = 0, hi = s.count
            while lo < hi { let m = (lo + hi) / 2; if s[m] < lower { lo = m + 1 } else { hi = m } }
            var i = lo, scanned = 0
            while i < s.count, s[i].hasPrefix(lower), scanned < 600 {
                let w = s[i]
                if w.count > lower.count {
                    let c = w[w.index(w.startIndex, offsetBy: lower.count)]
                    acc[c, default: 0] += Double(dict.freq[w] ?? 0)
                }
                i += 1; scanned += 1
            }
        }
        guard let top = acc.values.max(), top > 0 else { return [:] }
        return acc.mapValues { $0 / top }
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
        let lower = word.lowercased().replacingOccurrences(of: "’", with: "'")
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
                if dict.freq[cand] != nil, cand != lower { scored.append((cand, dict.p(cand, after: prev) * w * 6)) }
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

    /// Single-edit candidates with a plausibility weight — the probability
    /// of the slip relative to a boundary tap on the right key (= 1).
    /// Priors match a touchscreen: a neighbouring-key substitution is the
    /// common slip, a dropped or stray tap is next, a transposition is rare.
    /// `touches`, when present, holds for each typed letter the Gaussian
    /// touch likelihood of every nearby key (see KeyTouchUIView); a
    /// substitution is then weighted by the likelihood ratio of the proposed
    /// key to the typed one, so a tap near a key boundary makes its
    /// neighbour a strong candidate and a tap in the middle of a key does
    /// not. Without touch data the static adjacency table stands in.
    private static func edits1(_ w: String, alphabet: [Character], adjacency: [Character: Set<Character>],
                               narrow: Bool = false, touches: [[Character: Double]]? = nil) -> [(String, Double)] {
        let chars = Array(w)
        var out: [(String, Double)] = []
        out.reserveCapacity(chars.count * (alphabet.count * 2 + 2))
        for i in 0...chars.count {
            // dropped tap
            if i < chars.count {
                var d = chars; d.remove(at: i); out.append((String(d), 0.12))
            }
            // transposition
            if i < chars.count - 1 {
                var t = chars; t.swapAt(i, i + 1); out.append((String(t), 0.05))
            }
            let letters: [Character] = narrow
                ? Array((i < chars.count ? adjacency[chars[i]] ?? [] : []).union(i > 0 ? adjacency[chars[i - 1]] ?? [] : []))
                : alphabet
            let nearPrev = i > 0 ? adjacency[chars[i - 1]] : nil
            let nearHere = i < chars.count ? adjacency[chars[i]] : nil
            for c in letters {
                // substitution
                if i < chars.count, c != chars[i] {
                    var s = chars; s[i] = c
                    let weight: Double
                    if let t = touches, i < t.count, let typed = t[i][chars[i]], typed > 0 {
                        weight = min(1, max(0.001, (t[i][c] ?? 0) / typed))
                    } else {
                        weight = (nearHere?.contains(c) ?? false) ? 0.5 : 0.01
                    }
                    out.append((String(s), weight))
                }
                // stray tap: likelier next to a key that was hit anyway
                var ins = chars; ins.insert(c, at: i)
                let near = (nearHere?.contains(c) ?? false) || (nearPrev?.contains(c) ?? false)
                out.append((String(ins), near ? 0.12 : 0.02))
            }
        }
        return out
    }

    /// Optimal-string-alignment edit distance (insert, delete, substitute,
    /// swap adjacent), capped at `limit + 1`.
    static func editDistance(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return max(a.count, b.count) }
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prev2: [Int] = [], prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            var rowMin = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { v = min(v, prev2[j - 2] + 1) }
                cur[j] = v; rowMin = min(rowMin, v)
            }
            if rowMin > limit { return limit + 1 }
            prev2 = prev; prev = cur
        }
        return prev[b.count]
    }

    private static var alphabetCache: [String: [Character]] = [:]
    private static var adjacencyCache: [String: [Character: Set<Character>]] = [:]

    private static func alphabet(for layout: LetterLayout) -> [Character] {
        if let a = alphabetCache[layout.id] { return a }
        var set = Set<Character>()
        for row in layout.rows { for k in row { for ch in k { set.insert(ch) } } }
        for (_, alts) in KeyAlternates.table { for a in alts { if let ch = a.first, ch.isLetter, set.contains(a.lowercased().first!) == false { set.insert(ch) } } }
        set.insert("'")                                       // dropped apostrophes: dont → don't
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
