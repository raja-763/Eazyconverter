# Releasing a signed DMG

The release workflow (`.github/workflows/release.yml`) builds eazyConverter on GitHub's Mac build machines. It then:

1. signs the app with your Developer ID certificate, with the hardened runtime and a secure timestamp
2. sends the app to Apple for notarization and staples the ticket to it
3. puts the app in a DMG with a shortcut to Applications
4. signs, notarizes and staples the DMG
5. checks both with Gatekeeper (`spctl`)
6. publishes the DMG and a SHA-256 checksum as a GitHub release

If any step fails, nothing is published.

**Without the signing secrets**, the workflow still runs: it builds an ad-hoc signed app, makes the DMG and publishes it as "(not notarized)", with instructions for opening it the first time (System Settings, Privacy & Security, Open Anyway). Add the secrets below to get rid of that step.

## What you need first

- **Apple Developer Program membership.** It costs 99 US dollars a year. Notarization and Developer ID are included, and the free Apple account doesn't include them.
- **A Developer ID Application certificate.**
- **An App Store Connect API key** for notarization.

## One-time setup

### 1. Create the Developer ID certificate

1. In Xcode, open Settings (Command-Comma), then the Accounts tab.
2. Select your Apple ID, then choose Manage Certificates.
3. Choose the Add (+) pop-up button, then Developer ID Application.

### 2. Export it as a .p12 file

1. Open Keychain Access (in Applications > Utilities).
2. In the My Certificates category, find "Developer ID Application: your name (TEAM ID)".
3. Select it and choose File > Export Items. Save it as `certificate.p12` on your Desktop and set a strong password.
4. In Terminal, turn it into text for GitHub:

   ```
   base64 -i ~/Desktop/certificate.p12 | pbcopy
   ```

   The text is now on your clipboard. Delete `certificate.p12` once the secret is saved.

### 3. Find your Team ID

Sign in at developer.apple.com/account and open Membership details. The Team ID is 10 characters long.

### 4. Create the notarization API key

1. Sign in at appstoreconnect.apple.com, then go to Users and Access, Integrations, App Store Connect API.
2. Under Team Keys, create a key with the **Developer** role.
3. Copy the **Issuer ID** (a long ID with dashes) and the key's **Key ID** (10 characters).
4. Download the `.p8` key file. Apple only lets you download it once.

### 5. Add six repository secrets

On GitHub, open the repo, then Settings, Secrets and variables, Actions, and choose New repository secret for each of these:

| Name | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | The base64 text from step 2 |
| `MACOS_CERTIFICATE_PASSWORD` | The password you set when exporting the .p12 |
| `APPLE_TEAM_ID` | Your 10-character Team ID |
| `NOTARY_KEY_P8` | The whole contents of the .p8 file, including the BEGIN and END lines |
| `NOTARY_KEY_ID` | The API key's Key ID |
| `NOTARY_ISSUER_ID` | The Issuer ID |

GitHub encrypts secrets and never shows them in build logs. The workflow deletes the certificate and key from the build machine when it finishes.

## Making a release

1. On the repo page, go to Releases, then choose "Draft a new release".
2. In "Choose a tag", type the version, such as `v1.0.0`, and choose "Create new tag".
3. Leave the title and description empty: the workflow fills them in.
4. Choose "Publish release".

The workflow then builds the DMG and attaches it, with a `.sha256` checksum, to that release. It usually takes about 5 minutes unsigned, or 15 to 30 minutes signed, mostly waiting on Apple's notarization. You can follow it on the Actions tab.

## Checking a DMG yourself

After downloading, these commands should all report that it's accepted or valid:

```
spctl --assess --type open --context context:primary-signature --verbose ~/Downloads/eazyConverter-1.0.0.dmg
xcrun stapler validate ~/Downloads/eazyConverter-1.0.0.dmg
shasum -a 256 ~/Downloads/eazyConverter-1.0.0.dmg
```

Compare the last one with the `.sha256` file on the release.
