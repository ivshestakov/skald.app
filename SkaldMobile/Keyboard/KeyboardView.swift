import SwiftUI

/// Visual constants tuned against the iOS system keyboard (see README:
/// "Matching the system keyboard"). Two presets: portrait and landscape.
struct KeyboardMetrics: Equatable {
    var gap: CGFloat
    var rowGap: CGFloat
    var rowHeight: CGFloat
    var sidePadding: CGFloat
    var topBarHeight: CGFloat
    var topPadding: CGFloat
    var composerHeight: CGFloat
    var keyCornerRadius: CGFloat
    var bottomPadding: CGFloat
    var smallKeyWidth: CGFloat
    var letterFont: CGFloat

    static let portrait = KeyboardMetrics(gap: 7, rowGap: 12, rowHeight: 42, sidePadding: 6, topBarHeight: 44,
                                          topPadding: 5, composerHeight: 56, keyCornerRadius: 7, bottomPadding: 4,
                                          smallKeyWidth: 43.5, letterFont: 23)
    static let landscape = KeyboardMetrics(gap: 9, rowGap: 7, rowHeight: 33, sidePadding: 4, topBarHeight: 38,
                                           topPadding: 3, composerHeight: 44, keyCornerRadius: 6, bottomPadding: 3,
                                           smallKeyWidth: 60, letterFont: 20)

    static func current(width: CGFloat, height: CGFloat) -> KeyboardMetrics {
        width > height && width > 500 ? .landscape : .portrait
    }

    var keysHeight: CGFloat { rowHeight * 4 + rowGap * 3 }
    func totalHeight(translateMode: Bool) -> CGFloat {
        topBarHeight + (translateMode ? composerHeight : 0) + topPadding + keysHeight + bottomPadding
    }
}

/// Frames of the visible keys, in the "keyboard" coordinate space, collected
/// from the key views for the UIKit touch layer.
struct KeyFramesKey: PreferenceKey {
    static var defaultValue: [Key: CGRect] = [:]
    static func reduce(value: inout [Key: CGRect], nextValue: () -> [Key: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme
    @State private var keyFrames: [Key: CGRect] = [:]

    private var m: KeyboardMetrics { model.metrics }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .frame(height: m.topBarHeight)
                .padding(.horizontal, 6)
            Group {
                if model.showSettings {
                    TranslateSettingsPanel(model: model)
                } else {
                    switch model.page {
                    case .emoji:     EmojiPanel(model: model)
                    case .numberPad: numberPad
                    default:         keyRows
                    }
                }
            }
            .frame(height: m.keysHeight)
            .padding(.top, m.topPadding)
            .padding(.bottom, m.bottomPadding)
        }
        .background(KeyboardPalette.background(scheme))
        .coordinateSpace(name: "keyboard")
        .onPreferenceChange(KeyFramesKey.self) { keyFrames = $0 }
        .overlay(KeyTouchView(model: model, frames: keyFrames))
        .overlay(alignment: .topLeading) {
            if let preview = model.keyPreview, model.popup == nil, let f = keyFrames[preview.key] {
                KeyPreviewView(glyph: preview.glyph, keyFrame: f, metrics: m)
            }
            if let popup = model.popup {
                KeyPopupView(popup: popup, keyHeight: m.rowHeight)
            }
        }
    }

    // MARK: Rows

