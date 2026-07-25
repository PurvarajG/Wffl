# Release signing setup

The `Release Wffl` workflow (`.github/workflows/release.yml`) builds, signs,
notarizes, and publishes `Wffl.dmg` whenever a `v*` tag is pushed. The website's
download button points at
`https://github.com/PurvarajG/Wffl/releases/latest/download/Wffl.dmg`, so **the
link only works once that workflow has published a release**.

It needs six repository secrets. Until they are all set, the workflow stops at
the "Check signing secrets are configured" step with the missing names listed.

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
