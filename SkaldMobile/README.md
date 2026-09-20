# Skald for iOS — translating keyboard

Status: **MVP, runs in the simulator** (2026-09-16). Not yet on a device,
not on TestFlight.

Two targets, one shared code folder:

```
SkaldMobile/
├── project.yml        — xcodegen spec (the .xcodeproj is generated, not committed)
├── App/               — container app (SwiftUI): Setup (with a try-it field) / Settings
├── Keyboard/          — SkaldKeyboard.appex (UIInputViewController + SwiftUI)
└── Shared/            — compiled into both targets:
    ├── Language.swift, Engine.swift, Tone.swift   — same enums as the Mac app
    ├── SkaldSettings.swift    — App Group UserDefaults + shared Keychain
    ├── TranslationService.swift — async Google / DeepL / Claude, language detection
    ├── AppleTranslator.swift  — Translation.framework bridge (needs a host view)
    └── TranslateFailure.swift — one-line error texts
```

Bundle IDs: `com.ivshestakov.skald.ios` (app), `.ios.keyboard` (extension).
App Group: `group.com.ivshestakov.skald`. Team `975ZZPJQNB`, automatic signing.

## How the keyboard works

- Full keyboard with shift, caps (double-tap), numbers and symbols pages,
  long-press alternates (ъ, ё, ґ, ß, é, ą, …), backspace repeat,
  auto-capitalisation at sentence start, system key clicks.
- **System typing behaviours**: double space → ". " (consecutive presses after
  a word), space after punctuation on the 123/#+= page returns to letters,
  magnified key pop-up while pressed (follows the finger, lingers 100 ms),
  light haptic on every key (needs Full Access), key click sound.