    private var keyRows: some View {
        GeometryReader { geo in
            let width = geo.size.width - m.sidePadding * 2
            VStack(spacing: m.rowGap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowView(row, width: width)
                }
                bottomRow(width: width)
            }
            .frame(width: width)
            .padding(.horizontal, m.sidePadding)
        }
    }

    private var rows: [[Key]] {
        switch model.page {
        case .letters, .emoji, .numberPad:
            let l = model.currentLayout.rows
            return [
                l[0].map(Key.char),
                l[1].map(Key.char),
                [.shift] + l[2].map(Key.char) + [.backspace],
            ]
        case .numbers:
            return [
                SymbolPages.numbers[0].map(Key.char),
                SymbolPages.numbers[1].map(Key.char),
                [.symbols] + SymbolPages.numbers[2].map(Key.char) + [.backspace],
            ]
        case .symbols:
            return [
                SymbolPages.symbols[0].map(Key.char),
                SymbolPages.symbols[1].map(Key.char),
                [.numbers] + SymbolPages.symbols[2].map(Key.char) + [.backspace],
            ]
        }
    }

    private func isChar(_ key: Key) -> Bool {
        if case .char = key { return true } else { return false }
    }

    private var widestRow: Int {
        rows.map { $0.filter(isChar).count }.max() ?? 10
    }

    private func unit(_ width: CGFloat) -> CGFloat {
        let n = CGFloat(widestRow)
        return (width - m.gap * (n - 1)) / n
    }

    private func rowView(_ row: [Key], width: CGFloat) -> some View {
        let u = unit(width)
        let chars = row.filter(isChar).count
        let specials = row.count - chars
        let gaps = CGFloat(row.count - 1) * m.gap
        let minSpecial = u * (widestRow <= 10 ? 1.25 : 1.0)
        let leftover = specials > 0 ? (width - CGFloat(chars) * u - gaps) / CGFloat(specials) : 0
        let specialWidth = max(minSpecial, leftover)
        let charWidth = specials > 0
            ? min(u, (width - CGFloat(specials) * specialWidth - gaps) / CGFloat(chars))
            : u
        return HStack(spacing: m.gap) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                KeyView(key: key, model: model, width: isChar(key) ? charWidth : specialWidth, height: m.rowHeight)
            }
        }
        .frame(width: width)
    }

    private func bottomRow(width: CGFloat) -> some View {
        let small = m.smallKeyWidth
        return HStack(spacing: m.gap) {
            KeyView(key: model.page == .letters ? .numbers : .letters, model: model, width: small, height: m.rowHeight)
            KeyView(key: .emoji, model: model, width: small, height: m.rowHeight)
            if model.hasLanguageKey {
                KeyView(key: .language, model: model, width: small, height: m.rowHeight)
            }
            if model.showsGlobe {
                KeyView(key: .globe, model: model, width: small, height: m.rowHeight)
            }
            if model.page == .letters, model.bottomExtras.count == 2 {
                KeyView(key: .char(model.bottomExtras[0]), model: model, width: small * 0.8, height: m.rowHeight)
            }
            KeyView(key: .space, model: model, width: nil, height: m.rowHeight)
            if model.page == .letters, model.bottomExtras.count == 2 {
                KeyView(key: .char(model.bottomExtras[1]), model: model, width: small * 0.8, height: m.rowHeight)
            }
            KeyView(key: .ret, model: model, width: small * 2 + m.gap, height: m.rowHeight)
        }
        .frame(width: width)
    }

    // MARK: Number pad (numberPad / decimalPad / phonePad fields)

    private var numberPad: some View {
        GeometryReader { geo in
            let width = geo.size.width - m.sidePadding * 2
            let keyW = (width - m.gap * 2) / 3
            let extra: Key? = {
                switch model.numberPadStyle {
                case .decimal?: return .char(".")
                case .phone?:   return .char("+")
                default:        return nil
                }
            }()
            VStack(spacing: m.rowGap) {
                ForEach([["1","2","3"],["4","5","6"],["7","8","9"]], id: \.self) { row in
                    HStack(spacing: m.gap) {
                        ForEach(row, id: \.self) { d in
                            KeyView(key: .char(d), model: model, width: keyW, height: m.rowHeight)
                        }
                    }
                }
                HStack(spacing: m.gap) {
                    if let extra {
                        KeyView(key: extra, model: model, width: keyW, height: m.rowHeight)
                    } else {
                        Color.clear.frame(width: keyW, height: m.rowHeight)
                    }
                    KeyView(key: .char("0"), model: model, width: keyW, height: m.rowHeight)
                    KeyView(key: .backspace, model: model, width: keyW, height: m.rowHeight)
                }
            }
            .frame(width: width)
            .padding(.horizontal, m.sidePadding)
        }
    }
}

// MARK: - Palette (sampled from the system keyboard)

