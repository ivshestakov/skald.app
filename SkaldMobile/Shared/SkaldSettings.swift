import Foundation
import Security

/// Settings shared between the container app and the keyboard extension.
///
/// Non-secret preferences live in the App Group `UserDefaults`; API keys in
/// the Keychain, tagged with the App Group as access group so both processes
/// see the same items. Everything the keyboard reads goes through here.
final class SkaldSettings: ObservableObject {

    static let appGroup       = "group.com.ivshestakov.skald"
    static let keychainService = "com.ivshestakov.skald.ios"
    static let keyboardBundleID = "com.ivshestakov.skald.ios.keyboard"

    static let shared = SkaldSettings()

    private let defaults: UserDefaults

    private enum Key {
        static let engine        = "skald.engine"
        static let claudeModel   = "skald.claudeModel"
        static let primaryLang   = "skald.primaryLanguage"
        static let secondaryLang = "skald.secondaryLanguage"
        static let adaptStyle    = "skald.adaptStyleEnabled"
        static let tone          = "skald.tone"
        static let history       = "skald.history"
        static let kbLanguages   = "skald.keyboardLanguages"
        static let recentEmoji   = "skald.recentEmoji"
    }

    private init() {
        // Falls back to standard defaults when the App Group entitlement is
        // missing (e.g. a build signed without it) so the app still runs.
        defaults = UserDefaults(suiteName: Self.appGroup) ?? .standard
    }

    // MARK: - Preferences

    var engine: Engine {
        get { defaults.string(forKey: Key.engine).flatMap(Engine.init) ?? .google }
        set { defaults.set(newValue.rawValue, forKey: Key.engine); objectWillChange.send() }
    }

    var claudeModel: ClaudeModel {
        get { defaults.string(forKey: Key.claudeModel).flatMap(ClaudeModel.init) ?? .haiku }
        set { defaults.set(newValue.rawValue, forKey: Key.claudeModel); objectWillChange.send() }
    }

    var primaryLanguage: Language {
        get { defaults.string(forKey: Key.primaryLang).flatMap(Language.init) ?? .russian }
        set { defaults.set(newValue.rawValue, forKey: Key.primaryLang); objectWillChange.send() }
    }

    var secondaryLanguage: Language {
        get { defaults.string(forKey: Key.secondaryLang).flatMap(Language.init) ?? .english }
        set { defaults.set(newValue.rawValue, forKey: Key.secondaryLang); objectWillChange.send() }
    }

    var adaptStyleEnabled: Bool {
        get { defaults.object(forKey: Key.adaptStyle) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.adaptStyle); objectWillChange.send() }
    }

    var tone: Tone {
        get { (defaults.object(forKey: Key.tone) as? Int).flatMap(Tone.init) ?? .original }
        set { defaults.set(newValue.rawValue, forKey: Key.tone); objectWillChange.send() }
    }

    /// Languages whose layouts the keyboard cycles through with its language
    /// key. Defaults to the translation pair.
    var keyboardLanguages: [Language] {
        get {
            let stored = (defaults.stringArray(forKey: Key.kbLanguages) ?? []).compactMap(Language.init)
            return stored.isEmpty ? [primaryLanguage, secondaryLanguage] : stored
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.kbLanguages); objectWillChange.send() }
    }

    static let recentEmojiLimit = 32

    var recentEmoji: [String] {
        get { defaults.stringArray(forKey: Key.recentEmoji) ?? [] }
        set { defaults.set(Array(newValue.prefix(Self.recentEmojiLimit)), forKey: Key.recentEmoji); objectWillChange.send() }
    }

    func recordEmoji(_ e: String) {
        var list = recentEmoji.filter { $0 != e }
        list.insert(e, at: 0)
        recentEmoji = list
    }

    // MARK: - History (last translations, newest first)

    struct HistoryItem: Codable, Identifiable, Equatable {
        var id = UUID()
        var source: String
        var target: String
        var engine: Engine
        var date = Date()
    }

    static let historyLimit = 50

    var history: [HistoryItem] {
        get {
            guard let data = defaults.data(forKey: Key.history) else { return [] }
            return (try? JSONDecoder().decode([HistoryItem].self, from: data)) ?? []
        }
        set {
            let trimmed = Array(newValue.prefix(Self.historyLimit))
            defaults.set(try? JSONEncoder().encode(trimmed), forKey: Key.history)
            objectWillChange.send()
        }
    }

    func recordHistory(source: String, target: String, engine: Engine) {
        var items = history.filter { $0.source != source }
        items.insert(HistoryItem(source: source, target: target, engine: engine), at: 0)
        history = items
    }

    // MARK: - API keys

    func apiKey(for engine: Engine) -> String? {
        SharedKeychain.load(service: Self.keychainService, account: engine.rawValue)
    }

    func setApiKey(_ key: String?, for engine: Engine) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            SharedKeychain.delete(service: Self.keychainService, account: engine.rawValue)
        } else {
            SharedKeychain.save(service: Self.keychainService, account: engine.rawValue, value: trimmed)
        }
        objectWillChange.send()
    }

    func hasApiKey(for engine: Engine) -> Bool {
        !(apiKey(for: engine) ?? "").isEmpty
    }
}

/// Generic-password Keychain wrapper. Items are stored in the App Group's
/// keychain access group so the keyboard extension can read keys the app
/// saved. If the entitlement is missing (errSecMissingEntitlement) we retry
/// without the group so the app alone still works.
enum SharedKeychain {

    private static let accessGroup = SkaldSettings.appGroup

    private static func baseQuery(service: String, account: String, grouped: Bool) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if grouped { q[kSecAttrAccessGroup as String] = accessGroup }
        return q
    }

    static func save(service: String, account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        for grouped in [true, false] {
            SecItemDelete(baseQuery(service: service, account: account, grouped: grouped) as CFDictionary)
            var item = baseQuery(service: service, account: account, grouped: grouped)
            item[kSecValueData      as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecSuccess { return }
            if status != errSecMissingEntitlement { NSLog("Skald: keychain save failed (%d)", status); return }
        }
    }

    static func load(service: String, account: String) -> String? {
        for grouped in [true, false] {
            var q = baseQuery(service: service, account: account, grouped: grouped)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &result)
            if status == errSecSuccess, let data = result as? Data {
                return String(data: data, encoding: .utf8)
            }
            if status != errSecMissingEntitlement && status != errSecItemNotFound { return nil }
        }
        return nil
    }

    static func delete(service: String, account: String) {
        for grouped in [true, false] {
            SecItemDelete(baseQuery(service: service, account: account, grouped: grouped) as CFDictionary)
        }
    }
}
