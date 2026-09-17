#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
python3 Tests/test_project_generation.py
clang -std=c11 -Wall -Wextra -Wno-unused-parameter -fsanitize=address,undefined -g -I Sources/Realtime/include Sources/Realtime/Realtime.c Tests/realtime_tests.c -framework CoreAudio -o .build/realtime-tests
.build/realtime-tests
swift test --disable-sandbox --scratch-path .build
