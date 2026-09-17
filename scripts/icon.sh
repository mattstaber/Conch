#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
ICON_TOOL="/Applications/Icon Composer.app/Contents/Executables/ictool"
"$ICON_TOOL" "$PWD/Resources/AppIcon.icon" --export-image --output-file "$PWD/Resources/AppIcon.png" --platform macOS --rendition Default --width 1024 --height 1024 --scale 1 --design-generation 27
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
