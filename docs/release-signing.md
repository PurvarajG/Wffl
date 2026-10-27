# Release signing setup

The `Release Wffl` workflow (`.github/workflows/release.yml`) builds, signs,
notarizes, and publishes `Wffl.dmg` whenever a `v*` tag is pushed. The website's
download button points at
`https://github.com/PurvarajG/Wffl/releases/latest/download/Wffl.dmg`, so **the
link only works once that workflow has published a release**.

It needs seven repository secrets: six for Apple signing and notarization, and
`SPARKLE_ED_PRIVATE_KEY` for in-app updates (see section 6). Until they are all set, the workflow
stops at the "Check signing secrets are configured" step with the missing names listed. It also
refuses to release while `SUPublicEDKey` in `Support/Info.plist` is still the placeholder.

## Prerequisites

- An active Apple Developer Program membership.
- A **Developer ID Application** certificate in your local login keychain,
  with its private key. Confirm with:

  ```bash
  security find-identity -v -p codesigning
  ```

  The line you want looks like
  `"Developer ID Application: Your Name (TEAMID)"`. That whole string, without
  the surrounding quotes, is `WFFL_SIGN_IDENTITY`.

## 1. Export the certificate as a .p12

Keychain Access → **My Certificates** → right-click the *Developer ID
Application* entry → **Export…** → format *Personal Information Exchange
(.p12)* → save as `~/wffl-signing.p12` and set a password.

Make sure you export the row that expands to show a private key. Exporting
from the "Certificates" category gives you the public certificate only, and the
build will fail with "does not provide identity".

Then base64-encode it (`-w0`/no wrapping matters — the workflow decodes a single
line):

```bash
base64 -i ~/wffl-signing.p12 | tr -d '\n' | pbcopy
```

That clipboard value is `APPLE_CERTIFICATE_BASE64`. The password you chose is
`APPLE_CERTIFICATE_PASSWORD` (the workflow reuses it as the temporary CI
keychain password too).

## 2. Create an App Store Connect API key for notarization

App Store Connect → **Users and Access** → **Integrations** → **App Store
Connect API** → **Team Keys** → **+**. Give it the *Developer* role. Then:

- **Key ID** (e.g. `A1B2C3D4E5`) → `APPLE_API_KEY_ID`
- **Issuer ID** (the UUID at the top of the page) → `APPLE_API_ISSUER`
- Download the `AuthKey_<KEYID>.p8` — **it can only be downloaded once** — and
  encode it:

  ```bash
  base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | pbcopy
  ```

  That value is `APPLE_API_KEY_BASE64`.

## 3. Set the secrets

`gh` figures out which repository you mean from the git remote, so either run
these from a clone:

```bash
cd ~/Documents/PROJECTS/MeetilyMac
```

…or pass `--repo PurvarajG/Wffl` on every command. Running them from your home
directory without `--repo` fails with `fatal: not a git repository`.

**Run them one at a time.** Each command stops and prompts `? Paste your
secret:`. If you paste all six lines as a block, lines 2-6 are consumed as the
answer to the first prompt and you end up with one garbage secret.

```bash
gh secret set WFFL_SIGN_IDENTITY --repo PurvarajG/Wffl
```
```bash
gh secret set APPLE_CERTIFICATE_BASE64 --repo PurvarajG/Wffl
```
```bash
gh secret set APPLE_CERTIFICATE_PASSWORD --repo PurvarajG/Wffl
```
```bash
gh secret set APPLE_API_KEY_ID --repo PurvarajG/Wffl
```
```bash
gh secret set APPLE_API_ISSUER --repo PurvarajG/Wffl
```
```bash
gh secret set APPLE_API_KEY_BASE64 --repo PurvarajG/Wffl
```

For the two base64 values, the string is long enough that pasting into a prompt
can be flaky. Piping the file straight in is more reliable:

```bash
base64 -i ~/wffl-signing.p12 | tr -d '\n' | gh secret set APPLE_CERTIFICATE_BASE64 --repo PurvarajG/Wffl
```
```bash
base64 -i ~/Downloads/AuthKey_XXXXXXXXXX.p8 | tr -d '\n' | gh secret set APPLE_API_KEY_BASE64 --repo PurvarajG/Wffl
```

Verify all six are present:

```bash
gh secret list --repo PurvarajG/Wffl
```

Afterwards, delete the exported material — it is a signing key, and the copies
on disk are no longer needed:

```bash
rm -f ~/wffl-signing.p12 ~/Downloads/AuthKey_*.p8
```

## 4. Cut the release

`v1.3.5` is already tagged but its run failed, so the tag has no release.
Re-run that same tag rather than inventing a new version:

```bash
gh run rerun 30107707690 --repo PurvarajG/Wffl
```

Or, for a fresh version (the workflow writes the tag's version into
`Support/Info.plist` itself, so no manual bump is needed):

