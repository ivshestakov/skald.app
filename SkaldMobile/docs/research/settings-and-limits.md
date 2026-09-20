# iOS keyboard: native feature inventory vs. what a third-party extension can reproduce

Scope: iOS 17 → 26 (Apple's current feature-availability page already labels itself iOS/iPadOS 27; language lists below are from that page as fetched 2026-09-17 — features are additive, so they hold for 26).
Tags: **DOC** = documented by Apple; **OBS** = observed/reported by developers or users; **INF** = inferred.

---

## PART A — Native keyboard feature inventory

### A1. Settings → General → Keyboard (iPhone)

Apple documents the location ("Turn the typing features (below All Keyboards) on or off") and most descriptions; the exact list below is OBS from iOS 17–26 devices. Every "All Keyboards" toggle ships **ON**; One-Handed Keyboard Off; Dictation off until the user taps *Enable Dictation* (OBS).

| Item | What it does | Default |
|---|---|---|
| **Keyboards (N)** | List of enabled input modes; *Add New Keyboard*; swipe to delete; *Edit* to reorder. Tap a language → **Software Keyboard Layout** / **Hardware Keyboard Layout**. Third-party keyboards appear here with an **Allow Full Access** switch (DOC). | — |
| **Text Replacement** | Shortcut → phrase expansion ("omw" → "On my way!" preinstalled). A phrase with an empty shortcut = "don't autocorrect this word". Synced via iCloud Drive. Chinese/Japanese support word/input pairs (DOC). | — |
| **One-Handed Keyboard** | Off / Left / Right; also reachable by long-pressing 🌐/emoji key (DOC). iPhone only. | Off |
| **Auto-Capitalization** | Capitalises first word of sentences and proper nouns (DOC). | On |
| **Auto-Correction** | "Uses your keyboard dictionary to spellcheck words as you type, automatically correcting misspelled words" (DOC). iOS 17+: on-device **transformer language model** runs on every keystroke, sentence-level grammar fixes, corrected words are briefly underlined and tappable to revert, learns your profanity (DOC — Apple newsroom WWDC23). | On |
| **Check Spelling** | Red-underlines misspellings without changing them; independent of Auto-Correction (DOC). | On |
| **Enable Caps Lock** | Double-tap ⇧ locks caps (DOC). | On |
| **Predictive Text** | Suggestion bar above keys (words, emoji, contextual info such as location/phone number). Turning it off also disables inline predictions (DOC). | On |
| **Show Predictions Inline** (17.2+) | Grey ghost-text completion of word/sentence; Space accepts, keep typing rejects (DOC). | On |
| **Slide to Type** (QuickPath) | Swipe across letters; can mix with tapping mid-sentence (DOC). | On |
| **Delete Slide-to-Type by Word** | One ⌫ after a swiped word deletes the whole word (DOC). | On |
| **Character Preview** | Magnified key pop-up on tap (iPhone only) (DOC/OBS). | On |
| **"." Shortcut** | Double-Space inserts ". " (DOC). | On |
| **Smart Punctuation** | Straight → curly quotes, `--` → em dash (DOC). | On |
| **Stickers** (was **Memoji Stickers** ≤ iOS 16) | Shows Memoji/Live stickers in the emoji keyboard (OBS). | On |
| **Enable Key Flicks** (iPad only) | Each key shows a secondary number/symbol; flick down to type it (OBS/DOC iPad guide). | On |
| **Enable Dictation** | Adds mic key; on-device processing "in many languages"; *About Dictation & Privacy* link; **Dictation Languages** sub-list when several keyboards exist (DOC). | Off until enabled |
| **Auto-Punctuation** | Dictation inserts commas/periods/question marks automatically (DOC). | On |

Related places:
- **Sounds & Haptics → Keyboard Feedback**: **Sound** (obeys Silent switch) and **Haptic** (does not obey Silent; requires Accessibility → Touch → Vibration on; "might affect battery life"), iOS 16+ (DOC). Defaults: Sound on, Haptic off (OBS).
- **Accessibility → Keyboards & Typing**: **Show Lowercase Keys** (off = keycaps always uppercase), **Key Repeat** (delay/rate/off, external kb), **Sticky Keys**, **Slow Keys**, **Full Keyboard Access** (DOC). **Accessibility → Touch → Haptic Touch** duration also changes long-press latency for key alternates (OBS).
- **General → Transfer or Reset iPhone → Reset → Reset Keyboard Dictionary**: "All custom words and shortcuts are deleted, and the keyboard dictionary returns to its default state" (DOC). Rejecting the same correction a few times also stops it (DOC).
- Long-press 🌐/emoji key → **Keyboard Settings** shortcut, one-handed layouts, keyboard picker (DOC). Long-press Space → trackpad cursor mode (system keyboard only).

### A2. Language coverage (Apple feature-availability page, fetched 2026-09-17 — DOC)

| Feature | English | Russian | Ukrainian |
|---|---|---|---|
| Keyboard exists | yes (9 regional variants) | yes | yes |
| Autocorrection | yes | **yes** | **yes** |
| Predictive Typing (bar) | yes | **yes** | **yes** |
| Inline Predictions | yes | **no** (only EN, FR, ES variants) | **no** |
| QuickPath (Slide to Type) | yes | **no** | **no** |
| Multilingual Typing | yes | **no** | **no** |
| Dictation | yes | yes | yes |
| On-device dictation | yes | yes | **no** |

Consequence: for RU/UK the native keyboard gives tap autocorrect, a 3-slot prediction bar and spell underline, but no swipe, no ghost text, no auto language switching — exactly the gaps a third-party keyboard can fill.

### A3. "Multilingual typing" pairs
- Mechanism (DOC): "For some supported languages, you can type in two languages without having to switch between keyboards. Your keyboard automatically switches between the two languages you use most often." It works implicitly when two keyboards from the *Multilingual Typing* list are enabled (e.g. English + Spanish/French/German…). Only Latin/CJK/Indic languages are in the list; **no Cyrillic language qualifies**, so RU↔EN or UK↔EN never auto-switch on the native keyboard.
- iOS 18 **bilingual keyboards** (DOC): *Add New Keyboard → Add to [language] Keyboard* for "select language pairs" (English+Spanish (Latin America), English + up to two Indian languages, Korean+English). iOS 26 added Arabic+English bilingual and Arabizi transliteration; Hindi transliteration gets bilingual suggestions (OBS). None of this exists for RU/UK.

### A4. Layouts and long-press alternates
**English (US)** — QWERTY, rows 10/9/7; Software layouts: QWERTY / AZERTY / QWERTZ / Dvorak (iOS 16+) (DOC). Long-press alternates on a c e i l n o s u y z (àáâäæãåā, çćč, èéêëēėę, îïíīįì, ł, ñń, ôöòóœøōõ, ßśš, ûüùúū, ÿ, žźż) and on punctuation (`-`→–—•, `'`→‘’`, `"`→“”„«», `?`→¿, `!`→¡, `.`→…, `$`→€£¥₩¢, `&`→§, `0`→°); iOS 17 added 71 more → 164 accented letters (OBS, Gadget Hacks).

**Russian (iPhone)** — ЙЦУКЕН, rows 11/11/9: `й ц у к е н г ш щ з х` / `ф ы в а п р о л д ж э` / `я ч с м и т ь б ю`. **ё** = long-press **е**; **ъ** = long-press **ь** (OBS, Apple Community, iOS 16–18). One software layout only; *Russian – PC* and *Russian – Phonetic* exist only as **hardware** layouts (OBS, MacStories). On iPad's wider rows ъ (and on large iPads ё) get dedicated keys (OBS, unverified for every model).

**Ukrainian (iPhone)** — rows 11/11/9: `й ц у к е н г ш щ з х` / `ф і в а п р о л д ж є` / `я ч с м и т ь б ю`. **ї** = long-press **і**; **ґ** = long-press **г** (OBS, Apple Community 2024). **Apostrophe is not on the letter layer** — only on the `123` layer (OBS, long-running user complaint). Until iOS 17 the Ukrainian keyboard also hid Russian letters (ъ under ь, ы under и, э under є); **iOS 18 removed them** (OBS).

---

## PART B — What a keyboard extension can and cannot do

### B1. UITextDocumentProxy (DOC unless noted)
- Protocol = `UIKeyInput` (`insertText`, `deleteBackward`, `hasText`) + `UITextInputTraits` + proxy members; Apple: "get the selected text, insert or delete text, manipulate the text insertion position, and get surrounding textual context in order to support things like autocorrect or autocomplete."
- `documentContextBeforeInput` / `documentContextAfterInput: String?` — no documented size. OBS: bounded by the current **paragraph** ("any new paragraph may stop the proxy from fetching more content" — KeyboardKit); developers report only "the last two sentences" in WhatsApp/Signal/Telegram after paste, `nil` in Gmail/Mail after paste until edited, a practical ceiling of a few hundred characters. Full-document reads require walking the caret with `adjustTextPosition` and re-reading (KeyboardKit Pro) — visibly moves the cursor.
- `selectedText: String?` (iOS 11) — read-only; the extension **cannot create or change a selection** ("Because a custom keyboard can draw only within the primary view … it cannot select text").
- `adjustTextPosition(byCharacterOffset:)` — moves caret by characters; the only cursor control available. OBS: offsets are UTF-16-ish and emoji/newlines can misbehave; it is also the standard hack to force a context refresh.
- `setMarkedText(_:selectedRange:)` / `unmarkText()` — IME-style composition: "Calling setMarkedText selects the text specified by range … the nonselected portion is marked with a background color." It is underlined/highlighted composition text, **not** grey ghost text, and web views/some apps handle it poorly (OBS).
- `documentIdentifier: UUID` (iOS 11) — detect field switches; `documentInputMode` — host's current `UITextInputMode` (language hint).
- Batching quirks (OBS): the host applies `insertText`/`deleteBackward` asynchronously, so context read immediately afterwards is stale (KeyboardKit adds delays); `deleteBackward` removes whatever the host treats as one character (usually a grapheme cluster); rapid deletes across paragraphs lag.
- `UITextInputDelegate` callbacks: `textWillChange/textDidChange` fire on focus and caret moves, **not** on every external edit (hardware keyboard, paste, other keyboard); `selectionWillChange/selectionDidChange` effectively never fire (OBS, Apple forum thread open since 2016). Polling with ±1 `adjustTextPosition` is the known workaround.
- Traits exposed via the proxy (DOC): `keyboardType`, `keyboardAppearance`, `returnKeyType`, `textContentType`, `isSecureTextEntry`, `enablesReturnKeyAutomatically`, `autocapitalizationType`, `autocorrectionType`, `spellCheckingType`, `smartQuotesType`, `smartDashesType`, `smartInsertDeleteType`, `passwordRules`, `inlinePredictionType` (iOS 17), `mathExpressionCompletionType` (18), `writingToolsBehavior` (18.1), `conversationContext` (18.4), `grammarCheckingType`. OBS: unset traits read `.default`; apply system defaults yourself.
- **Not exposed**: the system's autocorrect candidates, spell-check state, learned words, or predictions — Apple says users "expect … autocorrection, autocapitalization, smart quotes" but offers no API; you implement them. Settings → General → Keyboard toggles are invisible too ("does not have access to most of the general keyboard settings"); ship your own settings.

### B2. Helper APIs
- **UITextChecker** (iOS 3.2, DOC): `rangeOfMisspelledWord`, `guesses(forWordRange:)`, `completions(forPartialWordRange:)`, `learnWord/unlearnWord/hasLearnedWord`, `ignoreWord`, class `availableLanguages`. OBS: dictionary + edit distance, context-free, completions are prefix lists, learned words are device-wide but absent from completions; far below native quality. Check `availableLanguages` at runtime; ru/uk spell dictionaries exist on iOS (INF from Apple's Autocorrection list).
- **UILexicon** via `requestSupplementaryLexicon` (iOS 8, DOC): term pairs (`userInput` → `documentText`) from contacts' first/last names, user's Text Replacement list and "a common words dictionary"; available **without** Full Access; Apple says it is "supplementary to an autocorrection/suggestion lexicon of your own design". OBS: the common-words portion is small.

### B3. Feedback, audio, network, memory
- **Haptics**: `UIFeedbackGenerator` produces nothing unless **Allow Full Access** is on (OBS — Apple forum since 2016, KeyboardKit docs "feedback isn't generated unless the user enables Full Access"). Not stated in Apple docs.
- **Sound**: `UIDevice.playInputClick()` needs `UIInputViewAudioFeedback` + `enableInputClicksWhenVisible`, honours the user's keyboard-click setting (DOC); Apple lists "ability to play audio, including keyboard clicks using playInputClick" under Full Access (DOC). `AudioServicesPlaySystemSound` needs no audio session; `AVAudioPlayer` does (OBS).
- **Network**: none without Full Access ("the system ensures that keystrokes cannot be sent back to you or anywhere else") (DOC).
- **Memory**: "that process has a limit … If your keyboard extension exceeds the memory limit the system terminates it … limits vary from model to model … dismissing the keyboard won't necessarily terminate the extension process" (DOC). Numbers (OBS): ~48 MB on older devices, ~60 MB phys_footprint (Kibo; Grammarly "≈60 MiB budget"), ~70 MB (KeyboardKit). Overrun = silent jetsam kill, no crash log, user bounced to the previous keyboard.
- **Latency**: Grammarly targets ≈17 ms per touch event (60 Hz) for its whole pipeline (OBS).

### B4. Hard boundaries
- **Secure fields**: "When a user taps in a secure text input object, the system temporarily replaces your custom keyboard with the system keyboard"; also ineligible for `phonePad`/`namePhonePad`; apps may block all extensions via `shouldAllowExtensionPointIdentifier` (DOC).
- **Dictation**: system Dictation cannot be invoked; Apple's guide says extensions "have no access to the device microphone". OBS: with Full Access + `NSMicrophoneUsageDescription` an extension *can* record (Gboard/SwiftKey voice typing), but AVAudioSession activation is flaky (forum errors 561015905/561145187) and you must supply your own recogniser.
- **URLs/apps**: iOS 18 broke the responder-chain `openURL` hack ("needs to migrate to UIApplication.open… Force returning false"); only a SwiftUI `Link` still opens URLs (OBS, KeyboardKit). Guideline 4.4.1 forbids launching "other apps besides Settings" anyway.
- **Drawing**: only inside the extension's own view — no key pop-ups above the top edge, no UI at the caret, so no inline autocorrect bubble or ghost text (DOC).
- **Pasteboard**: requires Full Access (DOC).
- **Emoji**: no API to summon the system emoji panel, Memoji/Genmoji or sticker drawer; build your own emoji grid/search (INF). Users can still switch to the system *Emoji* input mode via the globe key.
- **Trackpad / selection**: caret movement via `adjustTextPosition` is fine (Gboard's Space-bar cursor), but no selection, no edit menu (DOC).

### B5. System chrome, height, Full Access, review
- **Globe/dictation bar**: "On iPhones with Face ID, iOS automatically shows the globe icon below your keyboard view and sets [`needsInputModeSwitchKey`] to false"; elsewhere you must draw a next-keyboard key wired to `handleInputModeList(from:with:)` with `.allTouchEvents` so long-press shows the picker (DOC). The system bar's mic runs Apple dictation when enabled (OBS).
- **Height**: width is system-set; set a height constraint on the primary view after it first draws; support compact/regular widths, rotation and the iPad floating keyboard (DOC). The Face-ID bottom bar sits outside your view (OBS).
- **Allow Full Access** grants (DOC): network, App Group **write** access (read-only works without it), pasteboard, Location/Contacts (with permission), iCloud, IAP/Game Center via the container app, MDM; `hasFullAccess` (iOS 11) reports it. iOS warns users it "allows the developer of this keyboard to transmit anything you type" (OBS). Privacy rules: use data only for text input, don't retain keystrokes/voice, treat the autocorrect lexicon as private.
- **App Review 4.4.1** (DOC, verbatim): must "Provide keyboard input functionality; Follow Sticker guidelines if the keyboard includes images or emoji; Provide a method for progressing to the next keyboard; Remain functional without full network access and without requiring full access; Collect user activity only to enhance the functionality of the user's keyboard extension"; must not "Launch other apps besides Settings; or Repurpose keyboard buttons for other behaviors". Plus App Privacy labels for anything collected under Full Access.

### B6. How leading third-party keyboards approximate native autocorrect
- **Gboard**: on-device CIFG-LSTM next-word/autocorrect models trained by **federated learning with differential privacy**; per-language packs; personal dictionary; RU and UK supported on iOS (glide for both — INF). Key-target adjustment via touch-model rescoring (OBS).
- **SwiftKey**: first on-device neural LM (2016); personal LM learned from typing (optional cloud personalisation via Microsoft account); RU/UK supported (OBS).
- **Grammarly iOS**: 2-layer LSTM seq2seq swipe decoder, 7.5 M params, 33 features per touch point incl. **26 per-letter proximity scores** (= key-target model); candidate generator = tap autocorrect (edit-distance similarity × context LM score); everything on-device within ≈60 MiB and ≈17 ms (OBS, engineering blog).
- **Fleksy SDK**: unified LM for autocorrect + next-word (n-gram → neural), `LayoutPoint` tap geometry passed into the engine, `TypingContext` for previous words, 80+ languages, fully on-device (OBS, docs).
- **KeyboardKit Pro**: local autocomplete "for many of the 77 supported languages", remote autocomplete hook, next-word prediction via Apple Foundation Models / Claude / OpenAI; the open-source core ships no autocomplete engine (OBS).
Common recipe: touch-point → per-key probabilities → weighted-edit-distance candidates from a frequency dictionary → rescoring by an on-device n-gram/small neural LM over the previous 2–3 words from `documentContextBeforeInput` → user lexicon (accepted/undone corrections, UILexicon, Text Replacement) → shown in the keyboard's own strip, since inline UI is impossible.

---

## Reproducibility matrix

| Native feature | Reproducible by extension? | Why |
|---|---|---|
| Auto-Capitalization | **partly** | Must be reimplemented from `autocapitalizationType` + context; context is paragraph-bounded and stale after external edits (OBS). |
| Auto-Correction (iOS 17 transformer quality) | **partly** | Own dictionary/LM inside ~60 MB; UITextChecker is context-free; correction bubble/revert-underline at caret impossible (DOC). |
| Check Spelling (red underline) | **no** | Cannot draw in the host field; only a strip indicator (DOC). |
| Enable Caps Lock | yes | Pure keyboard UI. |
| Predictive Text bar | yes | Own strip inside the keyboard view; own model (DOC/OBS). |
| Show Predictions Inline (ghost text) | **no** | No caret UI; `setMarkedText` gives highlighted composition, not grey text (DOC/OBS). |
| Slide to Type (incl. RU/UK) | yes | Own gesture decoder (Grammarly/Gboard prove it); memory/latency budgets apply (OBS). |
| Delete Slide-to-Type by Word | yes | Track your own swiped words; `deleteBackward` loop (OBS). |
| Character Preview | **partly** | Pop-ups only inside your view; top-row previews cannot extend above the keyboard (DOC). |
| "." Shortcut / Smart Punctuation / Smart insert-delete | yes | Read the traits, implement in `insertText` (DOC). |
| Text Replacement (user's list) | yes | Delivered via UILexicon without Full Access (DOC). |
| Contacts names in autocorrect | yes | UILexicon (DOC). |
| Keyboard dictionary learning / Reset | **partly** | Own store (App Group); `UITextChecker.learnWord` is device-wide but not visible in completions (OBS). |
| Multilingual auto-switching (RU⇄EN) | yes | Own language ID — and native lacks it for Cyrillic (DOC). |
| Multiple layouts / long-press alternates | yes | Pure UI. |
| One-Handed Keyboard | yes | Own layout; system 🌐 long-press menu not available (INF). |
| Key Flicks (iPad) | yes | Gesture in own view. |
| Keyboard sound (click) | **partly** | `playInputClick` only with Full Access (DOC). |
| Keyboard haptics | **partly** | Only with Full Access (OBS). |
| Dictation | **partly/no** | System dictation impossible; own STT needs Full Access + mic, flaky (DOC/OBS). |
| Emoji keyboard / stickers / Memoji | **partly** | Own emoji grid yes; stickers/Memoji/Genmoji no (INF). |
| Trackpad cursor (Space long-press) | **partly** | Caret moves via `adjustTextPosition`; no selection (DOC). |
| Text selection / Cut-Copy-Paste | **no** | No selection API; pasteboard needs Full Access (DOC). |
| Secure/password fields | **no** | System swaps in its keyboard (DOC). |
| Phone-pad fields | **no** | Ineligible (DOC). |
| Globe key behaviour | yes | Required; system draws it on Face ID phones (DOC). |
| Height like system | yes | Height constraint; width fixed (DOC). |
| Open URLs / other apps | **no** | iOS 18 breakage + Guideline 4.4.1 (OBS/DOC). |
| Works offline | yes | Required by 4.4.1 (DOC). |

---

## Sources
- Apple Support — Type with the onscreen keyboard: https://support.apple.com/guide/iphone/iph3c50f96e/ios
- Apple Support — Use predictive text: https://support.apple.com/guide/iphone/iphd4ea90231/ios
- Apple Support — Add or change keyboards: https://support.apple.com/guide/iphone/iph73b71eb/ios
- Apple Support — Set up shorthand / Reset Keyboard Dictionary: https://support.apple.com/guide/iphone/iph6d01d862/ios
- Apple Support — Dictate text: https://support.apple.com/guide/iphone/iph2c0651d2/ios
- Apple Support — Keyboard accessibility settings: https://support.apple.com/guide/iphone/ipha7c3927eb/ios
- Apple Support — Keyboard sounds or haptics: https://support.apple.com/en-us/102463
- Apple Support — Auto-Correction and predictive text: https://support.apple.com/en-us/104995
- Apple Support — Three languages in one keyboard (iOS 18): https://support.apple.com/en-us/121233
- Apple — iOS & iPadOS Feature Availability: https://www.apple.com/ios/feature-availability/
- Apple Newsroom — iOS 17 preview (transformer autocorrect): https://www.apple.com/newsroom/2023/06/ios-17-makes-iphone-more-personal-and-intuitive/
- Apple — App Extension Programming Guide: Custom Keyboard: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- Apple Developer — Creating a custom keyboard: https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- Apple Developer — Configuring open access: https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
- Apple Developer — Handling text interactions: https://developer.apple.com/documentation/uikit/handling-text-interactions-in-custom-keyboards
- Apple Developer — UITextDocumentProxy / UIInputViewController / UITextInputTraits / UITextChecker / UILexicon / playInputClick: https://developer.apple.com/documentation/uikit/uitextdocumentproxy , …/uiinputviewcontroller , …/uitextinputtraits , …/uitextchecker , …/uilexicon , …/uidevice/playinputclick()
- Apple — App Review Guidelines §4.4.1: https://developer.apple.com/app-store/review/guidelines/
- Apple Developer Forums — haptics need Full Access: https://developer.apple.com/forums/thread/63493 ; textDidChange not called: https://developer.apple.com/forums/thread/45121 ; context limited to last sentences: https://developer.apple.com/forums/thread/772158 ; nil context after paste: https://developer.apple.com/forums/thread/812642 ; mic in extension errors: https://developer.apple.com/forums/thread/775077
- KeyboardKit — full-context proxy trick: https://keyboardkit.com/blog/2022/10/05/uitextdocumentproxy-full-context ; iOS 18 URL breakage: https://keyboardkit.com/blog/2024/09/11/ios18-breaks-selector-based-url-opening ; autocomplete: https://keyboardkit.com/features/autocomplete ; Liquid Glass: https://keyboardkit.com/blog/2025/07/28/custom-ios-keyboard-extensions-and-liquid-glass
- Memory limits: https://dev.to/tbds_2dadf2b626f315902eae/the-three-hard-constraints-of-an-ios-keyboard-extension-46af ; https://github.com/facebook/react-native/issues/31910
- Grammarly Engineering — swipe typing: https://www.grammarly.com/blog/engineering/deep-learning-swipe-typing/
- Fleksy — LM post: https://medium.com/@fleksy/boosting-text-prediction-with-our-new-language-model-f80fea39eb37 ; SDK docs: https://docs.fleksy.com/core-sdk/
- Google Research — Gboard federated learning / DP: https://research.google/blog/advances-in-private-training-for-production-on-device-language-models/ ; https://arxiv.org/pdf/2305.18465
- SwiftKey neural engine: https://venturebeat.com/business/swiftkey-mobile-keyboard-neural-networks
- NSHipster — UITextChecker: https://nshipster.com/uitextchecker/
- Kodeco — needsInputModeSwitchKey on Face ID devices: https://www.kodeco.com/49-custom-keyboard-extensions-getting-started/page/2
- Apple Community — Russian ё/ъ: https://discussions.apple.com/thread/255211339 ; Ukrainian ї long-press: https://discussions.apple.com/thread/255690493 ; Ukrainian apostrophe: https://discussions.apple.com/thread/254009343 ; iOS 18 removed hidden Russian letters: https://discussions.apple.com/thread/255761660
- MacStories — software vs hardware layouts (Russian): https://www.macstories.net/tutorials/hardware-keyboards-and-ios-international-keyboard-layouts/
- Gadget Hacks — iOS 17 long-press characters: https://ios.gadgethacks.com/how-to/71-more-special-characters-are-hiding-within-your-keyboard-ios-17-and-ipados-17-heres-whats-new-0385398/ ; iOS 17–27 keyboard changes: https://apple.gadgethacks.com/news/ios-27-keyboard-improvements-explained-3-years-of-updates/
- Gboard Help — voice typing on iOS: https://support.google.com/gboard/answer/2781851?co=GENIE.Platform%3DiOS
