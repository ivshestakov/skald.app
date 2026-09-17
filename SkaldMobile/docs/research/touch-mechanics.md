# iOS System Keyboard — Touch, Gesture, Cursor & Feedback Mechanics (iPhone, iOS 17–26)

Labels: **D** = DOCUMENTED (Apple source: User Guide, HIG, developer docs, Apple patent) · **O** = OBSERVED (credible hands-on / measured report) · **I** = INFERRED (no published figure; best estimate, stated as such).

## 1. Space-bar trackpad

- **Activation (D):** "Touch and hold the Space bar with one finger until the keyboard turns light gray and the characters on the keys disappear — now it's a trackpad." Duration unpublished; Apple's app-level long-press default is 0.5 s and the accent pop-up is reported at "about half a second" — **estimate 0.4–0.5 s (I)**. Whether Accessibility ▸ Touch ▸ Haptic Touch speed shortens it is claimed by one how-to site, unconfirmed (I).
- **Visual (D):** keys blank (labels hidden), keyboard lightens; key rectangles remain. Patent US 9,639,184 describes "obscuring the characters on keys" and optional blur/translucency.
- **Mapping (O/I):** *relative*, not absolute — the caret moves "in relation to your finger" from wherever it was; it does not jump to a position under the finger. Speed-dependent gain: "the faster you drag your thumb, the more distance the cursor covers" (O). Points-per-character is unpublished; at slow speed roughly one character per ~5 pt of travel (KeyboardKit, which imitates the native feel, uses 5 pt/char as its "medium" default) (I).
- **Vertical (O/I):** both axes are resolved simultaneously; vertical travel moves the caret across (visual, wrapped) lines so you can "cross many lines of a long text quickly" (O). Vertical step threshold unpublished — about one line height (~15–25 pt) (I).
- **Edges (O):** at the text view's edge the view auto-scrolls (reported for the iOS 9 3D Touch variant, unchanged since). The finger must stay in contact; it may wander beyond the keyboard rectangle while tracking continues (I).
- **Selection (D):** "Touch and hold the keyboard with a second finger, then adjust the selection by moving the first finger." Selection anchors at the caret position when the second finger lands. On 3D Touch iPhones (6s–XS, iOS 9–12) a *deeper press* started selection; further deep presses extended to word/sentence (O). iPad additionally offers two-finger drag anywhere (D). iOS 12 brought the space-bar method to every iPhone; iPhone 11+ (Haptic Touch) use space only (O).
- **Release (D/I):** lifting ends the mode with the caret where it was left; no space is inserted — Apple's steps never mention a space and the patent describes lift-off as "ceasing to display the cursor" without insertion. Confirmed in practice (O).
- **Haptics (D for 3D Touch, I otherwise):** the patent specifies "a tactile output indicative of entry into text selection mode." On Haptic Touch phones a light tick on entry is commonly felt when keyboard haptics are on, but no source measures it (I).
- **Magnifier (O):** trackpad mode shows no loupe; the loupe belongs to direct caret dragging (see §9).

## 2. Key press semantics

- **Letters/digits/symbols commit on touch-up (O).** Frame-by-frame measurement (simulator, iOS 17-era): the character appears in the same frame the pop-up disappears, **67–74 ms after finger lift**; a 150 ms press yields a pop-up visible 210–223 ms. That post-release delay is consistent with a rollover/disambiguation window (I).
- **Modifiers act on touch-down (D by implication):** Apple documents "touch Shift, then slide to a letter" and "hold 123, slide to a character, release" — the plane switches while the finger is down, and after release the keyboard returns to letters/lowercase automatically (D/O). Delete acts on touch-down and repeats (O). Globe/emoji key switches on release; holding it opens the keyboard menu (D for hold; release timing I). Space acts on release (a hold becomes the trackpad) (I).
- **Slide before release (O/I):** the pop-up follows the finger; the key under the release point is typed. Apple's patent US 7,694,231 claims exactly "detecting a change in position of the contact and selecting the symbol corresponding to the current position." With Slide to Type on, a longer slide is interpreted as QuickPath (D).
- **Multi-touch (O/I):** two-finger *double-tap* on the keyboard selects the last word and *triple-tap* the last sentence (undocumented system gesture, cannot be disabled; still present in iPadOS 26). Rollover: a second touch-down while the first key is still held commits the first key; both letters are inserted in touch-down order (I — universally relied on, no published measurement).
- **Pop-up ("Character Preview") (O):** iPhone only (iPad full-size keyboard never had it); toggle Settings ▸ General ▸ Keyboard ▸ Character Preview (since iOS 9). Appears at touch-down, sits above the key, roughly 1.7× key width, ~55 pt tall with a ~10 pt radius and a short neck into the key; edge keys' balloons lean inward (O; KeyboardKit's imitation: min height 55, radius 10, neck 8×15, large-title light glyph). Lingers ~70 ms after lift (O, measured). Shown for character keys only — Shift, 123/#+=, Delete, Return, Space, Globe show a *pressed-state colour inversion* instead (dark grey → white in light mode; #474747 → #6B6B6B in dark) (O/I).