enum KeyboardPalette {
    static func background(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x212121) : Color(hex: 0xDFE0E6)
    }
    static func key(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x454545) : .white
    }
    static func pressedKey(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x6B6B6B) : Color(hex: 0xC9CBD1)
    }
    static func text(_ s: ColorScheme) -> Color { s == .dark ? .white : .black }
    static func secondaryText(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0xA3A3A3) : Color(hex: 0x6B6C72)
    }
    static func chip(_ s: ColorScheme) -> Color { key(s) }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Key (visual only; touches handled by KeyTouchUIView)

struct KeyView: View {
    let key: Key
    @ObservedObject var model: KeyboardModel
    let width: CGFloat?
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                .fill(fill)
            label
                .foregroundStyle(labelColor)
                .opacity(model.cursorMode && isCharOrSpace ? 0 : 1)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(GeometryReader { geo in
            Color.clear.preference(key: KeyFramesKey.self, value: [key: geo.frame(in: .named("keyboard"))])
        })
        .allowsHitTesting(false)
    }

    private var isChar: Bool { if case .char = key { return true } else { return false } }
    private var isCharOrSpace: Bool { isChar || key == .space }
    private var isSpecial: Bool { !isCharOrSpace }
    private var pressed: Bool { model.pressedKeys.contains(key) }
    private var shiftActive: Bool { key == .shift && model.shift != .off }
    private var returnBlue: Bool { key == .ret && model.returnKeyTinted }

    private var fill: Color {
        if returnBlue { return pressed ? Color.accentColor.opacity(0.7) : Color.accentColor }
        // The system only pops up letters; special keys darken/lighten.
        if pressed, isSpecial { return KeyboardPalette.pressedKey(scheme) }
        if pressed, key == .space { return KeyboardPalette.pressedKey(scheme) }
        return KeyboardPalette.key(scheme)
    }

    private var labelColor: Color { returnBlue ? .white : KeyboardPalette.text(scheme) }

    @ViewBuilder
    private var label: some View {
        switch key {
        case .char(let s):
            Text(model.page == .letters && model.shift != .off ? s.uppercased() : s)
                .font(.system(size: model.page == .letters ? model.metrics.letterFont : model.metrics.letterFont - 1))
        case .shift:
            Image(systemName: model.shift == .caps ? "capslock.fill" : (model.shift == .on ? "shift.fill" : "shift"))
                .font(.system(size: 18))
        case .backspace:
            Image(systemName: pressed ? "delete.left.fill" : "delete.left").font(.system(size: 18))
        case .space:
            ZStack(alignment: model.keyboardLanguages.count > 1 ? .bottom : .bottomTrailing) {
                Color.clear
                if model.keyboardLanguages.count > 1 {
                    HStack {
                        Image(systemName: "chevron.left")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KeyboardPalette.secondaryText(scheme).opacity(0.45))
                    .padding(.horizontal, 9)
                }
                Text(spaceCode)
                    .font(.system(size: 10))
                    .foregroundStyle(KeyboardPalette.secondaryText(scheme).opacity(0.8))
                    .padding(.trailing, model.keyboardLanguages.count > 1 ? 0 : 7)
                    .padding(.bottom, 4)
            }
        case .ret:
            if model.returnLabel == "return" {
                Image(systemName: "return").font(.system(size: 18))
            } else {
                Text(model.returnLabel).font(.system(size: 16))
            }
        case .numbers:  Text("123").font(.system(size: 16))
        case .letters:  Text("ABC").font(.system(size: 16))
        case .symbols:  Text("#+=").font(.system(size: 16))
        case .globe:    Image(systemName: "globe").font(.system(size: 18))
        case .emoji:    SmileyIcon(disc: labelColor, face: fill)
        case .language: Text(model.currentLanguage.shortCode).font(.system(size: 15, weight: .medium))
        }
    }

    private var spaceCode: String {
        switch model.currentLanguage {
        case .russian:   return "ру"
        case .ukrainian: return "ук"
        default:         return model.currentLanguage.rawValue
        }
    }
}

