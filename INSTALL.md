# Installing Skald

## Requirements

- macOS 15 (Sequoia) or newer
- ~10 MB of disk space
- Optional: API keys for DeepL or Claude (Apple and Google work without)

## First-time install

1. **Download** `Skald-<version>.zip` from the
   [Releases page](https://github.com/ivshestakov/skald.app/releases).
2. **Unzip** — you'll get `Skald.app`.
3. **Drag** `Skald.app` into `/Applications`.
4. **First launch**: macOS will refuse to open with a message like
   *"Skald can't be opened because Apple cannot check it for malicious
   software"*. This is because Skald is currently distributed under a
   self-signed certificate (a real Apple Developer ID is on the
   roadmap). To bypass:
   - **Right-click** `Skald.app` → **Open** → **Open** in the dialog.
   - You only have to do this once.
5. The Skald icon (a speech bubble) appears in the menu bar at the top
   of the screen.
6. **Press the hotkey** (default `⌥/`). The first time, macOS will ask
   for **Accessibility** permission so Skald can paste the translation
   into other apps. Open *System Settings → Privacy & Security →
   Accessibility*, find Skald, switch the toggle on.
7. **Test it**: press `⌥/` again, type "hello", press Enter. You should
   see "привет" appear at your cursor.

## API keys

By default Skald uses Apple's on-device translation engine. The first
translation between any new language pair downloads a ~50 MB model
(once, then offline forever).

For higher quality on idioms, slang, or technical text, configure
Claude or DeepL via the menu-bar icon → **Settings… → Model**:

| Engine | Where to get a key | Cost |
| --- | --- | --- |
| Apple  | No key — built in. | Free |
| Google | No key — public endpoint. | Free, can rate-limit |
| DeepL  | [deepl.com/pro-api](https://www.deepl.com/pro-api) → Sign up for free | 500 000 chars/mo free |
| Claude | [console.anthropic.com](https://console.anthropic.com) → API Keys | ~$0.0001 per phrase on Haiku 4.5 |

Keys are stored in the macOS Keychain (`com.ivshestakov.skald.v2`
service) and are never sent anywhere except the engine you've selected.

## Customising the hotkey

Settings… → **Shortcuts** → click the box, press the new combination
(must include at least one modifier — `⌘ ⌥ ⌃ ⇧`).

## Auto-launch

Menu-bar icon → **Launch at Login** (toggle).

## Uninstall

1. Quit Skald (menu-bar → Quit Skald).
2. Drag `/Applications/Skald.app` to the Trash.
3. Optional: clear settings via Terminal:
   ```
   defaults delete com.ivshestakov.skald
   security delete-generic-password -s com.ivshestakov.skald.v2
   ```
