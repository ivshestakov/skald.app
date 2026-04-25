# Releasing Skald

This document covers what's needed to publish a new version of Skald —
producing a downloadable build, hosting an appcast for Sparkle, and
shipping the update to existing users.

## One-time setup

### 1. Generate Sparkle update-signing keys

```bash
cd TranslatorApp
./Frameworks/Sparkle.framework/Versions/Current/Resources/../../../bin/generate_keys
```

This prints a base64 EdDSA public key and writes the matching private key
into your login keychain. **Save the public key into Info.plist's
`SUPublicEDKey` value.** The private key never leaves your machine —
losing it means you have to re-distribute a fresh public key (and any
old client install can't verify your future updates).

### 2. Pick where to host the appcast

Skald assumes `SUFeedURL` is reachable over HTTPS. The simplest path is
GitHub Pages on your `skald` repo:

1. Create a `gh-pages` branch (or set Pages to serve from `/docs`).
2. Pages URL becomes `https://<user>.github.io/skald/`.
3. Set `SUFeedURL` in `Info.plist` to
   `https://<user>.github.io/skald/appcast.xml`.

### 3. Get an Apple Developer ID (for non-scary distribution)

Without a Developer ID, users see a Gatekeeper warning the first time
they open the app. To eliminate that:

1. Enrol at <https://developer.apple.com/programs/> ($99/year).
2. Download the "Developer ID Application" certificate into the keychain.
3. `security find-identity -v -p codesigning` — confirm the identity
   shows up.
4. Use it via env var:
   `SKALD_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh`
5. Notarise the build (see §"Per-release", below).

## Per-release

### 1. Bump version

In `TranslatorApp/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>0.2.0</string>     <!-- semantic version -->
<key>CFBundleVersion</key>
<string>2</string>          <!-- monotonic build number -->
```

### 2. Build & sign

```bash
cd TranslatorApp
SKALD_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

### 3. Notarise

```bash
ditto -c -k --keepParent Skald.app Skald.zip

xcrun notarytool submit Skald.zip \
  --apple-id you@example.com \
  --team-id TEAMID \
  --password APP_SPECIFIC_PASSWORD \
  --wait

xcrun stapler staple Skald.app
```

Re-zip after stapling so the staple ticket is bundled with the download.

```bash
rm Skald.zip
ditto -c -k --keepParent Skald.app Skald-0.2.0.zip
```

### 4. Sign the update payload

```bash
./Frameworks/Sparkle.framework/Versions/Current/Resources/../../../bin/sign_update Skald-0.2.0.zip
```

Outputs an `sparkle:edSignature` string and the file size. Both go into
the appcast item.

### 5. Update appcast.xml

Append a new `<item>` to your `appcast.xml` (modelled on
`/tmp/sparkle/SampleAppcast.xml`):

```xml
<item>
  <title>Skald 0.2.0</title>
  <pubDate>Mon, 01 Jun 2026 12:00:00 +0000</pubDate>
  <sparkle:version>2</sparkle:version>
  <sparkle:shortVersionString>0.2.0</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
  <description><![CDATA[
    <ul>
      <li>What's new in 0.2.0</li>
    </ul>
  ]]></description>
  <enclosure
    url="https://github.com/<user>/skald/releases/download/v0.2.0/Skald-0.2.0.zip"
    sparkle:version="2"
    sparkle:shortVersionString="0.2.0"
    length="..."
    type="application/octet-stream"
    sparkle:edSignature="..." />
</item>
```

`generate_appcast` (also in `Frameworks/.../bin/`) can produce the whole
file if you point it at a folder full of release zips.

### 6. Push the release

1. Commit `appcast.xml` to the gh-pages branch.
2. Create a GitHub Release tagged `v0.2.0`, attach `Skald-0.2.0.zip`.
3. Existing installs detect the new appcast item on next launch (or via
   menu-bar → Check for Updates…) and show the standard Sparkle update
   prompt.
