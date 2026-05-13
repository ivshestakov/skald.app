# Releasing Skald

Skald ships as a signed + notarized **DMG** hosted on GitHub Releases.
Existing installs auto-update through Sparkle reading
`https://panic-kit.com/skald/appcast.xml`.

The product page (`panic-kit.com/skald`) and the appcast feed both
live in the **panic-kit** repo (https://github.com/ivshestakov/panic-kit),
served via Vercel. Skald's own repo (this one) only holds the source +
release tooling — appcast updates land in panic-kit on every release.

This file covers both **one-time setup** (do once, ever) and the
**per-release procedure** (do for every new version).

---

## One-time setup

You only need to do this section once. After it's done, the per-release
steps below are a single `./release.sh` invocation plus a copy-paste.

### 1. Apple Developer ID Application certificate

The cert that signs the app for distribution outside the App Store.
Different from the "Apple Development" cert (which is for Xcode/local
testing only). Must live in your login keychain.

1. <https://developer.apple.com/account/resources/certificates/list>
   → **+** → "Developer ID Application" → Continue.
2. Apple asks for a **CSR** (Certificate Signing Request):
   - Open **Keychain Access** → menu **Certificate Assistant** →
     **Request a Certificate from a Certificate Authority…**
   - Email: your Apple-ID email
   - Common Name: `Ivan Shestakov`
   - Request is: **Saved to disk**
   - Continue → saves `CertificateSigningRequest.certSigningRequest`.
3. Upload the CSR file back on the Apple developer page. Apple returns
   `developerID_application.cer`.
4. Double-click the `.cer` to install it in the login keychain.
5. Verify:
   ```
   security find-identity -v -p codesigning | grep "Developer ID"
   ```
   Should print
   `Developer ID Application: Ivan Shestakov (PSDN96Z689)`.

### 2. notarytool keychain profile

`notarytool` submits builds to Apple's notary service. It needs an
**app-specific password** (not your regular Apple ID password).

1. <https://appleid.apple.com/account/manage> → **App-Specific Passwords**
   → **+** → name it `skald-notarize` → Generate.
   Apple shows the password **once**. Copy it.
2. In Terminal:
   ```
   xcrun notarytool store-credentials skald-notarize \
     --apple-id ivshestakov@gmail.com \
     --team-id PSDN96Z689 \
     --password <the-app-specific-password-from-step-1>
   ```
   This caches the credentials in the login keychain under a profile
   named `skald-notarize`. `release.sh` looks for that exact name.
3. Verify:
   ```
   xcrun notarytool history --keychain-profile skald-notarize
   ```
   Should not error (history may be empty — that's fine).

### 3. Sparkle EdDSA keypair

Already generated when this doc was written. Public key is in
`TranslatorApp/Info.plist` under `SUPublicEDKey`. Private key lives in
the login keychain under the account `https://sparkle-project.org`.

**Back up the private key immediately**:
```
TranslatorApp/Frameworks/Sparkle-bin/generate_keys -x ~/skald-sparkle-private.key
```
Store that file somewhere safe and offline (1Password, encrypted USB,
etc.). Losing it means existing installs can no longer verify any
future update — you'd have to ship a new public key in `Info.plist`
and every 0.3+ user would be stranded on their current version forever.

### 4. panic-kit hosting (nothing to do — already set up)

`panic-kit.com` is already deployed via Vercel from the
[ivshestakov/panic-kit](https://github.com/ivshestakov/panic-kit) repo.
Skald's product page lives there at `/skald/` and the appcast feed
at `/skald/appcast.xml`.

To make a release, you'll edit `skald/appcast.xml` in that repo —
either via the GitHub UI or by cloning it locally alongside this one.

Verify the appcast is reachable:
```
curl -fsSI https://panic-kit.com/skald/appcast.xml
```
Should return `HTTP/2 200`.

---

## Per-release procedure

For every new version (e.g. 0.3.0 → 0.3.1):

### 1. Bump the version

In `TranslatorApp/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>0.3.1</string>       <!-- semantic version users see -->
<key>CFBundleVersion</key>
<string>6</string>            <!-- monotonic build number (must increase) -->
```

Commit on `main`.

### 2. Build, sign, notarize, package

From `TranslatorApp/`:

```bash
SKALD_SIGN_IDENTITY="Developer ID Application: Ivan Shestakov (PSDN96Z689)" \
  ./release.sh
```

This script does the whole pipeline:

1. Compiles a universal binary (arm64 + x86_64).
2. Signs the app with Developer ID + hardened runtime + secure timestamp.
3. Zips the app, submits to Apple notary (`--wait`, ~2 min), staples
   the ticket into the .app.
4. Builds `dist/Skald-<version>.dmg` (HFS+, UDZO compression, contains
   `Skald.app` + `/Applications` symlink).
5. Signs the DMG, submits it to notary, staples the DMG.
6. Runs Sparkle's `sign_update` to produce the EdDSA signature line.
7. Prints a ready-to-paste `<item>` block for `appcast.xml`.

End state: `TranslatorApp/dist/Skald-0.3.1.dmg` exists, is notarized,
stapled, and Sparkle-signed.

### 3. Publish a GitHub Release

```bash
gh release create v0.3.1 TranslatorApp/dist/Skald-0.3.1.dmg \
  --title "Skald 0.3.1" \
  --notes-file <(printf '## What's new\n\n- thing 1\n- thing 2\n')
```

### 4. Update appcast.xml (in the panic-kit repo)

Paste the `<item>` block that `release.sh` printed into the panic-kit
repo at `skald/appcast.xml`, just below the comment inside `<channel>`
(newest item first). Fill in the release notes in the
`<description><![CDATA[ … ]]></description>` block (HTML allowed —
Sparkle renders it in the update prompt).

Two ways to do it:

**A. Via GitHub UI** (one-off, no clone needed):
<https://github.com/ivshestakov/panic-kit/edit/main/skald/appcast.xml>

**B. Local clone** (cleaner if you do this often):
```bash
gh repo clone ivshestakov/panic-kit ~/code/panic-kit
cd ~/code/panic-kit
# edit skald/appcast.xml
git add skald/appcast.xml
git commit -m "skald: appcast 0.3.1"
git push
```

Vercel redeploys panic-kit within ~30 seconds. Existing installs poll
the appcast every 24h (configurable via `SUScheduledCheckInterval` in
Info.plist) and on next launch.

### 5. Sanity-check the update flow

On any 0.3+ install:
- Menu-bar → **Check for Updates…**
- Should show "Skald 0.3.1 is now available" with the release notes.
- Click **Install Update** → Sparkle downloads the DMG, mounts it,
  copies the new app over the running one, relaunches.

---

## Recovery scenarios

**Lost the Sparkle private key.** Generate a new one
(`generate_keys`). Bump version, ship a new release with the new
public key in `Info.plist`. Existing installs can no longer
auto-update — they'll be stuck on their current version and need a
manual reinstall. (This is why §1.3 says back it up.)

**Notarization rejected.** `notarytool log <submission-id>
--keychain-profile skald-notarize` shows the full report. Most common
cause is signing without `--timestamp` or without `--options=runtime`
— both are set in `build.sh`. Second most common cause is an embedded
binary not signed at all (every nested executable in the bundle must
be signed, in inside-out order).

**Sparkle update fails to install.** Check the Console.app log filtered
by `Skald` for errors. Common causes:
- DMG enclosure size in appcast doesn't match the actual file size
  (a CDN cached the wrong version).
- `sparkle:edSignature` doesn't verify (DMG was modified after signing).
