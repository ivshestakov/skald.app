import AppKit
import Foundation
import Security

enum Language: String, CaseIterable {
    case english    = "en"
    case russian    = "ru"
    case ukrainian  = "uk"
    case german     = "de"
    case french     = "fr"
    case spanish    = "es"
    case italian    = "it"
    case portuguese = "pt"
    case polish     = "pl"
    case dutch      = "nl"
    case chinese    = "zh"
    case japanese   = "ja"
    case korean     = "ko"

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .russian:    return "Russian"
        case .ukrainian:  return "Ukrainian"
        case .german:     return "German"
        case .french:     return "French"
        case .spanish:    return "Spanish"
        case .italian:    return "Italian"
        case .portuguese: return "Portuguese"
        case .polish:     return "Polish"
        case .dutch:      return "Dutch"
        case .chinese:    return "Chinese"
        case .japanese:   return "Japanese"
        case .korean:     return "Korean"
        }
    }

    var flag: String {
        switch self {
        case .english:    return "🇬🇧"
        case .russian:    return "🇷🇺"
        case .ukrainian:  return "🇺🇦"
        case .german:     return "🇩🇪"
        case .french:     return "🇫🇷"
        case .spanish:    return "🇪🇸"
        case .italian:    return "🇮🇹"
        case .portuguese: return "🇵🇹"
        case .polish:     return "🇵🇱"
        case .dutch:      return "🇳🇱"
        case .chinese:    return "🇨🇳"
        case .japanese:   return "🇯🇵"
        case .korean:     return "🇰🇷"
        }
    }

    var googleCode: String { rawValue }
    var deepLCode:  String { rawValue.uppercased() }
}

enum Engine: String, CaseIterable {
    case apple
    case google
    case deepl
    case claude

    var displayName: String {
        switch self {
        case .apple:  return "Apple (on-device, offline)"
        case .google: return "Google (free, no key)"
        case .deepl:  return "DeepL"
        case .claude: return "Claude (Anthropic)"
        }
    }
}

/// Tone/register axis for LLM-based translation. Ordered from cold/formal
/// to crude/vulgar, which doubles as the draw order on the gradient slider.
enum Tone: Int, CaseIterable {
    case corporate = 0
    case simple    = 1
    case original  = 2   // default — mirrors the source
    case youth     = 3
    case vulgar    = 4

    var displayName: String {
        switch self {
        case .corporate: return "Corporate"
        case .simple:    return "Simple & Short"
        case .original:  return "Original"
        case .youth:     return "Youth Slang"
        case .vulgar:    return "Vulgar"
        }
    }

    /// Short uppercase label used on the slider tick row.
    var shortLabel: String {
        switch self {
        case .corporate: return "CORPORATE"
        case .simple:    return "SIMPLE"
        case .original:  return "ORIGINAL"
        case .youth:     return "YOUTH"
        case .vulgar:    return "VULGAR"
        }
    }

    /// One-line description shown under the slider for the active tone.
    var subtitle: String {
        switch self {
        case .corporate:
            return "Bureaucratic, strictly formal, polite but firm. No slang, no contractions. Short and to the point."
        case .simple:
            return "Stripped for clarity. Plain, short sentences, no jargon, no filler. Understandable on first read."
        case .original:
            return "Mirrors your input's tone, emoji, spelling, and punctuation. Picks the clearest variants while keeping your voice."
        case .youth:
            return "Contemporary slang, internet-speak, playful phrasing. Sounds like a 20-something chatting online."
        case .vulgar:
            return "Crude, aggressive, sharp. Swearing, mockery, and teasing welcome. Matches or exceeds source intensity. Unfiltered."
        }
    }

    /// SF Symbol shown in the input panel's tone pill. Drawn flat in the
    /// same colour as text labels (`textColor`) so the panel reads as a
    /// single coherent typographic surface, not "icon + decoration".
    var symbolName: String {
        switch self {
        case .corporate: return "briefcase.fill"
        case .simple:    return "scissors"
        case .original:  return "equal"
        case .youth:     return "sparkles"
        case .vulgar:    return "flame.fill"
        }
    }

    /// Saturated colour used for the panel tint, the slider gradient, and
    /// the slider thumb's inner dot — all of which sit on the always-dark
    /// HUD surface, so a single vivid colour reads fine.
    var color: NSColor {
        switch self {
        case .corporate: return NSColor(srgbRed: 0.12, green: 0.23, blue: 0.54, alpha: 1.0) // deep blue
        case .simple:    return NSColor(srgbRed: 0.03, green: 0.57, blue: 0.70, alpha: 1.0) // cyan
        case .original:  return NSColor(srgbRed: 0.06, green: 0.73, blue: 0.51, alpha: 1.0) // emerald
        case .youth:     return NSColor(srgbRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0) // amber
        case .vulgar:    return NSColor(srgbRed: 0.86, green: 0.17, blue: 0.17, alpha: 1.0) // red
        }
    }

