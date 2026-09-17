# Skald — macOS pop-up translator

Owner: Ivan (ivshestakov@gmail.com).
Started: 2026-04-23 (as "Translator", renamed to Skald 2026-04-24).

## What it is

Menu-bar utility. Press a global hotkey (default ⌥/) → glass input
panel slides up at the bottom of the screen → user types a phrase →
Enter → translation pasted at the original cursor via simulated ⌘V.

Five engines: **Apple** (on-device, offline), **Google** (free,
unofficial), **DeepL** (API key), **Claude** (API key, supports tone
adaptation). 13 languages with on-device source detection.

See `README.md` for the user-facing description and `RELEASE.md` for
the per-release procedure (notarize, sign, appcast).

## Code structure

Product page + appcast feed live in a **separate repo**
([ivshestakov/panic-kit](https://github.com/ivshestakov/panic-kit),
deployed via Vercel to `panic-kit.com`):

```
panic-kit/skald/
├── index.html            — product landing in parent-site style
├── support.html          — install, accessibility, troubleshooting
├── privacy.html          — what stays on device, what leaves it
└── appcast.xml           — Sparkle update feed (one <item> per release)
```

Skald's own repo holds source + release tooling:

```
TranslatorApp/
├── Info.plist            — bundle metadata + Sparkle keys (SUFeedURL/SUPublicEDKey)
├── Skald.entitlements    — disables library-validation so Sparkle.framework loads
├── build.sh              — swiftc + manual bundle, embeds Sparkle, signs (dev or Dev ID)
├── release.sh            — full release pipeline: build → notarize → DMG → notarize DMG → Sparkle sign
├── make-icon.sh          — sips/iconutil pipeline: PNG → multi-resolution .icns
├── icon-source.png       — 1024×1024 master icon
├── Resources/Skald.icns  — generated, copied into bundle
├── Frameworks/
│   ├── Sparkle.framework — embedded auto-update framework (3 MB)
│   └── Sparkle-bin/      — Sparkle CLI tools used by release.sh only
│                           (generate_keys, sign_update, generate_appcast, BinaryDelta)
└── Sources/
    ├── main.swift
    ├── AppDelegate.swift          — status-bar menu, hotkey registration, About panel,
    │                                login items, Sparkle bootstrap
    ├── HotKey.swift                — Carbon RegisterEventHotKey wrapper
    ├── SkaldPanel.swift            — the glass input panel (NSPanel + NSVisualEffectView,
    │                                 tone-tinted gradient overlay, tone pill, offline toggle,
    │                                 spinner, paste logic)
    ├── ToneSlider.swift            — gradient slider with tick labels (Corporate → Vulgar)
    ├── ShortcutRecorderView.swift  — click-to-record hotkey picker
    ├── KeyCapView.swift            — keycap rendering (used in shortcut recorder)
    ├── SidebarItemView.swift       — selectable sidebar row + CardView container
    ├── SettingsWindowController.swift — sidebar nav, frosted-glass window,
    │                                    cards, four sections (Languages/Model/Style/Shortcuts)
    ├── Translator.swift            — engine router + Google/DeepL/Claude HTTP impls
    ├── AppleTranslator.swift       — SwiftUI TranslationSession bridge (macOS 15+)
    ├── Settings.swift              — UserDefaults + Keychain wrapper, Tone/Engine/Language enums
    ├── NetworkMonitor.swift        — NWPathMonitor wrapper for auto-offline switching
    ├── LoginItem.swift             — SMAppService.mainApp wrapper for "Launch at Login"
    └── Updater.swift               — Sparkle SPUStandardUpdaterController wrapper
```

## iOS keyboard (SkaldMobile/) — added 2026-09-15

Ivan wants a mobile version as a **translating keyboard**. It lives in
`SkaldMobile/` (xcodegen project, `project.yml` is the source of truth;
`Skald.xcodeproj` and `build/` are git-ignored). See
`SkaldMobile/README.md` for structure, build steps and known gaps.

- App `com.ivshestakov.skald.ios` + extension `.ios.keyboard`, App Group
  `group.com.ivshestakov.skald`, min iOS 18, automatic signing, team
  `975ZZPJQNB`.
- `Shared/` is a platform-neutral copy of the Mac app's Language / Engine
  / Tone / Settings / Translator code (async). Claude prompt and tone
  directives are duplicated — change both when editing one.
- Status (2026-09-16): MVP verified in the iPhone 17 Pro simulator —
  typing, RU/UK/EN layouts + language key, long-press alternates, emoji
  panel, Translate *mode* (composer + live preview, Return inserts), Undo,
  light/dark styling matched to the system keyboard (iOS 26.4 sim + iOS 27
  photos), double-space period, punctuation→letters, key pop-up, haptics,
  frequency-dictionary + bigram autocorrect, next-word prediction,
  tap-on-word suggestions, UIKit multi-touch layer with glide and space
  trackpad, host-field traits (see SkaldMobile/README.md).
  TestFlight: app "Skald Translator" (6812791271), upload via
  `SkaldMobile/release-ios.sh` (manual signing + altool).
- **Parity with the system keyboard is the north star.** The audit
  `SkaldMobile/docs/native-parity.html` (+ `docs/research/*.md`, 2026-09-17)
  compares native iOS behaviour with Skald item by item, lists what an
  extension can never do, and holds the prioritised P0–P3 plan. Consult it
  before changing keyboard behaviour. Not yet run on a device; Apple on-device engine unverified
  inside the extension. Ivan's goal: keep only the English system keyboard
  and let Skald replace the RU/UK ones, so it must look identical to iOS 27.

## Codesigning identity

The build.sh signs with a stable self-signed cert in the user's login
keychain named **"Translator Dev (self-signed)"**. The cert was created
locally on 2026-04-24 (via `openssl req` + `security add-trusted-cert`).
Keeping the identity stable across rebuilds means TCC (Accessibility)
grants persist — re-grant happens only when bundle ID changes.

For production, override via env var:
```
SKALD_SIGN_IDENTITY="Developer ID Application: …" ./build.sh
```

## Keychain ACL — temporary wide-open for dev

Self-signed builds get a new cdhash on every recompile, and the default
Keychain ACL records cdhash, not certificate. So under default rules the
user gets a "Skald wants to access key …" prompt every rebuild.

Workaround in `Settings.swift` → `Keychain.save()`: pass a `SecAccess`
created with `nil` trusted-app list, which Apple's old SecKeychain
headers document as "grants access to all callers". Side effect: any
other tool running as the same user can read the API keys.

Acceptable for the dev/self-signed phase because the keys are the
user's own API credentials on their own machine. **Once we switch to
Developer ID for production, remove the wide-open SecAccess** —
team-id-anchored DRs match across rebuilds with the default ACL, no
prompts and no over-broad access. The code comment in `Keychain.save`
flags this explicitly.

Service name was bumped from `com.ivshestakov.skald` →
`com.ivshestakov.skald.v2` to migrate cleanly: old strict-ACL entries
become orphaned and the user re-enters keys once.

## Status (2026-07-08)

**Currently published: 0.4.0** —
<https://github.com/ivshestakov/skald.app/releases/tag/v0.4.0>

Version history:
- **0.4.0** (2026-06-04): multi-line input (panel grows upward, capped
  ~360pt), input history recall via Up/Down arrows (last 10 phrases,
  persisted), reliable outside-click dismissal
  (`windowDidResignKey` instead of global mouse-down monitor).
- **0.3.0** (2026-06-01): first signed + notarized public release —
  Developer ID (Team `975ZZPJQNB`), distribution switched zip → DMG,
  Sparkle auto-updates live via `panic-kit.com/skald/appcast.xml`,
  product page at `panic-kit.com/skald`. Old self-signed zip releases
  0.1.0–0.2.2 were deleted from GitHub on 2026-07-08 (they were never
  notarized).
- **0.2.2** (2026-05-13): paste, dictation, settings gear.
- **0.2.1** (2026-05-05): hardened Claude prompt.
- **0.2.0** (2026-04-27): `⌥`` quick-translate hotkey.
- **0.1.0** (2026-04-25): first public release.

✅ Done for publication:
- Renamed to Skald (bundle ID `com.ivshestakov.skald`)
- Min macOS 15.0
- App icon `.icns` generated and embedded
- LICENSE (MIT) + README.md + INSTALL.md + RELEASE.md
- About Skald, Launch at Login, Check for Updates… in menu
- Sparkle 2.9.1 framework embedded; CLI tools at
  `TranslatorApp/Frameworks/Sparkle-bin/` for release pipeline
- Library-validation entitlement so Sparkle loads under hardened runtime
- Two customisable hotkeys (panel + quick-translate)
- Universal binary (arm64 + x86_64)
- **Release pipeline** (`release.sh`): build → sign with Dev ID →
  notarize → staple → DMG → sign DMG → notarize DMG → staple DMG →
  Sparkle sign. Prints ready-to-paste `<item>` for appcast.
- Sparkle EdDSA public key in Info.plist (`SUPublicEDKey`); private key
  in login keychain under `https://sparkle-project.org`.
- Product page + appcast hosted on `panic-kit.com/skald` (Vercel-served
  from the [ivshestakov/panic-kit](https://github.com/ivshestakov/panic-kit)
  repo at `/skald/`). `SUFeedURL` in Info.plist points there.

✅ Done as of 0.3.0 (2026-06-01) — release infrastructure is live:
- Developer ID Application cert installed (`Ivan Shestakov (975ZZPJQNB)`)
- notarytool keychain profile `skald-notarize` (Intune MDM occasionally
  wipes it — recreate via `xcrun notarytool store-credentials` if
  release.sh fails with "No Keychain password item found")
- panic-kit.com serves the product page + appcast
- Every release: run `./release.sh`, `gh release create` with both DMGs
  (`Skald-X.Y.Z.dmg` + stable-alias `Skald.dmg`), paste `<item>` into
  panic-kit's `skald/appcast.xml`. See RELEASE.md.

⏳ Still pending: move the Sparkle private-key backup
(`skald-sparkle-private.key`) into 1Password and delete it from disk.
Losing the key strands every install from future auto-updates.

See `RELEASE.md` for the per-release procedure and `LAUNCH.md`
Phase 0 for the launch-day checklist.

## Decisions on file

- License: MIT
- Distribution: GitHub Releases (signed + notarized .dmg), no App Store
- **Homebrew: every release must be installable via
  `brew install --cask skald`** — bump `version` + `sha256` in
  [ivshestakov/homebrew-tap](https://github.com/ivshestakov/homebrew-tap)
  `Casks/skald.rb` as part of the release procedure (RELEASE.md §5)
- Localization: English only
- Min macOS: 15.0 (Sequoia)
- Auto-update: Sparkle 2.9.1, EdDSA-signed, appcast served from
  `panic-kit.com/skald/appcast.xml` (Vercel; source in panic-kit repo)

## Pre-release polish list (nice-to-have, not blocking)

- Test all four engines end-to-end with real keys before tagging 0.1.0
- Test offline auto-switch by disabling Wi-Fi and confirming Apple
  engine kicks in transparently
- Try every tone (Corporate / Simple / Original / Youth / Vulgar) on
  the same phrase via Claude to confirm the prompt directives produce
  meaningfully different output
- Test on a clean second user account so first-launch Accessibility
  prompt + model download flows are smooth
- Consider adding a brief onboarding popover on very first launch
  (after Accessibility grant) explaining the hotkey and Settings location