## 3. Long-press

- **Delay ≈ 0.5 s (O)**; a callout of alternates appears above the key; slide to an option and release to insert (D). Releasing without moving inserts the base character; sliding away from the callout and releasing cancels (I).
- **EN layout alternates (O):** a→à á â ä ã å æ; c→ç č; e→è é ê ë; i→ì í î ï; l→ł; n→ñ; o→ò ó ô ö õ ø œ; s→ß š; u→ù ú û ü; y→ý; z→ž ź ż. 123 page: 0→°; -→– — •; $→£ ¥ € ₩ ₹ (plus others by region); &→§; "→“ ” « » „; .→…; '→‘ ’ ′; %→‰. Comma: no alternates confirmed (I). On URL/e-mail keyboards "." and ".com" long-press list TLDs (.com .net .org .edu .us .eu .uk …) (O).
- **RU layout (O):** е→ё, ь→ъ. **UK layout (O):** г→ґ, і→ї (ї has no dedicated key on iPhone), apostrophe only on the 123 page; until iOS 17 the UK keyboard also offered ь→ъ, и→ы, є→э — removed in iOS 18.
- **Special keys:** Space → trackpad (D). Shift → held shift, slide to letter (D). 123 / #+= → momentary layer, auto-return on release (O). Globe/emoji → keyboard list, "Keyboard Settings", one-handed layout buttons (D). Delete → auto-repeat (O). Emoji → skin-tone/variant picker (D). Return → nothing special (I).

## 4. Backspace

- Tap = one character. Hold (O, measured in a terminal app receiving the events): first repeat after **≈500 ms**, then **≈100 ms per character** for ≈20 repeats (≈2.5 s from touch-down), after which iOS switches to **word-by-word deletion at ≈350 ms per word**. Apple's manuals describe this as "three speeds" (O). Accessibility ▸ Keyboards & Typing ▸ Key Repeat applies to *external* keyboards only (D).
- **Delete Slide-to-Type by Word (D):** "If you tap Delete after sliding to type a word, it deletes the whole word"; Settings ▸ General ▸ Keyboard toggle.
- **Autocorrect undo:** iOS 17+: corrected words are temporarily underlined; tap → your original spelling is listed first (D). Pre-iOS 17: tapping Delete immediately after a correction offered the original word in a bubble (O). Haptics on each repeated deletion: not documented; ticks are commonly felt per deleted character (I).

## 5. Shift and caps

- Auto-Capitalization (Settings ▸ General ▸ Keyboard) shifts at sentence start; Shift is single-shot — resets after one character (D/O). Tapping Shift while auto-shifted turns shift off (O).
- **Caps Lock (D):** double-tap Shift (requires "Enable Caps Lock", on by default); the double-tap "must be quick" — window unpublished, ≈0.3 s (I). Tap again to release.
- **Icons (O):** outline arrow = off; filled arrow = shifted; filled arrow with underline = caps lock. Key legends change case live since iOS 9 (Accessibility ▸ Keyboards & Typing ▸ Show Lowercase Keys, D).
- Glide from Shift to a letter types one uppercase letter (D).

## 6. Space, period, Smart Punctuation

