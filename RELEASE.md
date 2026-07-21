# Release Process

Parrocchettami distributes public beta builds as GitHub Release DMGs and uses
Sparkle for in-app update checks.

## Release policy

- Parrocchettami is a beta product, but publish each version as a full GitHub
  release, not as a GitHub pre-release. Mark the newest version as **Latest**
  unless explicitly instructed otherwise.
- Do not repeat unchanged system or hardware requirements in release notes.
  Include requirements only when a release changes them.

## One-time Sparkle setup

The Sparkle public EdDSA key is embedded in `package-dmg.sh` as
`SPARKLE_PUBLIC_ED_KEY`. The matching private key is stored in the maintainer's
login keychain by Sparkle's `generate_keys` tool.

The appcast is hosted by the separate `parrocchettami-site` GitHub Pages repo:

```text
https://martinowong.github.io/parrocchettami-site/appcast.xml
```

## Build a release

1. Update the version and release URLs in the `parrocchettami-site` repo if needed.
2. Resolve dependencies:

```bash
cd Parrocchettami
swift package resolve
```

3. Build the DMG from the repository root:

```bash
./setup.sh
./package-dmg.sh 1.1.0
```

4. Generate or refresh the Sparkle appcast after the DMG exists and the GitHub
   release tag is chosen:

```bash
mkdir -p /tmp/parrocchettami-updates
cp dist/Parrocchettami-1.1.0-Apple-Silicon.dmg /tmp/parrocchettami-updates/
Parrocchettami/.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/martinowong/parrocchettami/releases/download/v1.1.0/" \
  --link "https://martinowong.github.io/parrocchettami-site/" \
  --embed-release-notes \
  -o ../parrocchettami-site/appcast.xml \
  /tmp/parrocchettami-updates
```

5. Commit and push the updated appcast in `../parrocchettami-site`.
6. Create a full GitHub release, mark it as **Latest**, and upload all four
   generated release assets:

```text
dist/Parrocchettami-x.y.z-Apple-Silicon.dmg
dist/Parrocchettami-x.y.z-Apple-Silicon.dmg.sha256
dist/Parrocchettami-latest-Apple-Silicon.dmg
dist/Parrocchettami-latest-Apple-Silicon.dmg.sha256
```

The stable alias is what the website download buttons use. Repeat it on every
full published release so GitHub's `releases/latest/download/...` URL follows
the newest release. Keep the versioned DMG in the Sparkle appcast.
7. Ensure GitHub Pages deploys from the site repo's `.github/workflows/pages.yml`.
