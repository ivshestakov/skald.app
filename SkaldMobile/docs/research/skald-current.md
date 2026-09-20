# Skald iOS keyboard — current behaviour audit (2026-09-17)

Read-only audit of `SkaldMobile/` (branch `docs/notarized-brew-0.4`, HEAD 263a80b). File keys: **KM** = Keyboard/KeyboardModel.swift, **KT** = Keyboard/KeyTouchView.swift, **KV** = Keyboard/KeyboardView.swift, **KVC** = Keyboard/KeyboardViewController.swift, **AC** = Keyboard/Autocorrect.swift, **KL** = Shared/KeyboardLayouts.swift, **SS** = Shared/SkaldSettings.swift.

## 1. Autocorrect

**Triggers.** Only two paths call `autocorrectCurrentWord` (KM:418): the space key (KM:579, separator `" "`) and a single-character insert from the set `. , ? ! ; :` (KM:344, 352-354). Return (KM:196), emoji (KM:608) and popup alternates (KM:837) never trigger it. Preconditions: `page == .letters` and `!correctionsDisabled` (KM:420); a non-empty word = trailing run of letters/`'`/`’`/`-` before the caret (KM:366-371). In translate mode the same logic runs on the composer string (KM:362-364).

**Order of checks.** (1) Text Replacement lexicon: `lexicon[word.lowercased()]` → synchronous replace with `documentText + separator` (KM:423-428); works with autocorrect off, no case matching. (2) `settings.autocorrectEnabled` (default true, SS:90-93). (3) Background lookup on `DispatchQueue.global(.userInteractive)` (KM:435).

**Refusals in `Autocorrect.correction`** (AC:198-241): word < 3 chars (AC:199); any char outside letters/`'`/`’`/`-` (AC:200); `word == word.uppercased()` — ALL CAPS, incl. 3-letter acronyms (AC:201); word in personal lexicon (AC:203); unknown to the frequency list but accepted by `UITextChecker` (AC:208, 187-192); known and (freq ≥ 300 **or** first letter uppercase **or** < 4 letters) (AC:211). Known-but-rare lowercase words ≥ 4 letters remain candidates for a context fix. A `personalFixes` hit short-circuits to that fix when it is in the dictionary or personal (AC:204-205). No dictionary → nil: only `freq_en/ru/uk` ship, so DE/FR/ES layouts get no correction at all.

**Candidates.** `edits1` (AC:292-321): deletion ×1.0, adjacent transposition ×2.0, substitution ×3.0 if the keys neighbour on the current layout else ×0.7, insertion ×1.0 of any alphabet letter. Alphabet = layout letters ∪ letter alternates from `KeyAlternates` (AC:326-334); the apostrophe is in the alphabet only on the Ukrainian layout (KL:39). Adjacency = same row ±1 plus the two nearest keys in the rows above/below (AC:337-356). `edits2` only when edits1 found nothing, the word is unknown and ≥ 5 letters; the second edit is restricted to neighbouring keys and weighted `w1·w2·0.05` (AC:224-233).

**Scoring.** `p(w|prev) = 0.75·bigram + 0.25·unigram` when prev has ≥ 20 bigram observations, else unigram (AC:68-75). Best candidate must be in the dictionary, differ from the input, and have freq ≥ 30 (AC:235); for a *known* word the fix must score > 40× `p(word|prev)` (AC:238). Case is mirrored via `matchCase` (AC:358-362).

**Async application.** Generation counter: a newer finished word drops any older pending result (KM:431-438); the result is discarded if translate mode flipped, and applied only if `textBeforeCaret.hasSuffix(word + separator)` (KM:447). Application = N× `deleteBackward` + `insertText(fix + separator)` (KM:397-410), records `lastAutocorrect` and a 60-entry replacement→typed history (KM:390-395).

**Revert.** The first `backspaceOnce` after a correction checks the text still ends with `replacement + separator` and restores `original + separator` (separator kept), then `learnWord(original)` (KM:458-468, 617). `lastAutocorrect` is cleared by the next word end, double-space, word delete and suggestion tap (KM:419, 571, 665, 493).

**Learning** (App Group defaults, SS:101-108): `learnWord` (+2, ≥ 2 chars, removes any fix, AC:141-148) on revert, on tapping a quoted word or the pre-correction original; `learnFix(typed, fix)` (AC:151-158) on tapping any other suggestion (KM:487-491); `noteUnknownKept` — an unknown-to-everything word (≥ 3 chars) left uncorrected twice in one process graduates to `personalWords` (AC:161-175, KM:440-442). No pruning.

