import Foundation

/// Languages Skald can translate between. Raw value is the ISO 639-1 code,
/// which doubles as the Google code; DeepL wants it upper-cased.
/// Mirrors `Language` in the macOS app (TranslatorApp/Sources/Settings.swift).
enum Language: String, CaseIterable, Identifiable, Codable {
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

    var id: String { rawValue }

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

    /// Two-letter code shown on the keyboard's layout-toggle key.
    var shortCode: String { rawValue.uppercased() }

    var googleCode: String { rawValue }
    var deepLCode:  String { rawValue.uppercased() }
}
