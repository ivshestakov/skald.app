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
TranslatorApp/
├── Info.plist            — bundle metadata + Sparkle keys (SUFeedURL/SUPublicEDKey)
├── Skald.entitlements    — disables library-validation so Sparkle.framework loads
├── build.sh              — swiftc + manual bundle, embeds Sparkle, signs with stable cert
├── make-icon.sh          — sips/iconutil pipeline: PNG → multi-resolution .icns
├── icon-source.png       — 1024×1024 master icon
├── Resources/Skald.icns  — generated, copied into bundle
├── Frameworks/Sparkle.framework  — embedded auto-update framework (3 MB)
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

## Status (2026-04-25)

✅ Done for publication:
- Renamed to Skald (bundle ID `com.ivshestakov.skald`)
- Min macOS bumped to 15.0 (Apple translation requires it)
- App icon `.icns` generated and embedded
- Hammerspoon legacy deleted
- LICENSE (MIT) + README.md + RELEASE.md
- .gitignore added
- About Skald, Launch at Login, Check for Updates… in menu
- Sparkle 2.9.1 framework embedded and code-signed correctly
- Library-validation entitlement so Sparkle loads under hardened runtime

⏳ Pending — must be done before public release:

1. **Apple Developer ID** ($99/year). Until then users see a Gatekeeper
   warning on first open and must right-click → Open. Set
   `SKALD_SIGN_IDENTITY` and re-build/notarize per RELEASE.md.

2. **Sparkle keys & feed URL.** Currently `SUFeedURL` is a placeholder
   (`https://example.com/skald/appcast.xml`) and `SUPublicEDKey` is empty.
   Before shipping:
   - Generate EdDSA keys: `Frameworks/Sparkle.framework/Versions/Current/../../bin/generate_keys`
   - Paste public key into `Info.plist` → `SUPublicEDKey`
   - Set up GitHub Pages branch hosting `appcast.xml`
   - Update `SUFeedURL` to the real Pages URL

3. **Bump version** in Info.plist before each release
   (`CFBundleShortVersionString` and `CFBundleVersion`).

4. **GitHub repo + Pages** for hosting releases and appcast.

## Decisions on file

- License: MIT
- Distribution: GitHub Releases (.zip), no App Store
- Localization: English only
- Min macOS: 15.0 (Sequoia)
- Auto-update: Sparkle (manual builds for now, formal first release later)

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
