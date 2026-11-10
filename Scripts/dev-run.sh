#!/bin/zsh
# Builds Ieum.app, re-signs it with the Developer ID identity so macOS keeps the microphone and speech permissions,
# and launches a fresh copy. Extra arguments are passed to the app as launch arguments, for example:
#   Scripts/dev-run.sh -heardLanguage en -shownLanguage ko -source microphone -displayMode panel
# Needs SIGN_IDENTITY (find it with: security find-identity -v -p codesigning). Without it the build stays ad-hoc signed
# and macOS asks for the permissions again.
set -e
cd "$(dirname "$0")/.."
make app
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --options runtime --sign "$SIGN_IDENTITY" --entitlements Resources/entitlements.plist .build/app/Ieum.app
fi
pkill -x Ieum 2>/dev/null || true
sleep 1
open -n .build/app/Ieum.app --args "$@"
