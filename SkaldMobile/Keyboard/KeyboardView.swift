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
    private var returnBlue: Bool { key == .ret && (model.returnKeyTinted || model.translateMode) }

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
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                Text(spaceCode)
                    .font(.system(size: 10))
                    .foregroundStyle(KeyboardPalette.secondaryText(scheme).opacity(0.8))
                    .padding(.trailing, 7)
                    .padding(.bottom, 4)
            }
        case .ret:
            if model.translateMode {
                Image(systemName: "arrow.up").font(.system(size: 19, weight: .bold))
            } else if model.returnLabel == "return" {
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

    var body: some View {
        HStack(spacing: 6) {
            // Target-language flag: tap = open the translation field.
            Button(action: model.toggleTranslateMode) {
                HStack(spacing: 3) {
                    Text(model.translatePair.target.flag).font(.system(size: 20))
                    if model.translateMode {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                }
                .frame(width: model.translateMode ? 50 : 40, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                        .fill(model.translateMode ? Color.accentColor.opacity(0.18) : KeyboardPalette.chip(scheme))
                )
            }
            .buttonStyle(.plain)

            // Style / engine settings.
            Button(action: model.toggleSettings) {
                Image(systemName: model.showsTonePill ? model.settings.tone.symbolName : "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.showSettings ? Color.white : KeyboardPalette.text(scheme))
                    .frame(width: 36, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                            .fill(model.showSettings ? Color.accentColor : KeyboardPalette.chip(scheme))
                    )
            }
            .buttonStyle(.plain)

            if model.undo != nil, !model.translateMode {
                Button(action: model.undoTranslation) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                                .fill(KeyboardPalette.chip(scheme))
                        )
                }
                .buttonStyle(.plain)
            }

            Group {
                if model.translateMode {
                    TranslationField(model: model)
                } else {
                    statusView
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(KeyboardPalette.text(scheme))
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
                            .font(.system(size: 16))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
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
/// translate mode is on: your text on top, the live translation below.
struct TranslationField: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(model.composer.isEmpty ? placeholder : model.composer)
                        .font(.system(size: 14))
                        .foregroundStyle(model.composer.isEmpty ? .secondary : KeyboardPalette.text(scheme))
                        .lineLimit(1)
                        .truncationMode(.head)
                    if !model.composer.isEmpty {
                        Rectangle().fill(Color.accentColor).frame(width: 2, height: 16)   // caret
                    }
                }
                HStack(spacing: 4) {
                    if model.previewBusy { ProgressView().controlSize(.mini) }
                    Text(previewLine)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(previewColor)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !model.composer.isEmpty {
                Button(action: model.insertComposerAsIs) {
                    Text("as is")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(KeyboardPalette.chip(scheme), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                .fill(KeyboardPalette.key(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: model.metrics.keyCornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
        )
    }

    private var placeholder: String {
        "\(model.translatePair.source.flag) → \(model.translatePair.target.flag)  type, then ↑"
    }

    private var previewLine: String {
        if case .error(let text) = model.status { return text }
        if model.composer.isEmpty { return "Empty + ↑ translates the text already in the field" }
        if model.preview.isEmpty { return model.previewBusy ? "Translating…" : "…" }
        return model.preview
    }

    private var previewColor: Color {
        if case .error = model.status { return .orange }
        return model.preview.isEmpty ? .secondary : Color.accentColor
    }
}

// MARK: - Translate settings panel (replaces the keys while open)

struct TranslateSettingsPanel: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    private let tones = Tone.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            row("Style") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("Off", selected: !model.settings.adaptStyleEnabled) { model.setAdaptStyle(false) }
                        ForEach(tones) { t in
                            chip(t.shortLabel, selected: model.settings.adaptStyleEnabled && model.settings.tone == t,
                                 tint: t.color) { model.setTone(t) }
                        }
                    }
                }
            }
            .opacity(model.settings.engine == .claude ? 1 : 0.35)
            .disabled(model.settings.engine != .claude)
            Text(model.settings.engine == .claude
                 ? model.settings.tone.subtitle
                 : "Style adaptation needs the Claude engine.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(action: model.toggleSettings) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 34)
                        .background(Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .foregroundStyle(KeyboardPalette.text(scheme))
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
                .frame(height: 30)
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
