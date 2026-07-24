# Releasing Wffl

## One-time setup

1. Enrol in the Apple Developer Program and create a **Developer ID Application** certificate.
2. Export that certificate as a `.p12`, then add these GitHub Actions secrets:
   - `WFFL_SIGN_IDENTITY` — for example `Developer ID Application: Your Name (TEAMID)`
   - `APPLE_CERTIFICATE_BASE64` — base64-encoded `.p12`
   - `APPLE_CERTIFICATE_PASSWORD` — its export password
   - `APPLE_API_KEY_ID`, `APPLE_API_ISSUER`, `APPLE_API_KEY_BASE64` — App Store Connect API key credentials for notarization
3. In Vercel, import this GitHub repository and set the **Root Directory** to `website`. Vercel deploys the download page after every push to `master`.

Never commit certificates, API keys, passwords, or Sparkle private keys.

## Release a version

1. Update `CFBundleShortVersionString` in `Support/Info.plist` while developing.
2. Merge to `master`, then create and push a matching semantic-version tag:

   ```bash
   git tag v1.3.5
   git push origin v1.3.5
   ```

3. The `Release Wffl` workflow tests, signs, notarizes, creates `Wffl.dmg`, and publishes it on GitHub Releases.
4. The download page points at GitHub's `releases/latest` URL, so no site change is needed for a normal release.

## In-app updates (Sparkle)

Sparkle is intentionally not enabled until the app is signed with a Developer ID certificate and an update-signing key is safely stored. Enabling it before those keys exist would ship an update mechanism that cannot safely verify releases.

When the credentials are ready:

1. Generate a Sparkle EdDSA key pair locally with Sparkle's `generate_keys` tool. Store the private key in the macOS Keychain or your secret manager.
2. Add only the generated public key to `Support/Info.plist` as `SUPublicEDKey`, plus the HTTPS `SUFeedURL` for `appcast.xml`.
3. Add the private Sparkle key to GitHub Actions secrets and have the release workflow generate and publish a signed `appcast.xml` alongside each DMG.
4. Add the Sparkle framework/package and an explicit “Automatically check for updates” preference in Wffl.

Until then, users update safely by downloading the newest notarized DMG from the Wffl site.