**Suggestion bar** (`updateSuggestions` KM:500-532; gated by `suggestionsEnabled`, letters page, `!correctionsDisabled`, status idle or translate mode). Up to 3 equal-width 16 pt items; no highlighted "will be applied" item (KV:408-426).
- *Typing*: `"word"` quoted first if unknown to dictionary/personal/system and ≥ 2 chars; then a personal fix; then prefix completions (binary search, ≤ 400 scanned, ×0.3 when > typed+4 letters) and, for unknown words ≥ 3 chars, edits1 fixes ×2, sorted by `p(·|prev)` (AC:254-287).
- *After a space*: the 3 most frequent followers of the previous word (≤ 12 stored per word, AC:59, 245-248; KM:516-517); empty when the previous word is unknown.
- *Caret inside a word*: `alwaysFixes` — edits1 alternatives even for known words (KM:520); if Skald auto-corrected it this session the typed original is inserted first (KM:521-525).
- *Tap*: strips quotes, replaces both halves of the word, appends a space only at word end outside translate mode (KM:472-496).
- No inline/ghost prediction, no capitalisation fixes (`i`→`I` impossible: < 3 chars), no apostrophe insertion on Latin layouts, no smart quotes/dashes.

**Dictionaries/memory.** `freq_en/ru/uk.txt` = 48 639 / 49 741 / 49 798 lines (609 KB / 996 KB / 885 KB); `bigrams_*.bin` = 3.79 / 3.80 / 2.40 MB (`SKBG` header, AC:44-62). Loaded lazily under a lock (AC:87-108), preloaded on init and every layout switch (KM:121, 137, 147, 964); at most two resident (AC:118-121), ~10 MB each (AC:111).

## 2. Touch handling

One `KeyTouchUIView` overlays the SwiftUI keys (`isMultipleTouchEnabled`, KT:52), tracks a `TouchState` per `UITouch` (KT:48), and claims only touches on a key frame, or any touch while one is active (KT:60-63). Hit-test slop: exact frame, else the nearest key within 8 pt (KT:65-77); farther touches are ignored.

**Down vs up.** Touch-down (`keyDown`, KM:212-229): click + haptic for every key; char keys show the preview; **backspace deletes immediately**; 123/ABC/#+= switch page immediately (remembering `pageBeforeGlide`). Everything else acts on release on the key **under the finger** (`keyReleased`, KM:238-266): letters, space, return, globe, emoji. Glide rules: shift→letter = one capital, shift state restored (KM:248-253); 123→char types it and returns to the previous page, but a glide from ABC or #+= stays on the new page (KM:254-257, `start == .numbers` only); shift→shift = normal tap; release on any mode key after starting elsewhere = nothing (KM:260-261). `keyMoved` only updates `pressedKeys` and the preview (KM:232-236) — no click on entering a new key.

**Long press** (KT:91-113): 0.35 s for char/language/space, 0.4 s for backspace, none otherwise; cancelled when the finger leaves the key (backspace excepted), re-armed on returning to the start key (KT:156-166). A char long-press shows alternates only when `KeyAlternates.table` has an entry (KM:802-810); otherwise release simply types the key.

**KeyAlternates table** (KL:96-127): a→à á â ä ã å ą; c→ç ć č; e→è é ê ë ę ė; i→ì í î ï; l→ł; n→ñ ń; o→ò ó ô ö õ ø; s→ß ś š; u→ù ú û ü; y→ÿ; z→ź ż ž; е→ё; ь→ъ; г→ґ; и→і ї; і→ї и; .→…; -→– —; '→‘ ’ « »; "→“ ” „; $→€ £ ¥ ₴ ₽; 0→°; %→‰; =→≠ ≈; /→\; ?→¿; !→¡. Options = base glyph then alternates, uppercased if shift is active on letters (KM:805-806); order never mirrored for right-edge keys.

**Popup geometry** (KV:720-729): option width max(key width, 34); total n·option + 8, clamped 2 pt from screen edges; height rowHeight + 10, sitting 6 pt above the key; 22 pt glyphs, accent highlight, container radius 10 with shadow. Selection tracks **x only** (`floor((x − minX)/optionWidth)`, KM:822-828), default index 0; release commits with click + haptic and drops shift on→off (KM:830-843); `touchesCancelled` cancels (KT:197).

