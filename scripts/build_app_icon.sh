#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
ICON_OUTPUT=${1:?Usage: zsh scripts/build_app_icon.sh /absolute/path/AppIcon.icns}
ICON_TEMP=$(mktemp -d "${TMPDIR:-/tmp/}FroggyTalkie-icon.XXXXXX")
trap 'rm -rf -- "$ICON_TEMP"' EXIT
ICON_SET="$ICON_TEMP/AppIcon.iconset"
mkdir -p "$ICON_SET"
swift -module-cache-path .cache/clang scripts/render_app_icon.swift \
    Assets/AppIcon.png "$ICON_TEMP/AppIcon.png"
# Generate all standard 1x/2x representations from the same rounded master.
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$ICON_TEMP/AppIcon.png" \
        --out "$ICON_SET/icon_${size}x${size}.png" >/dev/null
    pixels=$((size * 2))
    if [[ "$pixels" == 1024 ]]; then
        cp "$ICON_TEMP/AppIcon.png" "$ICON_SET/icon_${size}x${size}@2x.png"
    else
        /usr/bin/sips -z "$pixels" "$pixels" "$ICON_TEMP/AppIcon.png" \
            --out "$ICON_SET/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
/usr/bin/iconutil -c icns "$ICON_SET" -o "$ICON_OUTPUT"
