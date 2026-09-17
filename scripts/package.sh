#!/bin/zsh
# Package the already-built app without changing its signature or notarization.
set -euo pipefail
cd "${0:A:h:h}"
app="$PWD/build/Conch.app"
codesign --verify --strict "$app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Expected a major.minor.patch version'; exit 1; }
lipo -verify_arch arm64 "$app/Contents/MacOS/Conch"
mkdir -p dist
archive="Conch-${version}-macOS-arm64.zip"
# ditto preserves the executable permissions, bundle layout and signing metadata.
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
(cd dist && shasum -a 256 "$archive" > "$archive.sha256")
print "Packaged dist/$archive"
