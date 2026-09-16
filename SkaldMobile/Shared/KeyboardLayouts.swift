import Foundation

enum Key: Hashable {
    case char(String)     // letter or symbol; letters get upper-cased under shift
    case shift
    case backspace
    case space
    case ret
    case numbers          // "123"
    case letters          // "ABC"
    case symbols          // "#+="
    case globe            // next system keyboard
    case language         // cycle the keyboard's own layouts (long-press: pick)
    case emoji            // open the emoji panel
}

enum KeyboardPage { case letters, numbers, symbols, emoji, numberPad }

/// Which number pad a host field asked for (UIKeyboardType).
enum NumberPadStyle { case plain, decimal, phone }

struct LetterLayout: Equatable {
    let id: String
    let rows: [[String]]

    static let latin = LetterLayout(id: "latin", rows: [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l"],
        ["z","x","c","v","b","n","m"],
    ])
    static let russian = LetterLayout(id: "ru", rows: [
        ["й","ц","у","к","е","н","г","ш","щ","з","х"],
        ["ф","ы","в","а","п","р","о","л","д","ж","э"],
        ["я","ч","с","м","и","т","ь","б","ю"],
    ])
    // Matches the iOS 27 system layout: apostrophe closes row 2, ґ is a key.
    static let ukrainian = LetterLayout(id: "uk", rows: [
        ["й","ц","у","к","е","н","г","ш","щ","з","х","ї"],
        ["ф","і","в","а","п","р","о","л","д","ж","є","'"],
        ["я","ч","с","м","и","т","ь","б","ю","ґ"],
    ])
    static let german = LetterLayout(id: "de", rows: [
        ["q","w","e","r","t","z","u","i","o","p","ü"],
        ["a","s","d","f","g","h","j","k","l","ö","ä"],
        ["y","x","c","v","b","n","m"],
    ])
    static let french = LetterLayout(id: "fr", rows: [
        ["a","z","e","r","t","y","u","i","o","p"],
        ["q","s","d","f","g","h","j","k","l","m"],
        ["w","x","c","v","b","n"],
    ])
    static let spanish = LetterLayout(id: "es", rows: [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l","ñ"],
        ["z","x","c","v","b","n","m"],
    ])

    /// Languages with a real layout of their own (CJK falls back to Latin and
    /// is not offered as a keyboard language).
    static func hasLayout(_ language: Language) -> Bool {
        switch language {
        case .chinese, .japanese, .korean: return false
        default: return true
        }
    }

    static func forLanguage(_ language: Language) -> LetterLayout {
        switch language {
        case .russian:   return .russian
        case .ukrainian: return .ukrainian
        case .german:    return .german
        case .french:    return .french
        case .spanish:   return .spanish
        default:         return .latin
        }
    }
}

enum SymbolPages {
    static let numbers: [[String]] = [
        ["1","2","3","4","5","6","7","8","9","0"],
        ["-","/",":",";","(",")","$","&","@","\""],
        [".",",","?","!","'"],
    ]
    static let symbols: [[String]] = [
        ["[","]","{","}","#","%","^","*","+","="],
        ["_","\\","|","~","<",">","€","£","¥","•"],
        [".",",","?","!","'"],
    ]
}

/// Long-press alternates, keyed by the base key's lowercase glyph. A union
/// across languages: the popup is only ever one tap away, so offering a few
/// extra accents costs nothing.
enum KeyAlternates {
    static let table: [String: [String]] = [
        // Latin
        "a": ["à","á","â","ä","ã","å","ą"],
        "c": ["ç","ć","č"],
        "e": ["è","é","ê","ë","ę","ė"],
        "i": ["ì","í","î","ï"],
        "l": ["ł"],
        "n": ["ñ","ń"],
        "o": ["ò","ó","ô","ö","õ","ø"],
        "s": ["ß","ś","š"],
        "u": ["ù","ú","û","ü"],
        "y": ["ÿ"],
        "z": ["ź","ż","ž"],
        // Cyrillic
        "е": ["ё"],
        "ь": ["ъ"],
        "г": ["ґ"],
        "и": ["і","ї"],
        "і": ["ї","и"],
        // Punctuation
        ".": ["…"],
        "-": ["–","—"],
        "'": ["‘","’","«","»"],
        "\"": ["“","”","„"],
        "$": ["€","£","¥","₴","₽"],
        "0": ["°"],
        "%": ["‰"],
        "=": ["≠","≈"],
        "/": ["\\"],
        "?": ["¿"],
        "!": ["¡"],
    ]

    static func alternates(for glyph: String) -> [String] {
        table[glyph.lowercased()] ?? []
    }
}
