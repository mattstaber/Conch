#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcrun swift-format format --in-place --recursive Sources/Conch Tests/ConchTests
xcrun swift-format format --in-place Package.swift scripts/InspectAudio.swift
