import SwiftUI

/// Visual constants tuned against the iOS system keyboard (see README:
/// "Matching the system keyboard").
enum KeyboardMetrics {
    static let gap: CGFloat = 7
    static let rowGap: CGFloat = 12
    static let rowHeight: CGFloat = 42
    static let sidePadding: CGFloat = 6
    static let topBarHeight: CGFloat = 44
    static let topPadding: CGFloat = 5
    static let composerHeight: CGFloat = 56
    static let keyCornerRadius: CGFloat = 7
    static let bottomPadding: CGFloat = 4
    static let smallKeyWidth: CGFloat = 43.5

    static var keysHeight: CGFloat { rowHeight * 4 + rowGap * 3 }
    static func totalHeight(translateMode: Bool) -> CGFloat {
        topBarHeight + (translateMode ? composerHeight : 0) + topPadding + keysHeight + bottomPadding
    }
}

struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    private let m = KeyboardMetrics.self

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
                .frame(height: m.topBarHeight)
                .padding(.horizontal, 8)
            if model.translateMode {
                ComposerStrip(model: model)
                    .frame(height: m.composerHeight)
                    .padding(.horizontal, 8)
            }
            Group {
                if model.page == .emoji {
                    EmojiPanel(model: model)
                } else {
                    keyRows
                }
            }
            .frame(height: m.keysHeight)
            .padding(.top, m.topPadding)
            .padding(.bottom, m.bottomPadding)
        }
        .background(KeyboardPalette.background(scheme))
        .coordinateSpace(name: "keyboard")
        .overlay(alignment: .topLeading) {
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
        case .letters, .emoji:
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

    /// Width of one regular key, derived from the widest row.
    private func unit(_ width: CGFloat) -> CGFloat {
        let n = CGFloat(widestRow)
        return (width - m.gap * (n - 1)) / n
    }

    private func rowView(_ row: [Key], width: CGFloat) -> some View {
        let u = unit(width)
        let chars = row.filter(isChar).count
        let specials = row.count - chars
        let gaps = CGFloat(row.count - 1) * m.gap
        // Shift/backspace take what's left, never less than a letter key; on
        // 11–12 column layouts the letters in this row shrink a little, as on
        // the system keyboard.
        let minSpecial = u * (widestRow <= 10 ? 1.25 : 1.0)
        let leftover = specials > 0 ? (width - CGFloat(chars) * u - gaps) / CGFloat(specials) : 0
        let specialWidth = max(minSpecial, leftover)
        let charWidth = specials > 0
            ? min(u, (width - CGFloat(specials) * specialWidth - gaps) / CGFloat(chars))
            : u
        return HStack(spacing: m.gap) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, key in
                KeyButton(key: key, model: model, width: isChar(key) ? charWidth : specialWidth, height: m.rowHeight)
            }
        }
        .frame(width: width)
    }

    private func bottomRow(width: CGFloat) -> some View {
        let small = m.smallKeyWidth
        return HStack(spacing: m.gap) {
            KeyButton(key: model.page == .letters ? .numbers : .letters, model: model, width: small, height: m.rowHeight)
            KeyButton(key: .emoji, model: model, width: small, height: m.rowHeight)
            if model.hasLanguageKey {
                KeyButton(key: .language, model: model, width: small, height: m.rowHeight)
            }
            if model.showsGlobe {
                KeyButton(key: .globe, model: model, width: small, height: m.rowHeight)
            }
            KeyButton(key: .space, model: model, width: nil, height: m.rowHeight)
            KeyButton(key: .ret, model: model, width: small * 2 + m.gap, height: m.rowHeight)
        }
        .frame(width: width)
    }
}

// MARK: - Palette (sampled from the system keyboard)

enum KeyboardPalette {
    // Sampled from the system keyboard: iOS 27 dark (device photo) and
    // iOS 26.4 light (simulator). Every key shares one colour; no shadows.
    static func background(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x212121) : Color(hex: 0xDFE0E6)
    }
    static func key(_ s: ColorScheme) -> Color {
        s == .dark ? Color(hex: 0x454545) : .white
    }
    static func specialKey(_ s: ColorScheme) -> Color { key(s) }
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

// MARK: - Key button

