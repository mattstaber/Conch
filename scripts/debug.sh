#!/bin/zsh
# Build the same Debug app used by the Xcode Conch scheme.
set -euo pipefail
cd "${0:A:h:h}"
python3 scripts/generate-project.py
xcodebuild -project Conch.xcodeproj -scheme Conch -configuration Debug \
    -derivedDataPath .build/Xcode CODE_SIGN_IDENTITY=- build
codesign --verify --strict .build/Xcode/Build/Products/Debug/Conch.app
print "Built $PWD/.build/Xcode/Build/Products/Debug/Conch.app"
