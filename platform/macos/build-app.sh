#!/usr/bin/env sh
# Build a standalone Apple silicon .app for local use, without Apple certificates.
# MAC_BUNDLE_ID overrides the stable local identifier (default: app.strobie.local).

set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/build/macos"

. "$ROOT/platform/macos/build-bundle.sh"

BUNDLE_ID=${MAC_BUNDLE_ID:-app.strobie.local}
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"

# Apple silicon requires a code signature. Ad hoc signing needs no account or certificate.
# This build is not sandboxed and does not use the App Store entitlements or profile.
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"

# Keep the previous app until the new bundle is complete and verified.
rm -rf "$FINAL_APP"
mv "$APP" "$FINAL_APP"

echo "Built $FINAL_APP ($BUNDLE_ID)"
echo "Open with: open \"$FINAL_APP\""