struct KeyButton: View {
    let key: Key
    @ObservedObject var model: KeyboardModel
    let width: CGFloat?
    let height: CGFloat
    @Environment(\.colorScheme) private var scheme
    @State private var pressed = false
    @State private var frame: CGRect = .zero
    @State private var pressID = 0
    @State private var popupShown = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: KeyboardMetrics.keyCornerRadius, style: .continuous)
                .fill(fill)
            label
                .foregroundStyle(labelColor)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(GeometryReader { geo in
            Color.clear.onAppear { frame = geo.frame(in: .named("keyboard")) }
                .onChange(of: geo.size) { _, _ in frame = geo.frame(in: .named("keyboard")) }
        })
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("keyboard"))
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        popupShown = false
                        pressID += 1
                        let id = pressID
                        switch key {
                        case .backspace:
                            model.tap(.backspace)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                if pressed, pressID == id { model.startBackspaceRepeat() }
                            }
                        case .char(let glyph):
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                if pressed, pressID == id, model.showAlternates(for: glyph, keyFrame: frame) {
                                    popupShown = true
                                }
                            }
                        case .language:
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                if pressed, pressID == id, model.showLanguages(keyFrame: frame) {
                                    popupShown = true
                                }
                            }
                        default:
                            break
                        }
                    } else if popupShown, let popup = model.popup {
                        let layout = KeyPopupView.layout(for: popup, keyHeight: height)
                        model.updatePopupSelection(x: value.location.x,
                                                   optionWidth: layout.optionWidth,
                                                   popupMinX: layout.frame.minX)
                    }
                }
                .onEnded { _ in
                    pressed = false
                    pressID += 1
                    if key == .backspace {
                        model.stopBackspaceRepeat()
                    } else if popupShown {
                        popupShown = false
                        model.commitPopup()
                    } else {
                        model.tap(key)
                    }
                }
        )
    }

    private var isSpecial: Bool {
        if case .char = key { return false }
        if key == .space { return false }
        return true
    }

    private var shiftActive: Bool { key == .shift && model.shift != .off }

    private var fill: Color {
        if pressed { return KeyboardPalette.pressedKey(scheme) }
        return KeyboardPalette.key(scheme)
    }

    private var labelColor: Color { KeyboardPalette.text(scheme) }

    @ViewBuilder
    private var label: some View {
        switch key {
        case .char(let s):
            Text(model.page == .letters && model.shift != .off ? s.uppercased() : s)
                .font(.system(size: model.page == .letters ? 23 : 22, weight: .regular))
        case .shift:
            Image(systemName: model.shift == .caps ? "capslock.fill" : (model.shift == .on ? "shift.fill" : "shift"))
                .font(.system(size: 18, weight: .regular))
        case .backspace:
            Image(systemName: "delete.left").font(.system(size: 18))
        case .space:
            // The system keyboard leaves the space key blank and tucks the
            // language code into the bottom-right corner.
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                Text(spaceCode)
                    .font(.system(size: 10))
                    .foregroundStyle(KeyboardPalette.secondaryText(scheme).opacity(0.8))
                    .padding(.trailing, 7)
                    .padding(.bottom, 4)
            }
        case .ret:
            if model.returnLabel == "return" {
                Image(systemName: "return").font(.system(size: 18))
            } else {
                Text(model.returnLabel).font(.system(size: 16))
            }
        case .numbers:
            Text("123").font(.system(size: 16))
        case .letters:
            Text("ABC").font(.system(size: 16))
        case .symbols:
            Text("#+=").font(.system(size: 16))
        case .globe:
            Image(systemName: "globe").font(.system(size: 18))
        case .emoji:
            SmileyIcon(disc: labelColor, face: fill)
        case .language:
            Text(model.currentLanguage.shortCode).font(.system(size: 15, weight: .medium))
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

struct TopBar: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            // Direction chip
            HStack(spacing: 4) {
                Text(model.direction.source.flag)
                Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold))
                Text(model.direction.target.flag)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(KeyboardPalette.chip(scheme), in: Capsule())

            if model.showsTonePill {
                Button(action: model.cycleTone) {
                    HStack(spacing: 4) {
                        Image(systemName: model.settings.tone.symbolName)
                        Text(model.settings.tone.shortLabel)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(model.settings.tone.color, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            statusView
                .frame(maxWidth: .infinity, alignment: .leading)

            if model.undo != nil {
                Button(action: model.undoTranslation) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .background(KeyboardPalette.chip(scheme), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Translate mode toggle. Filled = on.
            Button(action: model.toggleTranslateMode) {
                HStack(spacing: 5) {
                    Image(systemName: "character.bubble")
                    Text("Translate")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(model.translateMode ? .white : Color.accentColor)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    Capsule().fill(model.translateMode ? Color.accentColor : KeyboardPalette.chip(scheme))
                )
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(model.translateMode ? 0 : 0.6), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(KeyboardPalette.text(scheme))
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .busy:
            ProgressView().controlSize(.small)
        case .done:
            Label("Translated", systemImage: "checkmark")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
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

// MARK: - Composer strip (translate mode)

struct ComposerStrip: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.composer.isEmpty ? "Type here — the translation goes into the app" : model.composer)
                    .font(.system(size: 15))
                    .foregroundStyle(model.composer.isEmpty ? .secondary : KeyboardPalette.text(scheme))
                    .lineLimit(1)
                    .truncationMode(.head)
                HStack(spacing: 6) {
                    if model.previewBusy {
                        ProgressView().controlSize(.mini)
                    }
                    Text(previewLine)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(previewColor)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !model.composer.isEmpty {
                Button(action: model.insertComposerAsIs) {
                    Text("as is")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 30)
                        .background(KeyboardPalette.chip(scheme), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                if model.composer.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.translate()
                } else {
                    model.commitComposer()
                }
            } label: {
                Image(systemName: model.composer.isEmpty ? "text.insert" : "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 32)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.status == .busy)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardMetrics.composerHeight - 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.22) : Color.white.opacity(0.9))
        )
        .foregroundStyle(KeyboardPalette.text(scheme))
    }

    private var previewLine: String {
        if case .error(let text) = model.status { return text }
        if model.composer.isEmpty { return "Empty? ⤓ translates what's already in the field" }
        if model.preview.isEmpty { return model.previewBusy ? "Translating…" : "…" }
        return model.preview
    }

    private var previewColor: Color {
        if case .error = model.status { return .orange }
        return model.preview.isEmpty ? .secondary : Color.accentColor
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
                KeyButton(key: .letters, model: model, width: 48, height: 36)
                if !model.settings.recentEmoji.isEmpty {
                    tab("recent", symbol: "clock")
                }
                ForEach(EmojiData.categories) { cat in
                    tab(cat.id, symbol: cat.symbol)
                }
                KeyButton(key: .backspace, model: model, width: 48, height: 36)
            }
            .padding(.horizontal, KeyboardMetrics.sidePadding)
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

    /// Popup sits just above the pressed key, centred on it, clamped to the
    /// screen. Shared with the key's drag tracking so both agree on geometry.
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

/// Filled smiley like the system emoji key: a solid disc with the eyes and
/// mouth knocked out in the key colour. Drawn by hand — SF's face.smiling
/// variants render as an outline in this context.
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