**Key preview** (KV:759-787, KM:778-798): on touch-down for every `.char` key on every page except emoji — including the number pad; width max(1.7×key, 46), height 2.35×key, bottom-aligned with the key, x clamped 2 pt; glyph `letterFont × 1.75` light; radius 9; shadow 0.25 light / 0.6 dark. Follows the finger, lingers 100 ms after release (token-guarded), hidden at once when a popup opens or on cancel.

**Pressed colours** (KV:276-282): char keys never change fill; shift/backspace/123/ABC/#+=/globe/emoji/space → `#C9CBD1` light / `#6B6B6B` dark; tinted return → accent at 0.7 opacity; backspace glyph → `delete.left.fill` (KV:296).

## 3. Backspace

Touch-down deletes once with click + haptic and sets `backspaceCount = 1` (KM:220-221). After 0.4 s (KT:96) a 0.1 s repeating `Timer` starts (KM:635); each tick plays click + haptic, increments, and calls `backspaceOnce` until `count > 14`, then `deleteWordBackward` (KM:639-642) — 13 single deletes, then word deletion from ≈1.8 s after touch-down (README says ~1.5 s). Word deletion = trailing whitespace run + non-whitespace run, min 1 (KM:653-667). Constant cadence, no ramp. Repeat survives sliding off the key (KT:160); stops on release/cancel (KM:242, 272). The first delete may instead revert an autocorrect (§1).

## 4. Shift / caps

Initial `.on`, auto (KM:52, 109). Tap toggles off↔on; a second tap within **0.3 s** → caps (KM:179-187); any tap sets `shiftIsAuto = false`. `.on` drops to `.off` after one inserted character (KM:350) or a popup commit (KM:838); `.caps` persists. `updateAutoShift` (KM:735-767) runs on the letters page when not caps, after every local edit (KM:603-606) and on host `textDidChange`/`selectionDidChange` unless the context is empty within 0.5 s of our own edit (KM:727-729). By `autocapitalizationType` (default `.sentences`): `.none` → only turns an auto shift off; `.allCharacters` → shift on whenever off; `.words` → on after empty/whitespace/newline; `.sentences` → on when text is empty/blank, or when the last char is whitespace/newline **and** the last non-blank char is `.`, `!` or `?` (KM:752-761). So after Return with no terminal punctuation there is no auto-capital. Auto-shift re-arms whenever `shift == .off` at a sentence start, even after a manual shift-off (KM:762). In translate mode the composer is auto-shifted with the host's trait (KM:721). Visuals: SF `shift` / `shift.fill` / `capslock.fill` 18 pt (KV:293), key fill unchanged; keycaps switch case (KV:290).

## 5. Space

**Double-space** (KM:546-573): no time window — `quick` is true whenever the previous key was also space with nothing inserted between (`lastSpaceTap`, KM:353, 494, 569); requires text ending in exactly one space preceded by a letter, digit, `)`, `"` or `'`; then `deleteBackward` + `". "`. Not gated on field type.
**Punctuation → letters**: space after a single `. , ? ! ; :` typed on 123/#+= jumps to letters (KM:574-576).
**Swipe to switch layout** (KT:145-152): |dx| > 36 pt with |dy| < 30 pt from touch-down, before the long-press fires; left = next, right = previous (KM:141-149); one switch per touch, haptic, > 1 layout required.
**Trackpad** (KT:95, KM:286-342): long-press 0.35 s, haptic, not in translate mode; key fills unchanged, letter and space labels go transparent (KV:259). Per move: vertical dominance `|dy| > 1.5·|dx|` → accumulate Y and zero X, else accumulate X and halve Y (KT:127-133); 8 pt/character, 28 pt/line (KT:134); one line step per event; `charsPerLine` 38 portrait / 80 landscape (KM:301) emulates soft wraps together with real `\n` (KM:305-337). No selection, no acceleration. Release → `endCursorMode` → `textDidChange`.
**Label**: language code (`ру`, `ук`, else rawValue) 10 pt, plus `‹ ›` 11 pt semibold at 0.45 opacity when > 1 layout (KV:297-315).

## 6. Feedback

Click: `UIInputView` subclass with `enableInputClicksWhenVisible = true` (KVC:6-8, 23) and `UIDevice.current.playInputClick()` (KVC:113-115) — one sound for every key kind. Haptic: `UIImpactFeedbackGenerator(style: .light)`, `impactOccurred(intensity: 0.8)`, re-`prepare()` (KVC:119-129); only with Full Access and `hapticsEnabled` (default true, SS:85-88). Both fire on every touch-down (KM:213-214), each backspace-repeat tick, popup commit, suggestion tap, emoji insert; haptic alone on layout swipe and trackpad start; click alone on most top-bar buttons. Nothing on glide-enter, popup selection change or cursor steps.

