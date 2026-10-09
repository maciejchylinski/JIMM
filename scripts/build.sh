#!/bin/sh
# Repeatable builds for JIMM (scheme: JIMM → JIMM.app + embedded RestTimerLiveActivityExtension.appex).
# Run from repo root: ./scripts/build.sh [sim|ios|clean]

set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="JIMM.xcodeproj"
SCHEME="JIMM"
DERIVED="DerivedDataLocal"

run_build() {
  destination="$1"
  echo "==> xcodebuild -scheme ${SCHEME} -destination '${destination}' -derivedDataPath ${DERIVED} $2"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -destination "${destination}" \
    -derivedDataPath "${DERIVED}" \
    $2
}

case "${1:-sim}" in
  clean)
    echo "==> Removing local and global DerivedData for JIMM"
    rm -rf "${DERIVED}"
    rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/JIMM-"*
    rm -rf "${HOME}/Library/Developer/Xcode/DerivedData/jim-"*
    ;;
  ios)
    run_build "generic/platform=iOS" "build"
    ;;
  sim)
    run_build "generic/platform=iOS Simulator" "build"
    ;;
  clean-sim)
    rm -rf "${DERIVED}"
    run_build "generic/platform=iOS Simulator" "clean build"
    ;;
  clean-ios)
    rm -rf "${DERIVED}"
    run_build "generic/platform=iOS" "clean build"
    ;;
  *)
    echo "Usage: $0 [sim|ios|clean|clean-sim|clean-ios]" >&2
    exit 1
    ;;
esac

echo "==> OK"
