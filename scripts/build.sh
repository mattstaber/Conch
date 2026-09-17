#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
APP="$PWD/build/Conch.app"
if xcodebuild -version >/dev/null 2>&1; then
    xcodebuild -project Conch.xcodeproj -scheme Conch -configuration Release -derivedDataPath .build/XcodeRelease CODE_SIGNING_ALLOWED=NO build
    ditto .build/XcodeRelease/Build/Products/Release/Conch.app "$APP"
else
    swift build --disable-sandbox --scratch-path .build -c release
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp .build/release/Conch "$APP/Contents/MacOS/Conch"
    cp Resources/Info.plist "$APP/Contents/Info.plist"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
fi
codesign --force --options runtime --sign "${SIGNING_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
print "Built $APP"