## 7. Layout / metrics

`KeyboardMetrics` (KV:18-23): portrait gap 7, rowGap 12, rowHeight 42, side 6, topBar 44, topPadding 5, composer 56, radius 7, bottom 4, smallKey 43.5, letterFont 23 → keys 204 pt, total 257 pt. Landscape (width > height && > 500, KV:26): gap 9, rowGap 7, rowHeight 33, side 4, topBar 38, topPadding 3, composer 44, radius 6, bottom 3, smallKey 60, letterFont 20 → 153 / 197 pt. Height constraint priority 999 (KVC:64); translate mode does not change height (KVC:17).
Widths: unit = (W − 7·(n−1))/n for the widest row; shift/backspace min 1.25·unit when n ≤ 10 else 1.0·unit (KV:133-148). Bottom row (KV:157-178): 123/ABC 43.5 · emoji 43.5 · globe 43.5 (only if `needsInputModeSwitchKey`) · [extra 34.8] · space · [extra 34.8] · return 94. Layouts: Latin 10/9/7, RU 11/11/9, UK 12/12/10 (`'` and `ґ`), DE 11/11/7, FR 10/10/6, ES 10/10/7 (KL:26-56).
Palette (KV:219-234): bg `#DFE0E6`/`#212121`, key `#FFFFFF`/`#454545`, pressed `#C9CBD1`/`#6B6B6B`, text black/white, secondary `#6B6C72`/`#A3A3A3`, no key shadow. Return: SF `return` 18 pt for default; text 16 pt for send/search/go/done/next/join/continue (KM:151-162, KV:316-321); accent fill + white label when type ∈ {go, search, send, done, join, route, emergencyCall, continue} and (`!enablesReturnKeyAutomatically` or document has text) (KM:701-704).
Number/symbol pages mirror the system rows (KL:80-89); the third row `. , ? ! '` is flanked by #+=/123 and ⌫. Number pad (KV:182-214): 3 columns of (W−14)/3, rows 123/456/789/[`.` decimal | `+` phone | blank] 0 ⌫; `numberPad`/`asciiCapableNumberPad` → plain, `decimalPad` → decimal, `phonePad` → phone, `namePhonePad` → plain letters (KM:681-686); no letters under digits, no `* #`. Extras (KM:691-698): email `@ .`, URL/webSearch `. /`, twitter `@ #`; letters page only. Globe: tap → `advanceToNextInputMode`, no long-press list (KT:97). Emoji panel (KV:649-706): 8-column grid, 30 pt glyphs in 38 pt cells, ABC and ⌫ keys 48×36 flanking category tabs (Recent ≤ 32, SS:110; 9 categories, 1 898 emoji); no search, no skin tones.

## 8. Translate UI

Top bar (KV:346-449) idle: suggestions | spinner | "Translated ✓" | orange error (tap dismisses); then Undo (when `undo != nil`), "Translate" chip, settings button (tone icon with Claude, else `slider.horizontal.3`). Translate mode: `×` | field (composer, head-truncated, accent caret and border, swipe ≥ 25 pt recalls the last 5 sent texts) | `↑` 44×34 accent (disabled while busy); no live preview (KM:983-987). Settings panel (replaces the keys): Layouts, Translate to, Engine + key Paste/Clear, Style slider, Done. Translate mode exits after an insert (KM:1031).

## 9. Host traits

Read on every `textDidChange`, `selectionDidChange`, `viewWillAppear` and own edit (KM:678-705, KVC:68-98): `keyboardType` (numberPad, asciiCapableNumberPad, decimalPad, phonePad, namePhonePad, emailAddress, URL, webSearch, twitter), `isSecureTextEntry`, `autocorrectionType == .no`, `returnKeyType`, `enablesReturnKeyAutomatically`, `autocapitalizationType` (KM:737), `keyboardAppearance` → `overrideUserInterfaceStyle` (KVC:100-107), `selectedText`. `correctionsDisabled` (secure / autocorrection off / email / URL) turns off autocorrect, lexicon and the bar (KM:699-700); `webSearch`/`twitter` keep them. Ignored: `smartQuotesType`, `smartDashesType`, `smartInsertDeleteType`, `spellCheckingType`, `textContentType`, `inlinePredictionType`, `.asciiCapable`, `.numbersAndPunctuation`, `.alphabet`. Lexicon: `requestSupplementaryLexicon` once at `viewDidLoad`, keyed by lowercased `userInput` (KVC:42-46) — shortcuts added while the extension process lives are not seen; replacement inserted verbatim, never offered in the bar.

