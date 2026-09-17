#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" build
staging=$(mktemp -d "$PWD/.build/bundle.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Conch.app"
python3 scripts/generate-project.py
if xcodebuild -version >/dev/null 2>&1; then
    xcodebuild -project Conch.xcodeproj -scheme Conch -configuration Release \
        -derivedDataPath .build/Xcode CODE_SIGNING_ALLOWED=NO \
        ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build
    ditto .build/Xcode/Build/Products/Release/Conch.app "$app"
else
    swift build --disable-sandbox --scratch-path .build/swiftpm -c release
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    bin_path=$(swift build --disable-sandbox --scratch-path .build/swiftpm -c release --show-bin-path)
    cp "$bin_path/Conch" "$app/Contents/MacOS/Conch"
    cp Resources/Info.plist "$app/Contents/Info.plist"
    cp Resources/AppIcon.icns "$app/Contents/Resources/"
fi
mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
# Stamp only the staged bundle; a tagged CI build never edits source files.
python3 - "$app/Contents/Info.plist" <<'PY'
import os
import plistlib
import re
import sys
from pathlib import Path
path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
version = os.environ.get('CONCH_VERSION', info['CFBundleShortVersionString'])
build = os.environ.get('CONCH_BUILD_NUMBER', info['CFBundleVersion'])
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('CONCH_VERSION must be major.minor.patch')
if not re.fullmatch(r'[1-9]\d*', build):
    raise SystemExit('CONCH_BUILD_NUMBER must be a positive integer')
info['CFBundleShortVersionString'] = version
info['CFBundleVersion'] = build
path.write_bytes(plistlib.dumps(info))
PY
signing_identity="${SIGNING_IDENTITY:--}"
sign_options=(--force --options runtime --sign "$signing_identity")
if [[ "$signing_identity" != '-' ]]; then sign_options+=(--timestamp); fi
codesign "${sign_options[@]}" "$app"
codesign --verify --strict "$app"
# Replace the generated bundle only after a successful build/signature check.
rm -rf "$PWD/build/Conch.app"
ditto "$app" "$PWD/build/Conch.app"
print "Built $PWD/build/Conch.app"
