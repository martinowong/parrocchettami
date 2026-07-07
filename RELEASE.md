# Release Process

Parrocchettami distributes public beta builds as GitHub Release DMGs and uses
Sparkle for in-app update checks.

## One-time Sparkle setup

The Sparkle public EdDSA key is embedded in `package-dmg.sh` as
`SPARKLE_PUBLIC_ED_KEY`. The matching private key is stored in the maintainer's
login keychain by Sparkle's `generate_keys` tool.

The appcast is hosted by GitHub Pages:

```text
https://martinowong.github.io/parrocchettami/appcast.xml
```

## Build a release

1. Update the version and release URLs in website/docs if needed.
2. Resolve dependencies:

```bash
cd Parrocchettami
swift package resolve
```

3. Build the DMG from the repository root:

```bash
./setup.sh
./package-dmg.sh 1.0.8
```

4. Generate or refresh the Sparkle appcast after the DMG exists and the GitHub
   release tag is chosen:

```bash
mkdir -p /tmp/parrocchettami-updates
cp dist/Parrocchettami-1.0.8-Apple-Silicon.dmg /tmp/parrocchettami-updates/
Parrocchettami/.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
  --download-url-prefix "https://github.com/martinowong/parrocchettami/releases/download/v1.0.8-beta.1/" \
  --link "https://martinowong.github.io/parrocchettami/" \
  --embed-release-notes \
  -o website/appcast.xml \
  /tmp/parrocchettami-updates
```

5. Commit and push the release files.
6. Create the GitHub prerelease and upload the DMG plus checksum.
7. Ensure GitHub Pages deploys from `.github/workflows/pages.yml`.