    /// Adapted colour for text labels that live on system-appearance
    /// backgrounds (Settings window, popover content). The `color` above
    /// fails contrast in at least one appearance for every tone — Corporate
    /// is invisible on dark backgrounds, Youth is unreadable on light ones.
    /// This property uses AppKit's dynamic colour API so each tone gets a
    /// darker shade for light mode and a lighter shade for dark mode.
    var textColor: NSColor {
        let light: NSColor
        let dark: NSColor
        switch self {
        case .corporate:
            light = NSColor(srgbRed: 0.12, green: 0.23, blue: 0.54, alpha: 1.0)
            dark  = NSColor(srgbRed: 0.52, green: 0.64, blue: 1.00, alpha: 1.0)
        case .simple:
            light = NSColor(srgbRed: 0.02, green: 0.44, blue: 0.56, alpha: 1.0)
            dark  = NSColor(srgbRed: 0.35, green: 0.80, blue: 0.95, alpha: 1.0)
        case .original:
            light = NSColor(srgbRed: 0.04, green: 0.52, blue: 0.36, alpha: 1.0)
            dark  = NSColor(srgbRed: 0.32, green: 0.88, blue: 0.66, alpha: 1.0)
        case .youth:
            light = NSColor(srgbRed: 0.62, green: 0.40, blue: 0.02, alpha: 1.0)
            dark  = NSColor(srgbRed: 1.00, green: 0.78, blue: 0.28, alpha: 1.0)
        case .vulgar:
            light = NSColor(srgbRed: 0.72, green: 0.12, blue: 0.12, alpha: 1.0)
            dark  = NSColor(srgbRed: 0.99, green: 0.45, blue: 0.45, alpha: 1.0)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// Directive appended to the Claude system prompt when style adaptation
    /// is enabled. Tuned to push the model firmly toward the requested
    /// register without needing multi-shot examples.
    var promptDirective: String {
        switch self {
        case .corporate:
            return "Use a CORPORATE / BUREAUCRATIC register. Strictly formal. Polite but firm. No slang. No contractions. No filler, no warmth. Keep it concise and to the point, like official correspondence. Standard vocabulary appropriate for business or legal documents."
        case .simple:
            return "Simplify AGGRESSIVELY. Use short, plain sentences. Strip jargon, technical terms, adjectives, hedging, and unnecessary words. Replace complex phrasing with the simplest equivalents. Aim for language an attentive non-expert reader would grasp on first pass."
        case .original:
            return "Mirror the source faithfully. Preserve the speaker's tone, mood, emoji, punctuation quirks, and even spelling irregularities (including intentional typos, unusual capitalisation, or stylistic punctuation). Within that voice, pick the clearest and most natural variants in the target language. Do not formalise, sanitise, or polish."
        case .youth:
            return "Use contemporary YOUTH SLANG — current informal expressions, internet abbreviations, playful phrasing, meme-adjacent language where natural. Sound like a late-teens / early-twenties speaker chatting online with friends. Don't overdo it or parody — just sound fluent in today's informal usage."
        case .vulgar:
            return "Use a CRUDE, AGGRESSIVE, VULGAR register. Profanity, swearing, mockery, and teasing are expected and appropriate. Be unfiltered, pointed, darkly humorous; a sharp jab (подъёб) is fine. Match or exceed the source's intensity; even if the source is mild, render the translation with strong, confrontational language. Do NOT sanitise, soften, or add warnings."
        }
    }
}

enum ClaudeModel: String, CaseIterable {
    // Cheapest & fastest — default for short phrases.
    case haiku  = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-6"
    case opus   = "claude-opus-4-7"

    var displayName: String {
        switch self {
        case .haiku:  return "Haiku 4.5 — fast, ~$0.0001/phrase"
        case .sonnet: return "Sonnet 4.6 — balanced"
        case .opus:   return "Opus 4.7 — top quality, expensive"
        }
    }
}

/// App-wide settings. UserDefaults for non-secret prefs, Keychain for API keys.
final class Settings {

    static let shared = Settings()

    // Keychain service. The `.v2` suffix marks the migration to a
    // wide-open SecAccess (see Keychain.makeWideOpenAccess) — old
    // entries under the bare `com.ivshestakov.skald` service had a
    // strict per-cdhash ACL that prompted on every rebuild. Existing
    // users re-enter their API keys once.
    private static let keychainService = "com.ivshestakov.skald.v2"
    private let defaults = UserDefaults.standard

    private enum Key {
        static let engine          = "skald.engine"
        static let claudeModel     = "skald.claudeModel"
        static let primaryLang     = "skald.primaryLanguage"
        static let secondaryLang   = "skald.secondaryLanguage"
        static let adaptStyle      = "skald.adaptStyleEnabled"
        static let tone            = "skald.tone"
        static let hotkeyKeyCode   = "skald.hotkeyKeyCode"
        static let hotkeyModifiers = "skald.hotkeyModifiers"
        static let hotkeyDisplay   = "skald.hotkeyDisplay"
    }

    private init() {}

    var engine: Engine {
        get {
            if let raw = defaults.string(forKey: Key.engine),
               let e   = Engine(rawValue: raw) { return e }
            return .google
        }
        set { defaults.set(newValue.rawValue, forKey: Key.engine) }
    }

    var claudeModel: ClaudeModel {
        get {
            if let raw = defaults.string(forKey: Key.claudeModel),
               let m   = ClaudeModel(rawValue: raw) { return m }
            return .haiku
        }
        set { defaults.set(newValue.rawValue, forKey: Key.claudeModel) }
    }

    var primaryLanguage: Language {
        get {
            if let raw = defaults.string(forKey: Key.primaryLang),
               let l   = Language(rawValue: raw) { return l }
            return .russian
        }
        set { defaults.set(newValue.rawValue, forKey: Key.primaryLang) }
    }

    var secondaryLanguage: Language {
        get {
            if let raw = defaults.string(forKey: Key.secondaryLang),
               let l   = Language(rawValue: raw) { return l }
            return .english
        }
        set { defaults.set(newValue.rawValue, forKey: Key.secondaryLang) }
    }

    /// Master switch for LLM style adaptation. When off, the Claude system
    /// prompt doesn't include any tone directive. When on, the configured
    /// `tone` is injected. Ignored for Google/DeepL/Apple engines — those
    /// can't accept custom instructions.
    var adaptStyleEnabled: Bool {
        get { defaults.object(forKey: Key.adaptStyle) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.adaptStyle) }
    }

    var tone: Tone {
        get {
            // `integer(forKey:)` returns 0 when missing, which maps to the
            // first case (.corporate). We want .original to be the default,
            // so we distinguish "never set" via `object(forKey:)`.
            if let raw = defaults.object(forKey: Key.tone) as? Int,
               let t   = Tone(rawValue: raw) { return t }
            return .original
        }
        set { defaults.set(newValue.rawValue, forKey: Key.tone) }
    }

    /// Carbon virtual key code for the global hotkey. Default 44 = `/`.
    var hotkeyKeyCode: Int {
        get {
            if let n = defaults.object(forKey: Key.hotkeyKeyCode) as? Int { return n }
            return 44
        }
        set { defaults.set(newValue, forKey: Key.hotkeyKeyCode) }
    }

    /// `NSEvent.ModifierFlags` rawValue for the hotkey. Default = Option.
    var hotkeyModifiers: NSEvent.ModifierFlags {
        get {
            if let raw = defaults.object(forKey: Key.hotkeyModifiers) as? UInt {
                return NSEvent.ModifierFlags(rawValue: raw)
            }
            return [.option]
        }
        set { defaults.set(newValue.rawValue, forKey: Key.hotkeyModifiers) }
    }

    /// Pre-rendered display string for the main key (set at recording time
    /// against the user's keyboard layout). Avoids having to map raw
    /// keycodes to glyphs at draw time.
    var hotkeyDisplay: String {
        get { defaults.string(forKey: Key.hotkeyDisplay) ?? "/" }
        set { defaults.set(newValue, forKey: Key.hotkeyDisplay) }
    }

    func apiKey(for engine: Engine) -> String? {
        Keychain.load(service: Self.keychainService, account: engine.rawValue)
    }

    func setApiKey(_ key: String?, for engine: Engine) {
        if let key, !key.isEmpty {
            Keychain.save(service: Self.keychainService, account: engine.rawValue, value: key)
        } else {
            Keychain.delete(service: Self.keychainService, account: engine.rawValue)
        }
    }
}

/// Thin wrapper around the Keychain Services API for generic passwords.
/// Stored with `kSecAttrAccessibleAfterFirstUnlock` so background HTTP calls
/// made shortly after login still have access.
///
/// Items are written with a deliberately wide-open `SecAccess` (nil
/// trusted-app list, which Apple's headers document as "grants access to
/// all callers"). Reason: Skald is a self-signed dev build whose cdhash
/// changes on every recompile, and the default per-cdhash Keychain ACL
/// would force the user to re-approve on every rebuild. Trade-off: any
/// other tool running as the same user can read these keys — acceptable
/// because the keys are the user's own API credentials on their own Mac.
/// When Skald ships under a Developer ID, switch back to the default
/// ACL: the team-id-anchored designated requirement matches across
/// rebuilds without per-cdhash entries.
enum Keychain {

    private static func makeWideOpenAccess() -> SecAccess? {
        var access: SecAccess?
        let status = SecAccessCreate(
            "Skald API key" as CFString,
            nil,                  // nil trustedList = unrestricted access
            &access
        )
        return status == errSecSuccess ? access : nil
    }

    static func save(service: String, account: String, value: String) {
        delete(service: service, account: account)

        guard let data = value.data(using: .utf8) else { return }
        var item: [String: Any] = [
            kSecClass           as String: kSecClassGenericPassword,
            kSecAttrService     as String: service,
            kSecAttrAccount     as String: account,
            kSecValueData       as String: data,
            kSecAttrAccessible  as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        if let access = makeWideOpenAccess() {
            item[kSecAttrAccess as String] = access
        }
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
