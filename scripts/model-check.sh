#!/usr/bin/env bash
# Builds the iPhone app's model code (the files that need only Foundation) with the Swift toolchain and runs the
# model checks (ios/PracticeTests/ModelChecks.swift): the same checks the iPhone unit tests run, here on the mini PC
# where there is no Mac. Swift for Windows: winget install Swift.Toolchain. Usage: bash scripts/model-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SW="${LOCALAPPDATA:-/c/Users/Joe/AppData/Local}/Programs/Swift"
SW="$(cygpath -u "$SW" 2>/dev/null || echo "$SW")"
VER="$(ls "$SW/Toolchains" | sort -V | tail -1)"; VER="${VER%%+*}"
export PATH="$SW/Toolchains/$(ls "$SW/Toolchains" | sort -V | tail -1)/usr/bin:$SW/Runtimes/$VER/usr/bin:$PATH"
export SDKROOT="$(cygpath -m "$SW/Platforms/$VER/Windows.platform/Developer/SDKs/Windows.sdk" 2>/dev/null || echo "$SW/Platforms/$VER/Windows.platform/Developer/SDKs/Windows.sdk")"
P=ios/Practice
OUT="${TMPDIR:-/tmp}/practice-model-check"
mkdir -p "$OUT"
swiftc -swift-version 5 -O -o "$OUT/model-check.exe" \
  $P/Scoring/*.swift $P/Library/RoutineClock.swift $P/Library/Tuning.swift $P/Library/Exercise.swift $P/Library/Routine.swift \
  $P/Library/Catalog.swift $P/Library/PracticeRoutine.swift $P/Engine/Sequencer.swift $P/Engine/OnsetDetector.swift \
  $P/Engine/GuitarBank.swift $P/Engine/PitchDetector.swift $P/Persistence/Results.swift \
  ios/ModelCheck/Stubs.swift ios/PracticeTests/ModelChecks.swift ios/ModelCheck/main.swift
"$OUT/model-check.exe"
