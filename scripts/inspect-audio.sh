#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/cache
swiftc -module-cache-path .build/cache Sources/Conch/AudioHAL.swift Sources/Conch/MixerState.swift Sources/Conch/ProcessResolver.swift scripts/InspectAudio.swift -o .build/inspect-audio
.build/inspect-audio
