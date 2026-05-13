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

```
docs/                     — served via GitHub Pages (Settings → Pages → main /docs)
├── appcast.xml           — Sparkle update feed (one <item> per release)
└── index.html            — minimal lander linking to GitHub releases

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

## Status (2026-05-13)

**Currently published: 0.2.2** —
<https://github.com/ivshestakov/skald.app/releases/tag/v0.2.2>

Version history:
- **0.3.0** (in flight): release infrastructure — `release.sh`
  produces a signed + notarized DMG, Sparkle EdDSA keypair generated,
  `docs/appcast.xml` skeleton on main, GitHub Pages set to serve `docs/`.
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
- `docs/appcast.xml` skeleton + `docs/index.html` on `main`.

⏳ Pending — manual steps before first signed release:

1. **Generate Developer ID Application cert** at developer.apple.com,
   install in login keychain. Dev account is paid; only the cert is
   missing (`security find-identity` shows only "Apple Development",
   which is for Xcode/local builds).

2. **App-specific password + notarytool profile.** Create at
   appleid.apple.com, store via
   `xcrun notarytool store-credentials skald-notarize`.

3. **Enable GitHub Pages → main `/docs`** in repo settings.

4. **Back up the Sparkle private key** offline. Losing it strands
   every existing install from future auto-updates.

5. **Run `./release.sh`**, upload DMG to a GitHub Release, paste
   `<item>` into `docs/appcast.xml`.

See `RELEASE.md` for the per-release procedure and `LAUNCH.md`
Phase 0 for the launch-day checklist.

## Decisions on file

- License: MIT
- Distribution: GitHub Releases (signed + notarized .dmg), no App Store
- Localization: English only
- Min macOS: 15.0 (Sequoia)
- Auto-update: Sparkle 2.9.1, EdDSA-signed, appcast served from
  GitHub Pages at `ivshestakov.github.io/skald.app/appcast.xml`

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
