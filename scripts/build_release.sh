#!/bin/zsh
# Builds a separate distribution candidate. Never replaces dist/ or installs an app.
set -euo pipefail
umask 022
cd "${0:A:h}/.."
VERSION=$(<VERSION)
BUILD=$(<BUILD_NUMBER)
[[ "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$BUILD" =~ '^[0-9]+$' ]] || exit 1
[[ $(uname -m) == arm64 ]] || { print -u2 'Build on an Apple Silicon Mac.'; exit 1; }
OUTPUT="$PWD/release/$VERSION"
IDENTITY="-"
while (( $# )); do
    case "$1" in
        --output) OUTPUT=${2:?Missing output directory}; shift 2 ;;
        --identity) IDENTITY=${2:?Missing Developer ID Application identity}; shift 2 ;;
        *) print -u2 'Usage: zsh scripts/build_release.sh [--output DIR] [--identity "Developer ID Application: …"]'; exit 1 ;;
    esac
done
OUTPUT=${OUTPUT:A}
[[ "$OUTPUT" != "$PWD/dist" && "$OUTPUT" != "$PWD/dist/"* ]] || {
    print -u2 'Distribution builds cannot write into dist/.'; exit 1
}
MODE=preview
if [[ "$IDENTITY" != '-' ]]; then
    [[ "$IDENTITY" == 'Developer ID Application: '* ]] || {
        print -u2 'Use a Developer ID Application identity, or omit --identity for an ad-hoc preview.'; exit 1
    }
    MODE=developer-id-unnotarized
fi
NAME="Froggy-Talkie-$VERSION-macos-arm64-$MODE"
[[ ! -e "$OUTPUT/Froggy Talkie.app" && ! -e "$OUTPUT/$NAME.zip" ]] || {
    print -u2 'Output already exists. Choose another --output directory.'; exit 1
}
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
swift build -c release --product LocalDictation --disable-automatic-resolution \
    --cache-path .cache/spm --config-path .cache/config --security-path .cache/security
BIN=$(swift build -c release --show-bin-path --cache-path .cache/spm --config-path .cache/config --security-path .cache/security)
mkdir -p "$OUTPUT"
STAGING=$(mktemp -d "$OUTPUT/.froggy-release.XXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT
PAYLOAD="$STAGING/Froggy Talkie-$VERSION"
APP="$PAYLOAD/Froggy Talkie.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/LocalDictation" "$APP/Contents/MacOS/LocalDictation"
zsh scripts/build_app_icon.sh "$APP/Contents/Resources/AppIcon.icns"
# Explicit allowlist: ASR does not use FluidAudio's LuxTTS GPL/CC-BY-SA dictionaries.
cp -R "$BIN/LocalDictation_DictationModels.bundle" "$APP/Contents/Resources/"
cp -R Licenses "$APP/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp docs/INSTALL.md "$PAYLOAD/INSTALL.md"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalDictation</string>
<key>CFBundleIdentifier</key><string>local.research.LocalDictation</string>
<key>CFBundleName</key><string>Froggy Talkie</string>
<key>CFBundleDisplayName</key><string>Froggy Talkie</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSArchitecturePriority</key><array><string>arm64</string></array>
<key>NSMicrophoneUsageDescription</key><string>Запись голоса по кнопке или при удержании горячей клавиши для локального распознавания на Mac.</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>© 2026 Froggy Talkie contributors. MIT License.</string>
</dict></plist>
PLIST
python3 scripts/release_metadata.py "$APP" "$MODE"
# Strip Finder/download metadata from the new bundle before signing it.
/bin/chmod -R u+w "$APP"
/usr/bin/xattr -cr "$APP"
if [[ "$IDENTITY" == '-' ]]; then
    /usr/bin/codesign --force --sign - --options runtime --timestamp=none \
        --entitlements packaging/Release.entitlements "$APP"
else
    /usr/bin/codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        --entitlements packaging/Release.entitlements "$APP"
    # Check certificate type and Apple trust, not just the user-supplied name.
    /usr/bin/codesign --verify --strict --test-requirement \
        '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$APP"
fi
/usr/bin/codesign --verify --deep --strict "$APP"
python3 scripts/verify_release.py "$APP"
/usr/bin/ditto -c -k --keepParent "$PAYLOAD" "$STAGING/$NAME.zip"
mv "$APP" "$OUTPUT/Froggy Talkie.app"
mv "$STAGING/$NAME.zip" "$OUTPUT/$NAME.zip"
cp docs/INSTALL.md "$OUTPUT/INSTALL.md"
(cd "$OUTPUT"; /usr/bin/shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256")
print "Built: $OUTPUT/$NAME.zip"
print 'This candidate is NOT notarized. See docs/RELEASE.md before public distribution.'
