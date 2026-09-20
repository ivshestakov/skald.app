import Foundation

enum Engine: String, CaseIterable, Identifiable, Codable {
    case apple
    case google
    case deepl
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:  return "Apple (on-device, offline)"
        case .google: return "Google (free, no key)"
        case .deepl:  return "DeepL"
        case .claude: return "Claude (Anthropic)"
        }
    }

    var shortName: String {
        switch self {
        case .apple:  return "Apple"
        case .google: return "Google"
        case .deepl:  return "DeepL"
        case .claude: return "Claude"
        }
    }

    /// Whether the engine needs an API key entered by the user.
    var needsKey: Bool { self == .deepl || self == .claude }

    /// Whether the engine talks to the network. In a keyboard extension that
    /// means the user must have granted "Allow Full Access".
    var needsNetwork: Bool { self != .apple }
}

enum ClaudeModel: String, CaseIterable, Identifiable, Codable {
    case haiku  = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-6"
    case opus   = "claude-opus-4-7"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku:  return "Haiku 4.5 — fast, cheapest"
        case .sonnet: return "Sonnet 4.6 — balanced"
        case .opus:   return "Opus 4.7 — top quality"
        }
    }
}