## 10. Known gaps noticed

1. No apostrophe/contraction repair on Latin layouts (`'` absent from the edit alphabet), no `i`→`I`, no smart quotes/dashes, no capital fix of already-typed text.
2. No inline prediction; the bar never marks which candidate space will apply; fast typing drops pending corrections (generation guard); Return never triggers autocorrect.
3. No autocorrect/suggestions for DE/FR/ES (no dictionaries); personal words never pruned.
4. No auto-capital after Return unless the line ended in `.!?`; auto-shift silently re-arms after a manual shift-off at sentence start.
5. Glide from ABC/#+= does not return to the previous page (only from 123); popup order not mirrored at screen edges; one key preview at a time; previews also on the number pad.
6. Backspace: fixed 0.1 s cadence, no ramp; word mode after ≈1.8 s.
7. Space trackpad: no selection, no acceleration, wrap estimate 38/80 chars, unavailable in the translate composer.
8. One click sound for all keys (system has letter/modifier/delete variants).
9. Number pad lacks phone letters and `+*#` toggle; `namePhonePad` has no digits toggle; no `.com` key; `.numbersAndPunctuation` does not open the 123 page.
10. No slide-to-type, dictation key, one-handed mode, globe long-press picker, emoji search/skin tones.
11. Lexicon fetched once, replacement inserted verbatim; double-space not disabled in email/URL fields.

## Parameter table

| Parameter | Skald value | file:line |
|---|---|---|
| Autocorrect separators | space, `. , ? ! ; :` | KM:344, 354, 579 |
| Min word length (correct / consider unknown) | 3 / 3 | AC:199, 173 |
| ALL-CAPS skip | `word == word.uppercased()` | AC:201 |
| Known-word skip | freq ≥ 300, or capitalised, or < 4 letters | AC:211 |
| Edit weights del/transp/sub-near/sub-far/ins | 1.0 / 2.0 / 3.0 / 0.7 / 1.0 | AC:300-317 |
| edits2 conditions & weight | unknown, ≥ 5 letters, narrow, ×0.05 | AC:224-230 |
| Bigram interpolation | 0.75·bi + 0.25·uni, prev total ≥ 20 | AC:70-74 |
| Min candidate frequency | 30 | AC:235 |
| Override known word | score > 40× | AC:238 |
| Followers stored / shown | 12 / 3 | AC:59, 245 |
| Prefix scan cap / long-completion penalty | 400 / ×0.3 beyond +4 letters | AC:269-271 |
| Suggestion bar items | 3 | AC:255, KM:524 |
| learnWord increment / min length | +2 / 2 chars | AC:143-144 |
| Unknown-kept graduation | 2 occurrences | AC:164 |
| Dictionary lines en/ru/uk | 48 639 / 49 741 / 49 798 | Keyboard/Resources |
| Resident dictionaries | ≤ 2 (~10 MB each) | AC:111, 119 |
| Hit-test slop | 8 pt | KT:74 |
| Long-press char/space/language | 0.35 s | KT:95 |
| Long-press backspace | 0.4 s | KT:96 |
| Backspace repeat / word mode | 0.1 s / count > 14 | KM:635, 642 |
| Preview linger | 0.1 s | KM:792 |
| Preview size | max(1.7×w, 46) × 2.35×h; glyph 1.75×letterFont light | KV:767-778 |
| Popup option width / height / gap | max(w, 34) / h+10 / 6 above key | KV:721-727 |
| Shift double-tap window | 0.3 s | KM:181 |
| Suspicious-empty guard | 0.5 s | KM:728 |
| Double-space window | none (consecutive presses) | KM:550 |
| Space swipe | dx > 36 pt, dy < 30 pt | KT:148 |
| Trackpad step / line / dominance | 8 pt / 28 pt / 1.5× | KT:127-134 |
| charsPerLine | 38 portrait / 80 landscape | KM:301 |
| Haptic | `.light`, intensity 0.8, Full Access only | KVC:120-127 |
| Portrait metrics | gap 7, rowGap 12, key 42, side 6, bar 44, radius 7, small 43.5, font 23 | KV:18-20 |
| Landscape metrics | gap 9, rowGap 7, key 33, side 4, bar 38, radius 6, small 60, font 20 | KV:21-23 |
| Palette light / dark | bg #DFE0E6 / #212121, key #FFFFFF / #454545, pressed #C9CBD1 / #6B6B6B | KV:220-231 |