```bash
git tag v1.3.6 && git push origin v1.3.6
```

Watch it:

```bash
gh run watch --repo PurvarajG/Wffl
```

## 5. Verify the download actually works

```bash
gh release view --repo PurvarajG/Wffl --json assets --jq '.assets[].name'
curl -sIL https://github.com/PurvarajG/Wffl/releases/latest/download/Wffl.dmg | grep -i '^HTTP/'
```

The asset list must contain `Wffl.dmg` and the final status must be `200`. Then
download it in a browser and open it — a correctly notarized build opens with no
Gatekeeper warning at all. To check a local copy:

```bash
spctl -a -vvv -t install /Volumes/Wffl/Wffl.app
```

Expect `source=Notarized Developer ID`.

## 6. Updates (Sparkle): one-time key setup

Wffl checks for updates with Sparkle. Each release is signed with an EdDSA key so the app can
verify what it downloads. The feed is `appcast.xml`, which the workflow uploads to every release
next to `Wffl.dmg`; the app reads it from
`https://github.com/PurvarajG/Wffl/releases/latest/download/appcast.xml`.

This is separate from Apple code signing and needs one more secret, `SPARKLE_ED_PRIVATE_KEY`.

**Releases fail without the key and the secret, on purpose.** The app's feed URL is
`releases/latest/download/appcast.xml`, so a release that lacks `appcast.xml` would make that URL
404 and break update checks for every existing install. And a build whose `SUPublicEDKey` is still the
placeholder has an updater that never starts. So the workflow stops early, before the long build, if:

- `SPARKLE_ED_PRIVATE_KEY` is not set (the "Check signing secrets are configured" step), or
- `SUPublicEDKey` in `Support/Info.plist` is still `SPARKLE_PUBLIC_ED_KEY_NOT_SET`, or
- the secret is not the private half of that public key (the "Check Sparkle update key" step signs a
  probe file with it and compares the key it derives against `SUPublicEDKey`).

You can run the same check locally with the exported key:

```bash
SPARKLE_ED_PRIVATE_KEY="$(cat ~/wffl-sparkle-private-key)" scripts/make-appcast.sh --check-key Support/Info.plist
```

**Generate the key pair once.** The tool ships with the Sparkle package, so after any `swift build`:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

It stores the private key in your login Keychain (macOS may ask you to allow access) and prints the
public key. If a key already exists it prints that public key and changes nothing. To print it again
later: `generate_keys -p`.

**Paste the public key into the app.** Replace `SPARKLE_PUBLIC_ED_KEY_NOT_SET` in
`Support/Info.plist` (`SUPublicEDKey`) with the printed value and commit it. Until then builds warn
at bundle time, and the app shows "This build of Wffl can’t check for updates." in Settings. Do not
lose the private key: every installed copy trusts only this public key, so a new key means every user
has to reinstall by hand once.

**Export the private key for GitHub.** The private key stays in your Keychain; export a copy only to
hand it to the workflow:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/wffl-sparkle-private-key
gh secret set SPARKLE_ED_PRIVATE_KEY --repo PurvarajG/Wffl < ~/wffl-sparkle-private-key
rm -f ~/wffl-sparkle-private-key
```

Keep a backup of the exported key in a password manager before you delete the file.

**Verify an update end to end.**

1. Install a build that has the real public key and an older version (for example the previous
   release's DMG, or `scripts/bundle.sh release` with a lower `CFBundleVersion`).
2. Publish a newer release. Confirm the assets include both files:

   ```bash
   gh release view --repo PurvarajG/Wffl --json assets --jq '.assets[].name'
   ```

   Expect `Wffl.dmg` and `appcast.xml`.
3. Check the feed: `curl -sL https://github.com/PurvarajG/Wffl/releases/latest/download/appcast.xml`
   should show the new `sparkle:shortVersionString`, a `sparkle:version` higher than the installed
   build, an `enclosure` URL ending in `/Wffl.dmg`, and a `sparkle:edSignature`.
4. Check the signature of the published DMG matches the feed:

   ```bash
   curl -sLO https://github.com/PurvarajG/Wffl/releases/latest/download/Wffl.dmg
   .build/artifacts/sparkle/Sparkle/bin/sign_update --verify Wffl.dmg "<sparkle:edSignature value>"
   ```
5. In the older install choose **Wffl, Check for Updates…** (or Settings, Updates, Check Now). Sparkle
   should offer the new version, download it, replace the app and relaunch. Afterwards
   `spctl -a -vvv -t exec /Applications/Wffl.app` should still say `Notarized Developer ID`.

A shortened check interval helps while testing: `defaults write com.purvaraj.wffl SUScheduledCheckInterval -int 60`
(Sparkle enforces a 60 second minimum), then relaunch. Remove it with `defaults delete` when done.