- **Touch handling like the system** (`Keyboard/KeyTouchView.swift`, a UIKit
  multi-touch layer over the SwiftUI keys): two-thumb typing, release on the
  key under the finger, glide from shift/123 to a key (one capital / one digit
  and back), long-press pop-ups, backspace repeat that switches to deleting
  whole words after ~1.5 s, **space-bar trackpad** (hold space; the whole
  keyboard becomes a trackpad: ~8 pt per character, ~28 pt per line, line
  moves only on clearly vertical motion; lines are real line breaks plus an
  estimated wrap every 38 characters, since extensions can't see layout).
- **Host field traits**: number pad for numberPad/decimalPad/phonePad
  fields, `@`/`.` keys for e-mail, `.`/`/` for URLs, no corrections in
  password/e-mail/URL fields or when the app turns autocorrection off,
  autocapitalization mode (none/words/sentences/all) from the field, blue
  Go/Search/Send/Done return key, user Text Replacement shortcuts via the
  supplementary lexicon. Landscape gets its own metrics preset.
- **Parity work (2026-09-17, see `docs/native-parity.html`)**: the bar
  follows the native layout — `"typed"` · highlighted correction · alternative —
  with the correction computed while typing, so space / punctuation / Return
  apply it instantly. Backspace after a correction only removes the
  separator and re-offers the typed word (quoted); retyping the same word is
  not corrected again. Touch geometry feeds the corrector (per-letter touch
  likelihoods, see P3 below). English contractions (dont → don't, i → I),
  Smart Punctuation (« » / “ ”, ‘ ’, -- → —), Contacts names and
  blank-shortcut Text Replacements as protected words, backspace speeds
  500 ms / 100 ms / words at 350 ms after 20 chars, rollover typing,
  trackpad gain by finger speed, ASCII fields switch to the Latin layout,
  numbersAndPunctuation opens 123, "Reset learned words" in the app.
- **P2 (2026-09-17)**: dynamic key hit areas — a likely next letter (from
  dictionary prefix completions, or the first letters of likely next words)
  claims touches up to 6 pt outside its visible key, as in Apple's patent;
  three key click samples (letter / modifier / delete, loaded from the
  system's UISounds, own "Key sounds" switch); emoji search (magnifier in the
  emoji panel → the bar becomes a search field, Latin layout, English names
  from `emoji-names.txt`) and skin-tone variants on long-press; ".com .net
  .org .ua .ru .edu" on long-press of "." in URL/email fields; the return
  key greys out and does nothing when the host asks for it on an empty field;
  landscape key area 162 pt; the chosen layout is remembered across sessions.
- **P3 corrector rework (2026-09-21, build 16)** after on-device testing
  showed far more typos than the system keyboard: (1) the touch model is
  now Gaussian (σ = 0.45 key pitch, `KeyTouchUIView.touchLikelihood`,
  measured at touch-down) and a substitution is weighted by the likelihood
  ratio of the proposed key to the typed one — the old linear 1.4-key-width
  falloff rated "hit the neighbouring key" below "inserted a random letter";
  edit priors re-set for a touchscreen (dropped/stray tap 0.12,
  transposition 0.05). (2) Frequency thresholds are shares of the corpus,
  not absolute counts: the Ukrainian list has 30× fewer tokens than the
  Russian one and the old `count ≥ 30` gate refused to correct into 73 % of
  its words. (3) Russian lines in the Ukrainian list (ы э ъ ё) and vice
  versa are ignored. (4) A word the corpus or `UITextChecker` vouches for is
  never replaced any more (the bar still offers alternatives); a rare
  corpus entry the checker rejects ("утебя", "наете") is corrected like an
  unknown word. (5) `UITextChecker.guesses` supplies candidates for forms
  the 50k list lacks, scored with the same touch model. (6) An unknown word
  is learned after three keeps, and never when the system dictionary has a
  one-edit fix for it. Synthetic check (`docs/research/autocorrect-sim.py`, 1500
  one-key slips per language): Russian fixes 92 % → 97 %, wrong rewrites of
  correctly typed rare words 3–5 % → ≤1.7 % (the system checker, which the
  simulation does not model, protects more of them on device); Ukrainian
  fixes 39 % → 96 %, "left as typed" 53 % → 1 %.
- **Auto-correction & suggestions** (`Keyboard/Autocorrect.swift`):
  per-language frequency dictionaries (OpenSubtitles 2018 top-50k,
  `Keyboard/Resources/freq_*.txt`, CC-BY-SA) plus a **bigram model** built
  from the OpenSubtitles corpus (`bigrams_*.bin`, 300k pairs per language,
  built with `scratchpad/bigrams.py`), edit-distance candidates weighted by
  the touch model above (static key adjacency when no touch data), the
  system `UITextChecker` as a validity check and as a source of candidates
  beyond the list. Candidates are scored by 0.75·P(word|previous) +
  0.25·P(word), so context decides ("превет мир" → "привет"). Known words
  are never overridden.
  Correction runs **in the background** on space/punctuation (typing never
  waits) and is applied only if the word is still right before the caret;
  backspace right after reverts it. **It learns**: a reverted correction or
  a "keep as typed" pick adds the word to your personal lexicon (never
  corrected again, offered in suggestions), a fix you pick from the bar is
  remembered for that typo, and an unknown word you keep three times
  becomes yours. Personal data lives in the App Group defaults.
  Top bar: while typing — the typed word (quoted if unknown) and the best
  fixes/completions; after a space — the three likeliest next words;
  **tap into a word** — alternatives for that word, and if Skald had
  auto-corrected it, what you originally typed comes first. Text
  Replacement shortcuts from iOS Settings apply too. Toggles in Settings →
  Typing. Only the current layout's dictionary is kept in memory (~10 MB);
  the three shipped languages take 12 MB of the bundle.
- **Layout switching = swipe on the space bar** (left: next, right:
  previous) through the layouts chosen under Settings → Keyboard layouts.
  The space key shows the current one (`ру`, `ук`, `en`) and faint ‹ ›
  chevrons when more than one layout is enabled. The idea is to keep
  only the English system keyboard and let Skald cover the rest.
- **Emoji key**: in-keyboard emoji panel, 1 898 emoji in 9 categories plus
  Recents (generated from Unicode `emoji-test.txt`, `Keyboard/EmojiData.swift`).
- **Top bar** = the system-style suggestion strip, with two translation
  controls on the right:
  - **Translate** button (source is always the current layout's language,
    target from the panel). Tap: the strip becomes `× | translation field | ↑`,
    the settings button hides, the return key stays standard. What you type
    goes into the field (plain text, no live translation); ↑ translates it
    and inserts the result into the app, then closes the field. With an
    empty field ↑ translates the text already before the cursor in place.
    Swipe left/right in the field to recall the last five texts you sent
    this session. **Undo** (after an insertion) takes it back.
  - **Style button**: a panel over the keys with *Layouts* (which languages
    the space-bar swipe cycles), *Translate to*, *Engine*
    (Apple / Google / DeepL / Claude) with a one-line hint per engine (cost,
    limits) and, for DeepL / Claude, **Paste key** from the clipboard (needs
    Full Access; keys can also be entered in the app) and Clear. With Claude
    a *Style* row appears: five tone icons over a gradient slider that snaps
    to them — style is always on for Claude.
- Direction in the translation field: current layout → "translate to"
  (or → primary when you're typing in the "translate to" language, or the
  language picked in the panel). In-place translation of existing text
  still detects the language.
- Google, DeepL and Claude need **Allow Full Access** (network). Without it
  the keyboard says so instead of failing silently. The Apple engine runs
  offline, but language packs must be downloaded from the app first —
  a keyboard extension can't show the download sheet.

## Matching the system keyboard

Measured against the iOS 26.4 simulator (light) and iOS 27 device photos
(dark); constants live in `KeyboardMetrics` / `KeyboardPalette`
(`Keyboard/KeyboardView.swift`):

| | value |
|---|---|
| key height / row pitch | 42 pt / 54 pt |
| key gap / side inset | 7 pt / 6 pt |
| corner radius | 7 pt |
| small keys (123, emoji, lang) / return | 43.5 pt / 2×43.5+7 |
| letters | SF 23 pt regular |
| light: background / keys | `#DFE0E6` / `#FFFFFF`, no shadow |
| dark: background / keys | `#212121` / `#454545` |

All keys share one colour (iOS 26+ dropped the grey special keys). Return
shows the ⏎ symbol for the default return type, the space key is blank with
the language code (`ру`, `ук`, `en`) in its corner. Layouts: RU 11/11/9 (ъ, ё
via long-press), UK 12/12/10 with the apostrophe key and ґ, as on iOS 27.

Pixel sampling helper used for the measurements: `scratchpad/px.swift`
(a 40-line CoreGraphics tool, not part of the project).

## Build & run

```bash
cd SkaldMobile
xcodegen generate
xcodebuild -project Skald.xcodeproj -scheme Skald \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Skald.app
xcrun simctl launch booted com.ivshestakov.skald.ios
```

Then in the simulator: Settings → General → Keyboard → Keyboards → Add New
Keyboard → Skald → Allow Full Access. In the app's Translate tab, long-press
🌐 and pick Skald.

Simulator gotcha: if no software keyboard appears, the Simulator has
"Connect Hardware Keyboard" on (I/O → Keyboard, ⇧⌘K). Or:
`defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false`
and restart Simulator.app.

Gotcha: iOS keeps the keyboard-extension process alive across reinstalls,
so a rebuilt keyboard may still show the old code. Kill it after installing:

```bash
xcrun simctl spawn booted launchctl list | grep skald.ios.keyboard | awk '{print $1}' | xargs -I{} xcrun simctl spawn booted /bin/kill -9 {}
```

## Release to TestFlight

`./release-ios.sh` = xcodegen → `xcodebuild archive` (Release, **manual
signing**) → `-exportArchive` to an IPA → `xcrun altool --upload-app`. Signing
uses two App Store profiles created through the ASC API and the Apple
Distribution cert of team 975ZZPJQNB; the App Group is assigned to both
bundle IDs in the developer portal (the public API can enable the
capability but can't assign a group — that step was done in the web UI).
Xcode's automatic signing with the ASC key failed with "Authentication
failed: bearer token", hence manual. App Store Connect app: "Skald
Translator", Apple ID 6812791271; TestFlight internal group "Internal".

For a device: open `Skald.xcodeproj` in Xcode, make sure the Apple ID for
team 975ZZPJQNB is signed in, and run. Automatic signing registers the App
Group.

## Known gaps / next steps

- The Apple (on-device) engine has not been verified inside the extension.
- `documentContextBeforeInput` only reaches back to the current paragraph;
  multi-paragraph messages translate paragraph by paragraph.
- No swipe typing; autocorrect is dictionary-based, not contextual.
- CJK languages fall back to the Latin layout (you can still translate text
  typed with a system CJK keyboard by switching to Skald and tapping
  Translate).
- Shared code is a copy of the Mac app's, not a Swift package; keep the
  Claude prompt and tone directives in sync by hand for now.
- App Store: needs privacy nutrition labels (Full Access disclosure),
  screenshots, and a keyboard-extension review note.
