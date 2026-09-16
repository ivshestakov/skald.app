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
        init(freq: [String: Int]) {
            self.freq = freq
            self.sorted = freq.keys.sorted()
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
        freq.reserveCapacity(50_000)
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2, let c = Int(parts[1]) { freq[String(parts[0])] = c }
        }
        let d = Dictionary(freq: freq)
        dictionaries[language] = d
        return d
    }

    /// Warm the cache off the main thread when the keyboard appears.
    func preload(_ languages: [Language]) {
        DispatchQueue.global(qos: .utility).async {
            for l in languages { _ = self.dictionary(for: l) }
        }
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
    func correction(for word: String, language: Language, layout: LetterLayout) -> Correction? {
        guard word.count >= 3, let dict = dictionary(for: language) else { return nil }
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }) else { return nil }
        if word == word.uppercased() { return nil }                         // acronyms
        let lower = word.lowercased()
        if dict.freq[lower] != nil { return nil }                           // a real word
        if isKnownToSystem(word, language: language) { return nil }        // rarer but valid

        let adjacency = Self.adjacency(for: layout)
        var best: (word: String, score: Double)?
        func consider(_ cand: String, weight: Double) {
            guard let f = dict.freq[cand] else { return }
            let s = Double(f) * weight
            if best == nil || s > best!.score { best = (cand, s) }
        }
        for (cand, weight) in Self.edits1(lower, alphabet: Self.alphabet(for: layout), adjacency: adjacency) {
            consider(cand, weight: weight)
        }
        if best == nil, lower.count >= 5 {
            // Two edits: only via candidates that are themselves plausible.
            var seen = Set<String>()
            for (e1, w1) in Self.edits1(lower, alphabet: Self.alphabet(for: layout), adjacency: adjacency) {
                for (e2, w2) in Self.edits1(e1, alphabet: Self.alphabet(for: layout), adjacency: adjacency) where !seen.contains(e2) {
                    seen.insert(e2)
                    consider(e2, weight: w1 * w2 * 0.05)
                }
            }
        }
        guard let b = best, b.word != lower else { return nil }
        // Don't "fix" into something obscure.
        guard let f = dict.freq[b.word], f >= 30 else { return nil }
        return Correction(original: word, replacement: Self.matchCase(of: word, to: b.word))
    }

    /// Suggestions for the word being typed: the word itself (quoted) when
    /// it isn't known, then the likeliest fixes/completions by frequency.
    func suggestions(forPartial word: String, language: Language, layout: LetterLayout, limit: Int = 3) -> [String] {
        guard !word.isEmpty, let dict = dictionary(for: language) else { return [] }
        guard word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-" }) else { return [] }
        let lower = word.lowercased()
        var out: [String] = []
        let known = dict.freq[lower] != nil || isKnownToSystem(word, language: language)
        if !known, word.count >= 2 { out.append("\"\(word)\"") }

        var scored: [(String, Double)] = []
        // completions
        let s = dict.sorted
        var lo = 0, hi = s.count
        while lo < hi { let m = (lo + hi) / 2; if s[m] < lower { lo = m + 1 } else { hi = m } }
        var i = lo
        while i < s.count, s[i].hasPrefix(lower), scored.count < 400 {
            if s[i] != lower { scored.append((s[i], Double(dict.freq[s[i]] ?? 0) * (s[i].count <= lower.count + 4 ? 1 : 0.3))) }
            i += 1
        }
        // fixes
        if !known, word.count >= 3 {
            let adjacency = Self.adjacency(for: layout)
            for (cand, w) in Self.edits1(lower, alphabet: Self.alphabet(for: layout), adjacency: adjacency) {
                if let f = dict.freq[cand] { scored.append((cand, Double(f) * w * 2)) }
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
    private static func edits1(_ w: String, alphabet: [Character], adjacency: [Character: Set<Character>]) -> [(String, Double)] {
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
            for c in alphabet {
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
