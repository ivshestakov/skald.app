import Foundation

/// Emoji names (English, from Unicode emoji-test.txt) and skin-tone
/// variants, loaded lazily from `emoji-names.txt` (glyph ⇥ name ⇥ tones).
final class EmojiIndex {
    static let shared = EmojiIndex()

    private(set) var names: [String: String] = [:]
    private(set) var tones: [String: [String]] = [:]
    private var loaded = false
    private let lock = NSLock()

    func load() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "emoji-names", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let glyph = String(parts[0])
            names[glyph] = String(parts[1]).lowercased()
            if parts.count >= 3, !parts[2].isEmpty {
                tones[glyph] = parts[2].split(separator: ",").map(String.init)
            }
        }
    }

    /// Emoji whose name contains every word of the query, most common first
    /// (category order of the shipped list is roughly by popularity).
    func search(_ query: String, limit: Int = 24) -> [String] {
        load()
        let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        var out: [String] = []
        for cat in EmojiData.categories {
            for e in cat.emoji {
                guard let n = names[e] else { continue }
                if words.allSatisfy({ n.contains($0) }) {
                    out.append(e)
                    if out.count >= limit { return out }
                }
            }
        }
        return out
    }

    func variants(of glyph: String) -> [String] {
        load()
        return tones[glyph] ?? []
    }
}