// MARK: - Top bar
//
// Left: translation controls (target-language flag, style). Right, filling
// the rest: the suggestion strip like the system keyboard — or, in translate
// mode, the translation field (what you type + live translation).

struct TopBar: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    private var corner: CGFloat { model.metrics.keyCornerRadius }

    var body: some View {
        HStack(spacing: 6) {
            if model.translateMode {
                // × | translation field | ↑
                squareButton(systemName: "xmark", size: 13, action: model.exitTranslateMode)
                TranslationField(model: model)
                Button(action: model.sendTranslation) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 34)
                        .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .disabled(model.status == .busy)
            } else {
                statusView
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.undo != nil {
                    squareButton(systemName: "arrow.uturn.backward", size: 14, action: model.undoTranslation)
                }
                Button(action: model.enterTranslateMode) {
                    Text("Translate")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(KeyboardPalette.chip(scheme)))
                }
                .buttonStyle(.plain)
                Button(action: model.toggleSettings) {
                    Image(systemName: model.showsTonePill ? model.settings.tone.symbolName : "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(model.showSettings ? Color.white : (model.showsTonePill ? model.settings.tone.color : KeyboardPalette.text(scheme)))
                        .frame(width: 36, height: 34)
                        .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(model.showSettings ? Color.accentColor : KeyboardPalette.chip(scheme)))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(KeyboardPalette.text(scheme))
    }

    private func squareButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(KeyboardPalette.chip(scheme)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle where !model.suggestions.isEmpty:
            HStack(spacing: 0) {
                ForEach(Array(model.suggestions.enumerated()), id: \.offset) { i, s in
                    if i > 0 {
                        Rectangle().fill(KeyboardPalette.secondaryText(scheme).opacity(0.4))
                            .frame(width: 1, height: 22)
                    }
                    Button { model.acceptSuggestion(s) } label: {
                        Text(s)
                            .font(.system(size: 16, weight: model.applyIndex == i ? .medium : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                                    .fill(model.applyIndex == i ? KeyboardPalette.key(scheme) : Color.clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .idle:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .busy:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        case .done:
            Label("Translated", systemImage: "checkmark")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 6)
        case .error(let text):
            Button(action: model.dismissError) {
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The translation field that replaces the suggestion strip while the
/// translate mode is on. Only the text you type; ↑ translates and inserts.
/// Swipe left/right to recall the last five texts you sent.
struct TranslationField: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            if case .busy = model.status {
                ProgressView().controlSize(.small)
            }
            HStack(spacing: 0) {
                if case .error(let text) = model.status {
                    Text(text).font(.system(size: 12)).foregroundStyle(.orange).lineLimit(2).minimumScaleFactor(0.8)
                } else {
                    Text(model.composer.isEmpty ? " " : model.composer)
                        .font(.system(size: 16))
                        .foregroundStyle(KeyboardPalette.text(scheme))
                        .lineLimit(1)
                        .truncationMode(.head)
                    Rectangle().fill(Color.accentColor).frame(width: 2, height: 18)   // caret
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                .fill(KeyboardPalette.key(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { v in
                    guard abs(v.translation.width) > abs(v.translation.height) else { return }
                    model.swipeHistory(v.translation.width < 0 ? 1 : -1)
                }
        )
    }
}

// MARK: - Translate settings panel (replaces the keys while open)

struct TranslateSettingsPanel: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle()
                .fill(KeyboardPalette.secondaryText(scheme).opacity(0.25))
                .frame(height: 0.5)
            row("Layouts") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Language.allCases.filter { LetterLayout.hasLayout($0) }) { l in
                            chip("\(l.flag) \(l.shortCode)", selected: model.keyboardLanguages.contains(l)) { model.toggleKeyboardLanguage(l) }
                        }
                    }
                }
            }
            row("Translate to") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Language.allCases.filter { $0 != model.currentLanguage }) { l in
                            chip("\(l.flag) \(l.shortCode)", selected: model.translatePair.target == l) { model.setTarget(l) }
                        }
                    }
                }
            }
            row("Engine") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Engine.allCases) { e in
                            chip(e.shortName, selected: model.settings.engine == e) { model.setEngine(e) }
                        }
                    }
                }
            }
            engineDetails
            if model.settings.engine == .claude {
                row("Style") { ToneSliderView(model: model) }
            }
            HStack(alignment: .center, spacing: 8) {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: model.toggleSettings) {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 26)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .foregroundStyle(KeyboardPalette.text(scheme))
    }

    /// One line under the engine chips: what the engine costs, and for
    /// DeepL / Claude the API-key controls.
    @ViewBuilder
    private var engineDetails: some View {
        let engine = model.settings.engine
        HStack(spacing: 6) {
            Text("")
                .frame(width: 78)
            switch engine {
            case .apple:
                hint("Free, on your device, works offline. Language packs download in the Skald app.")
            case .google:
                hint("Free, unofficial endpoint. No published limit — Google may throttle after a burst of requests.")
            case .deepl, .claude:
                let has = model.settings.hasApiKey(for: engine)
                Image(systemName: has ? "checkmark.seal.fill" : "key")
                    .font(.system(size: 12))
                    .foregroundStyle(has ? Color.green : Color.secondary)
                Text(model.keyMessage ?? (has ? "Key saved" : (engine == .deepl
                     ? "No key. Free plan: 500k chars/month."
                     : "No key. Pay per use, ~$0.0001/phrase (Haiku).")))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                smallButton("Paste key") { model.pasteAPIKey(for: engine) }
                if has { smallButton("Clear") { model.clearAPIKey(for: engine) } }
            }
        }
        .frame(height: 24)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: String {
        if model.settings.engine == .claude {
            return "\(model.settings.tone.displayName): \(model.settings.tone.subtitle)"
        }
        return "Style adaptation is available with the Claude engine."
    }

    private func smallButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(KeyboardPalette.key(scheme), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
        }
    }

    private func chip(_ text: String, selected: Bool, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .white : KeyboardPalette.text(scheme))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(selected ? tint : KeyboardPalette.key(scheme)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Emoji panel

struct EmojiPanel: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(currentEmoji, id: \.self) { e in
                        Button { model.insertEmoji(e) } label: {
                            Text(e)
                                .font(.system(size: 30))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
            .id(model.emojiCategory)

            HStack(spacing: 4) {
                KeyView(key: .letters, model: model, width: 48, height: 36)
                if !model.settings.recentEmoji.isEmpty {
                    tab("recent", symbol: "clock")
                }
                ForEach(EmojiData.categories) { cat in
                    tab(cat.id, symbol: cat.symbol)
                }
                KeyView(key: .backspace, model: model, width: 48, height: 36)
            }
            .padding(.horizontal, model.metrics.sidePadding)
        }
    }

    private var currentEmoji: [String] {
        if model.emojiCategory == "recent" { return model.settings.recentEmoji }
        return EmojiData.categories.first { $0.id == model.emojiCategory }?.emoji
            ?? EmojiData.categories.first?.emoji ?? []
    }

    private func tab(_ id: String, symbol: String) -> some View {
        Button { model.emojiCategory = id } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(model.emojiCategory == id ? KeyboardPalette.text(scheme) : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    Capsule().fill(model.emojiCategory == id ? KeyboardPalette.chip(scheme) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Long-press popup

struct KeyPopupView: View {
    let popup: KeyPopup
    let keyHeight: CGFloat
    @Environment(\.colorScheme) private var scheme

    struct Layout {
        let frame: CGRect
        let optionWidth: CGFloat
    }

    static func layout(for popup: KeyPopup, keyHeight: CGFloat) -> Layout {
        let optionWidth = popup.kind == .languages ? 64 : max(popup.keyFrame.width, 34)
        let width = optionWidth * CGFloat(popup.options.count) + 8
        let screenWidth = UIScreen.main.bounds.width
        var x = popup.keyFrame.midX - width / 2
        x = min(max(x, 2), screenWidth - width - 2)
        let height = keyHeight + 10
        let y = popup.keyFrame.minY - height - 6
        return Layout(frame: CGRect(x: x, y: y, width: width, height: height), optionWidth: optionWidth)
    }

    var body: some View {
        let l = Self.layout(for: popup, keyHeight: keyHeight)
        HStack(spacing: 0) {
            ForEach(Array(popup.options.enumerated()), id: \.offset) { i, option in
                Text(option)
                    .font(popup.kind == .languages ? .system(size: 14, weight: .semibold) : .system(size: 22))
                    .frame(width: l.optionWidth, height: l.frame.height - 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(i == popup.selected ? Color.accentColor : Color.clear)
                    )
                    .foregroundStyle(i == popup.selected ? .white : KeyboardPalette.text(scheme))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.25) : .white)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        )
        .frame(width: l.frame.width, height: l.frame.height)
        .offset(x: l.frame.minX, y: l.frame.minY)
        .allowsHitTesting(false)
    }
}

// MARK: - Character preview (magnified key)

struct KeyPreviewView: View {
    let glyph: String
    let keyFrame: CGRect
    let metrics: KeyboardMetrics
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let k = keyFrame
        let width = max(k.width * 1.7, 46)
        let height = k.height * 2.35
        let screenWidth = UIScreen.main.bounds.width
        var x = k.midX - width / 2
        x = min(max(x, 2), screenWidth - width - 2)
        let y = k.maxY - height
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(KeyboardPalette.key(scheme))
                .shadow(color: .black.opacity(scheme == .dark ? 0.6 : 0.25), radius: 4, y: 1)
            Text(glyph)
                .font(.system(size: metrics.letterFont * 1.75, weight: .light))
                .foregroundStyle(KeyboardPalette.text(scheme))
                .frame(height: k.height * 1.35)
        }
        .frame(width: width, height: height)
        .offset(x: x, y: y)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Emoji key icon

struct SmileyIcon: View {
    let disc: Color
    let face: Color
    private let size: CGFloat = 23

    var body: some View {
        ZStack {
            Circle().fill(disc)
            Circle().fill(face).frame(width: size * 0.13, height: size * 0.13)
                .offset(x: -size * 0.19, y: -size * 0.14)
            Circle().fill(face).frame(width: size * 0.13, height: size * 0.13)
                .offset(x: size * 0.19, y: -size * 0.14)
            Path { p in
                p.addArc(center: CGPoint(x: size / 2, y: size * 0.48),
                         radius: size * 0.30,
                         startAngle: .degrees(25), endAngle: .degrees(155), clockwise: false)
            }
            .stroke(face, style: StrokeStyle(lineWidth: size * 0.11, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Tone slider (icons above a gradient track, snaps to five stops)

struct ToneSliderView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme
    private let tones = Tone.allCases

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let step = w / CGFloat(tones.count - 1)

            let sel = model.settings.tone
            let x = CGFloat(sel.rawValue) * step
            ZStack(alignment: .topLeading) {
                // icons
                ForEach(tones) { t in
                    Image(systemName: t.symbolName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t == sel ? t.color : Color.secondary)
                        .frame(width: 24, height: 18)
                        .position(x: CGFloat(t.rawValue) * step, y: 9)
                }
                // track
                Capsule()
                    .fill(LinearGradient(colors: tones.map { $0.color }, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                    .position(x: w / 2, y: 32)
                ForEach(tones) { t in
                    Circle().fill(KeyboardPalette.background(scheme)).frame(width: 5, height: 5)
                        .position(x: CGFloat(t.rawValue) * step, y: 32)
                }
                // thumb
                Circle()
                    .fill(.white)
                    .overlay(Circle().fill(sel.color).frame(width: 10, height: 10))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: 22, height: 22)
                    .position(x: x, y: 32)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in select(at: v.location.x, step: step) }
                    .onEnded { v in select(at: v.location.x, step: step) }
            )
        }
        .frame(height: 38)
        .padding(.horizontal, 12)
    }

    private func select(at x: CGFloat, step: CGFloat) {
        let i = min(max(Int((x / step).rounded()), 0), tones.count - 1)
        let t = tones[i]
        if model.settings.tone != t { model.setTone(t) }
    }
}
