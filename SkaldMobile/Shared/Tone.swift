import SwiftUI

/// Tone/register axis for LLM-based translation, cold → crude.
/// Mirrors `Tone` in the macOS app; prompt directives are kept identical so
/// the same phrase translates the same way on both platforms.
enum Tone: Int, CaseIterable, Identifiable, Codable {
    case corporate = 0
    case simple    = 1
    case original  = 2   // default — mirrors the source
    case youth     = 3
    case vulgar    = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .corporate: return "Corporate"
        case .simple:    return "Simple & Short"
        case .original:  return "Original"
        case .youth:     return "Youth Slang"
        case .vulgar:    return "Vulgar"
        }
    }

    var shortLabel: String {
        switch self {
        case .corporate: return "Corporate"
        case .simple:    return "Simple"
        case .original:  return "Original"
        case .youth:     return "Youth"
        case .vulgar:    return "Vulgar"
        }
    }

    var subtitle: String {
        switch self {
        case .corporate:
            return "Bureaucratic, strictly formal, polite but firm. No slang, no contractions."
        case .simple:
            return "Plain, short sentences, no jargon, no filler. Understandable on first read."
        case .original:
            return "Mirrors your tone, emoji, spelling and punctuation. Keeps your voice."
        case .youth:
            return "Contemporary slang, internet-speak, playful phrasing."
        case .vulgar:
            return "Crude, aggressive, sharp. Swearing and mockery welcome. Unfiltered."
        }
    }

    var symbolName: String {
        switch self {
        case .corporate: return "briefcase.fill"
        case .simple:    return "scissors"
        case .original:  return "equal"
        case .youth:     return "sparkles"
        case .vulgar:    return "flame.fill"
        }
    }

    var color: Color {
        switch self {
        case .corporate: return Color(red: 0.30, green: 0.42, blue: 0.85)
        case .simple:    return Color(red: 0.03, green: 0.57, blue: 0.70)
        case .original:  return Color(red: 0.06, green: 0.73, blue: 0.51)
        case .youth:     return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .vulgar:    return Color(red: 0.86, green: 0.17, blue: 0.17)
        }
    }

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