- **Double-space period (D/O):** double-tap Space "ends a sentence with a period and a space" and the next letter is auto-capitalised. Requires the caret to immediately follow a typed character/word — not after an existing space or punctuation; the second tap must follow promptly (window unpublished, I). Toggle: "." Shortcut.
- **Auto-return to letters (O):** on the 123 plane, typing a digit/symbol then Space returns to ABC (not in Safari's address bar); gliding from 123 returns on release (D).
- **Smart Punctuation (O):** Settings ▸ General ▸ Keyboard; straight quotes → curly, `--` → em dash.

## 7. Feedback

- **Sound (D):** Settings ▸ Sounds & Haptics ▸ Keyboard Feedback ▸ Sound (iOS 16+; "Keyboard Clicks" before). UIKit: a click "plays only if the user has enabled keyboard clicks in Settings ▸ Sounds." Muted by the Ring/Silent switch (O). Three distinct samples exist in /System/Library/Audio/UISounds: key_press_click, key_press_modifier, key_press_delete (legacy Tock.caf = SystemSoundID 1104) (O). Click fires at touch-down with the pop-up (I).
- **Haptic (D):** Keyboard Feedback ▸ Haptic, iOS 16+, Taptic-Engine iPhones; works in Silent mode (O); needs Accessibility ▸ Touch ▸ Vibration on (D); may affect battery (D). Every key tick — letters, Space, Delete, emoji (O); one report says the globe/emoji switcher gives none (O). Style: light, short "tick" (≈UIImpactFeedbackGenerator .light) per touch-down (O/I). Trackpad entry: see §1; no separate haptic reported for the long-press callout (I).

## 8. Layout and metrics (iPhone)

- **Heights (O):** portrait 216 pt (4.7"/5.4"/6.1"), ≈226 pt (Plus/Max); landscape 162 pt; Face ID phones add a 75 pt bottom strip (globe + mic) → 291 pt; QuickType bar adds ≈44 pt.
- **Grid (O, KeyboardKit's calibrated imitation):** row pitch 54 pt portrait (56 on Max), 40 pt landscape; key insets 3 pt horizontal / 5 pt vertical → key height ≈44 pt, 6 pt gaps, 3 pt side margins; corner radius 5 pt (iOS ≤18) → 9 pt and +2 pt row pitch with Liquid Glass (iOS 26). Key width = (W − 60)/10 → 31.5 pt @375, 33.3 @393, 37 @430 (I, computed).
- **Colours (O, from KeyboardKit assets matched to native):** light — key #FFFFFF, special key #ABB1BA, background #D5D6DD; dark — key #6B6B6B, special #474747, background #2C2C2C; `keyboardAppearance = .dark` in light UI — key #979797, special #757575, bg #6A6A6A; key shadow black 30 % / 70 %. iOS 26 keys are translucent, rounder "frosted glass" (O).
- **Bottom row (D/O):** Home-button iPhones: [123][globe/emoji][mic][space][return]. Face ID iPhones: [123][space][return] with the globe/emoji and dictation keys "automatically beneath the keyboard, even with custom keyboards" (D). The beneath-key is the **emoji face when only one language keyboard + Emoji** is enabled and becomes a **globe when ≥2 keyboards/third-party keyboards** are present (D); in that case a small emoji key appears beside Space (O, since iOS 13.1). Plus-size landscape extra keys (undo/redo, arrows, punctuation) existed iOS 8–10 and were removed in iOS 11 (O).
- **Return key (D):** label from UIReturnKeyType — return (default), Go, Search, Send, Done, Next, Join, Route, Continue, Emergency Call (Google/Yahoo legacy); "typically results in the system dismissing the keyboard." Colour: grey for default, system-blue tint for action labels (Go/Search/Done/Send/Join…); `.next` was blue in early iOS, no longer (O). Dimmed when `enablesReturnKeyAutomatically` and the field is empty (O).
- **Keyboard types (D):** default, asciiCapable, numbersAndPunctuation (opens on the 123 plane), URL (. / .com), numberPad, phonePad (+*#), namePhonePad, emailAddress (@ .), decimalPad, twitter (@ #), webSearch (space + "." prominent, Search/Go return), asciiCapableNumberPad. URL/e-mail types use different number/symbol planes (O).
- **One-handed (D):** hold globe/emoji → left/right layout; tap the arrow at the blank edge to recenter; ≈75 % width (O); portrait only, all models except SE 1st gen (D).

## 9. QuickPath, emoji, dictation, caret placement

- **QuickPath (D):** iOS 13+; "touch and hold the first letter, slide to the next letters, lift at the end of a word"; tap and slide can mix mid-sentence; the QuickType bar shows alternatives for the slid word instead of next-word predictions; one Delete tap removes the whole slid word (if enabled). A space is inserted automatically between consecutive slid words (O). Languages: English, Simplified Chinese, Spanish, German, French, Italian, Portuguese from iOS 13; Dutch, Swedish, Vietnamese and Russian added in iOS 15; Ukrainian still unsupported (O).
- **Emoji keyboard (D):** open via emoji/globe; "Search Emoji" field at top (iOS 14+); Frequently Used (clock) category; category bar below; swipe horizontally; touch-and-hold an emoji → drag to a skin-tone/variant; ABC returns; Delete key present. iOS 17 merged stickers; iOS 18.x adds Genmoji/sticker "+" (O/D).
- **Dictation (D):** mic key at lower right (in the bottom row on Home-button phones, beneath the keyboard on Face ID phones); iOS 16+: keyboard stays open, you can type while dictating; on-device in many languages; Auto-Punctuation toggle; stops after 30 s of silence or "Stop dictation".
- **Caret placement (D/O):** tap to place; **iOS 15+: touch and hold to show the magnifier (capsule loupe), then drag** (D); iOS 13–14 had no loupe — you grab the caret directly, it enlarges and (13.1+) snaps to line starts/ends (O); a first tap inside a word lands at a word boundary, long-press places within the word (O). Double-tap = word; triple-tap = paragraph in the iOS 26 guide (older guides: triple = sentence, quadruple = paragraph) (D); double-tap-and-hold then drag grab points for a block (D); three-finger pinch/spread/swipe = copy/paste/undo/redo (D).

## Parameter table

| Parameter | Native behaviour | Confidence | Source URL |
|---|---|---|---|
| Trackpad activation | Hold Space until keys blank/grey | D (gesture) / I (≈0.4–0.5 s) | https://support.apple.com/guide/iphone/select-edit-and-move-text-iph1a9cae52c/ios |
| Trackpad cursor mapping | Relative, velocity-scaled; both axes; auto-scroll at view edge | O | https://appleinsider.com/articles/15/10/11/how-to-use-ios-9s-keyboard-as-a-trackpad-with-3d-touch-on-iphone-6s- |
| Trackpad selection | Second finger holds keyboard; first finger adjusts | D | https://support.apple.com/guide/iphone/type-with-the-onscreen-keyboard-iph3c50f96e/16.0/ios/16.0 |
| Trackpad release | No space typed; mode ends | D (patent) / O | https://patents.google.com/patent/US9639184B2/en |
| Trackpad entry haptic | Tactile output on entry (3D Touch variant) | D (patent) / I (Haptic Touch) | https://patents.google.com/patent/US9639184B2/en |
| Letter commit | On touch-up; glyph appears ≈70 ms after lift | O (measured) | https://github.com/getdictus/dictus-ios/issues/507 |
| Pop-up lingering | 67–74 ms after release; 150 ms press → 217 ms visible | O (measured) | https://github.com/getdictus/dictus-ios/issues/507 |
| Shift/123 timing | Act on touch-down; glide to key, auto-revert | D | https://support.apple.com/guide/iphone/type-with-the-onscreen-keyboard-iph3c50f96e/ios |
| Slide to neighbour key | Key under release point is typed | D (patent claim) / O | https://patents.google.com/patent/US7694231 |
| Two-finger double/triple tap | Selects last word / sentence; not disableable | O | https://forums.macrumors.com/threads/undocumented-and-annoying-keyboard-multi-touch-gesture.2479914/ |
| Character Preview toggle | Settings ▸ General ▸ Keyboard (iOS 9+); iPhone only | O | https://www.howtogeek.com/242772/how-to-turn-off-the-character-popups-on-the-ios-9-keyboard/ |
| Long-press alternates delay | ≈0.5 s | O | https://unicodefyi.com/guide/type-special-chars-mobile/ |
| RU alternates | е→ё, ь→ъ | O | https://discussions.apple.com/thread/255211339 |
| UK alternates | г→ґ, і→ї; ъ/ы/э removed in iOS 18; apostrophe on 123 | O | https://discussions.apple.com/thread/255761660 |
| Backspace repeat | 500 ms delay, 100 ms/char, ~20 chars, then words @350 ms | O (measured) | https://github.com/blinksh/blink/issues/1466 |
| Delete slid word | One Delete tap removes whole QuickPath word | D | https://support.apple.com/guide/iphone/type-with-the-onscreen-keyboard-iph3c50f96e/16.0/ios/16.0 |
| Autocorrect revert | iOS 17+: tap underlined word | D | https://support.apple.com/guide/iphone/select-edit-and-move-text-iph1a9cae52c/ios |
| Caps Lock | Quick double-tap Shift; underline icon | D / I (window) | https://support.apple.com/guide/iphone/type-with-the-onscreen-keyboard-iph3c50f96e/ios |
| Double-space period | ". " + auto-cap; needs word before | D / O | https://www.iphonelife.com/content/how-to-type-period-iphone-keyboard-only-space-bar |
| 123 auto-return | Space after digit/symbol returns to ABC | O | https://forums.macrumors.com/threads/automatic-change-of-keyboard-numbers-letters.1997186/ |
| Key sound / haptic setting | Sounds & Haptics ▸ Keyboard Feedback (iOS 16+) | D | https://support.apple.com/en-us/102463 |
| Click gating | Plays only if enabled in Settings; Silent switch mutes | D / O | https://developer.apple.com/documentation/uikit/uidevice/playinputclick() |
| Haptic per key | All keys tick; works in silent mode | O | https://www.macworld.com/article/784240/ios-16-how-to-haptic-feedback-keyboard.html |
| Keyboard heights | 216/226 portrait, 162 landscape; 291 on Face ID | O | https://github.com/zoul/ios-keyboards |
| Row pitch / radius | 54 pt (56 Max) / 40 landscape; r=5 → 9 (iOS 26) | O (imitation) | https://github.com/KeyboardKit/KeyboardKit/blob/master/Sources/KeyboardKit/Layout/KeyboardLayout+DeviceConfiguration.swift |
| Key colours | Light #FFF/#ABB1BA/#D5D6DD; dark #6B6B6B/#474747/#2C2C2C | O (imitation) | https://github.com/KeyboardKit/KeyboardKit/tree/master/Sources/KeyboardKit/Resources/Colors.xcassets |
| Globe vs emoji key | Globe replaces emoji key when >1 keyboard; beneath keyboard on Face ID | D | https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards |
| Return key labels | UIReturnKeyType list | D | https://developer.apple.com/documentation/uikit/uireturnkeytype |
| Keyboard types | UIKeyboardType list | D | https://developer.apple.com/documentation/uikit/uikeyboardtype |
| One-handed | Hold globe/emoji → left/right; tap edge to recenter | D | https://support.apple.com/guide/iphone/type-with-the-onscreen-keyboard-iph3c50f96e/ios |
| Emoji variants | Touch and hold → drag to variation | D | https://support.apple.com/guide/iphone/add-emoji-memoji-and-stickers-iph69df21ec5/ios |
| Dictation | Keyboard stays open; auto-punctuation; 30 s silence stop | D | https://support.apple.com/guide/iphone/dictate-text-iph2c0651d2/ios |
| Magnifier | Removed iOS 13, back iOS 15 (touch-hold-drag) | D / O | https://9to5mac.com/2021/06/07/ios-15-brings-back-the-magnifying-glass-for-accurate-text-selection/ |
| QuickPath languages | RU added iOS 15; UK unsupported | O | https://discussions.apple.com/thread/253675597 |

## Sources

Apple: User Guide "Type with the onscreen keyboard", iOS 13 and iOS 16 versions https://support.apple.com/guide/iphone/type-with-the-onscreen-keyboard-iph3c50f96e/13.0/ios/13.0 · Add or change keyboards https://support.apple.com/guide/iphone/add-or-change-keyboards-iph73b71eb/ios · Keyboard accessibility https://support.apple.com/guide/iphone/keyboards-ipha7c3927eb/ios · Developer Forums: long-press duration https://developer.apple.com/forums/thread/772660 · return-key colour https://developer.apple.com/forums/thread/133257

Measurements / engineering: KeyboardKit space-drag handler https://github.com/KeyboardKit/KeyboardKit/blob/master/Sources/KeyboardKit/Gestures/Gestures+SpaceDragGestureHandler.swift · KeyboardKit callout style https://github.com/KeyboardKit/KeyboardKit/blob/master/Sources/KeyboardKit/Callouts/Callouts+CalloutStyle.swift · DictateKeyboard #364 (two-axis trackpad) https://github.com/DevEmperor/DictateKeyboard/issues/364 · extratone/iOSSystemSounds (key_press_* files) https://github.com/extratone/iOSSystemSounds · TUNER88/iOSSystemSoundsLibrary (ID 1104) https://github.com/TUNER88/iOSSystemSoundsLibrary · craiggrummitt keyboard height https://craiggrummitt.com/2019/02/22/getting-the-keyboard-height/

Hands-on / UX: iDownloadBlog iOS 12 trackpad https://www.idownloadblog.com/2018/08/22/howto-iphone-keyboard-trackpad-mode/ · Gadget Hacks trackpad https://ios.gadgethacks.com/how-to/turn-your-iphones-keyboard-into-trackpad-for-easier-cursor-placement-0185606/ · Gadget Hacks keyboard facts https://ios.gadgethacks.com/how-to/10-things-everyone-should-know-about-iphones-keyboard-for-better-typing-experience-0385564/ · SlashGear trackpad https://www.slashgear.com/1373316/turn-iphone-keyboard-into-trackpad/ · PhoneArena iOS 12 trackpad https://www.phonearena.com/news/Apple-devices-without-3D-Touch-can-now-use-trackpad-mode-to-precisely-place-a-cursor-for-editing_id109191 · MacRumors iOS 26 Liquid Glass https://www.macrumors.com/guide/ios-26-liquid-glass/ · KnowTechie haptics https://knowtechie.com/how-to-use-the-iphones-haptic-keyboard/ · Apple Community: UK ї https://discussions.apple.com/thread/255690493 · UK apostrophe https://discussions.apple.com/thread/254009343 · globe vs emoji https://discussions.apple.com/thread/251476851 · iOS 13.1 emoji key https://discussions.apple.com/thread/250648336 · Plus landscape keys removed https://discussions.apple.com/thread/8076810 · Silent switch mutes clicks https://discussions.apple.com/thread/255952747 · Elon.io UK layout https://elon.io/grammar/ukrainian/writing-system/typing-ukrainian · Michael Tsai iOS 13 cursor https://mjtsai.com/blog/2020/02/10/ios-13-cursor-placement-and-text-selection/ · Gadget Hacks iOS 13 text editing https://ios.gadgethacks.com/how-to/ios-13-changes-way-you-navigate-edit-text-heres-place-cursor-make-selections-perform-edits-more-0203292/ · 9to5Mac iOS 14 emoji search https://9to5mac.com/2020/10/26/how-to-use-iphone-emoji-search-ios-14/ · TapSmart autocorrect https://www.tapsmart.com/tips-and-tricks/ios17-autocorrect-tips/ · Nutrient Smart Punctuation https://www.nutrient.io/blog/ios-11-smart-punctuation/ · HowToGeek one-handed https://www.howtogeek.com/327447/how-to-use-the-one-handed-keyboard-on-your-iphone/ · Cult of Mac Haptic Touch speed https://www.cultofmac.com/how-to/haptic-touch · O'Reilly iPhone: The Missing Manual (backspace speeds) https://www.oreilly.com/library/view/iphone-the-missing/9780596521677/ch01s11.html
