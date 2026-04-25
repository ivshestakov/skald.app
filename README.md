# Skald

A small macOS menu-bar utility that translates short phrases on the fly. Hit
the global hotkey, type a phrase in any language, press Enter — the
translation is pasted right where your cursor was.

Skald lives in the menu bar (`character.bubble` icon), takes ~30 MB of RAM,
and never touches your text unless you explicitly trigger a translation.

## Features

- **Five translation engines**, switchable per-session:
  - **Apple** — on-device, offline, free. macOS 15+ only.
  - **Google** — free, no key required (unofficial endpoint, can rate-limit).
  - **DeepL** — best-in-class quality on European languages. Free tier 500 000 characters/month.
  - **Claude (Anthropic)** — LLM-based, handles tone / slang / technical jargon. Pay-as-you-go.
- **Auto offline mode**: when the network drops, Skald automatically routes
  through Apple's on-device translator and switches back when connectivity
  returns. A toggle in the input panel lets you force offline manually.
- **Tone control** (Claude only): five-stop slider from Corporate to Vulgar.
  Style adaptation is opt-in and clearly labelled with its token cost.
- **13 supported languages**: English, Russian, Ukrainian, German, French,
  Spanish, Italian, Portuguese, Polish, Dutch, Chinese, Japanese, Korean.
  Source language is auto-detected via Apple's on-device Natural Language
  framework.
- **Customisable hotkey**: defaults to ⌥/, change to anything in Settings.
- **API keys are stored in the macOS Keychain**, not in plain text.

## Install

Skald requires macOS 15 (Sequoia) or newer.

### From a release (recommended)

Download the latest `Skald-<version>.zip` from the
[Releases page](https://github.com/ivshestakov/skald.app/releases/latest),
unzip, and drag `Skald.app` into `/Applications`.

The first time you launch, macOS Gatekeeper will warn that the app is from
an unidentified developer (Skald is currently distributed under a
self-signed certificate; an Apple Developer ID is on the roadmap).
**Right-click** `Skald.app` → **Open** → **Open** to confirm — only
required once.

For the full first-run walkthrough (Accessibility grant, API keys),
see [INSTALL.md](INSTALL.md).

### Build from source

You only need Xcode Command Line Tools (no full Xcode required).

```bash
git clone https://github.com/ivshestakov/skald.app.git
cd skald.app/TranslatorApp
./build.sh
cp -R Skald.app /Applications/
open -a Skald
```

The build script signs with an ad-hoc identity by default. For a stable
development experience (so macOS doesn't reset Accessibility permission on
every rebuild), see "Stable dev signing" below.

## First-run setup

1. Launch Skald — the menu-bar icon (a speech bubble) appears.
2. Press the hotkey (default `⌥/`). The input panel appears at the bottom
   of the screen.
3. The first time you trigger a translation, macOS asks for **Accessibility**
   permission so Skald can paste the result via ⌘V. Grant it in
   **System Settings → Privacy & Security → Accessibility**.
4. Open Settings (menu-bar icon → Settings… or `⌘,`) to configure your
   languages, translation engine, and API keys.

## API keys

| Engine | Where to get a key | Cost |
| --- | --- | --- |
| Apple  | No key — system handles it. First use of a new pair downloads ~50–100 MB. | Free |
| Google | No key — unofficial public endpoint. | Free |
| DeepL  | <https://www.deepl.com/pro-api> → "Sign up for free" → Account → Authentication Key for DeepL API | 500 000 chars/mo free, then €5.49/mo + €20/M |
| Claude | <https://console.anthropic.com> → API Keys → Create Key | Pay-as-you-go (~$0.0001 per phrase on Haiku 4.5) |

DeepL free-tier keys end in `:fx`; Skald detects this and routes to
`api-free.deepl.com` automatically.

## Privacy

- **Apple** translation runs on-device. Your text never leaves your Mac.
- **Google / DeepL / Claude** require sending your phrase to the
  respective provider's servers over HTTPS. Skald does not store or log
  your inputs anywhere.
- Source-language detection uses Apple's on-device Natural Language
  framework — also offline.
- API keys live in the macOS Keychain (`com.ivshestakov.skald.v2` service).

Skald has no analytics, no telemetry, no crash reporting beyond the
default macOS crash reports.

## Stable dev signing (optional)

By default `build.sh` signs the app with an ad-hoc signature. Each rebuild
gets a fresh code-hash and macOS treats it as a "new app" — meaning you
have to re-grant Accessibility every time.

To avoid that during active development, create a self-signed code-signing
certificate, trust it locally, and reference it from `build.sh`. The
script already looks for an identity called
`Translator Dev (self-signed)` and falls back to ad-hoc if it isn't there.

```bash
DIR=/tmp/skald-sign && mkdir -p "$DIR" && cd "$DIR"

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -keyout key.pem -out cert.pem \
  -subj "/CN=Translator Dev (self-signed)" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=CA:false"

security import cert.pem -k ~/Library/Keychains/login.keychain-db
security import key.pem  -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db cert.pem   # requires password
```

After this, `build.sh` will sign with the stable identity and Accessibility
permission persists across rebuilds.

## License

MIT — see [LICENSE](LICENSE).

## Credits

- Old Norse for "poet" or "bard" — the skald rendered one tongue into
  another at court.
- Built without Xcode, with a lot of `swiftc` and stubborn AppKit.
