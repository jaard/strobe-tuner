#!/usr/bin/env sh
# Build the Mac app for the Mac App Store, sign it with the given provisioning profile and package it as a .pkg
# for App Store Connect, upload it with the Transporter app.
#
# The bundle is assembled in build/macos-app-store from the Info.plist, credits and entitlements
# next to this script. The icon is made from AppIcon.iconset; the name comes from CFBundleName.
#
#   MAC_PROFILE=<path>              Mac App Store provisioning profile (.provisionprofile), required,
#                                   the bundle id and team come from it
#   MAC_SIGN_IDENTITY=<name>        app signing certificate, defaults to "Apple Distribution"
#   MAC_INSTALLER_IDENTITY=<name>   installer signing certificate, defaults to "3rd Party Mac Developer Installer"

set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/build/macos-app-store"

if [ -z "${MAC_PROFILE:-}" ] || [ ! -f "$MAC_PROFILE" ]; then
    echo "Set MAC_PROFILE to the Mac App Store provisioning profile (.provisionprofile)"
    exit 1
fi

. "$ROOT/platform/macos/build-bundle.sh"
PKG="$OUT/$NAME.pkg"

# The bundle id and team come from the profile, its application identifier is <team id>.<bundle id>
security cms -D -i "$MAC_PROFILE" > "$OUT/profile.plist"
APP_ID=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$OUT/profile.plist")
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$OUT/profile.plist")
BUNDLE_ID=${APP_ID#*.}
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
cp "$MAC_PROFILE" "$APP/Contents/embedded.provisionprofile"

# The sandbox and microphone entitlements, plus the app and team ids the profile allows
cp "$ROOT/platform/macos/app.entitlements" "$OUT/entitlements.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$OUT/entitlements.plist"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$OUT/entitlements.plist"

# Xcode records the SDK and itself in these, App Store Connect rejects uploads without them or with an old SDK.
# The Xcode version is written without dots, 26.6 is 2660 and 16.4.1 is 1641.
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version)
SDK_BUILD=$(xcrun --sdk macosx --show-sdk-build-version)
XCODE_VERSION=$(xcodebuild -version | awk 'NR == 1 { print $2 }')
XCODE_BUILD=$(xcodebuild -version | awk 'NR == 2 { print $3 }')
IFS=. read -r XCODE_MAJOR XCODE_MINOR XCODE_PATCH <<EOF
$XCODE_VERSION
EOF
PLIST="$APP/Contents/Info.plist"
plutil -replace DTPlatformName -string macosx "$PLIST"
plutil -replace DTPlatformVersion -string "$SDK_VERSION" "$PLIST"
plutil -replace DTPlatformBuild -string "$SDK_BUILD" "$PLIST"
plutil -replace DTSDKName -string "macosx$SDK_VERSION" "$PLIST"
plutil -replace DTSDKBuild -string "$SDK_BUILD" "$PLIST"
plutil -replace DTXcode -string "$XCODE_MAJOR${XCODE_MINOR:-0}${XCODE_PATCH:-0}" "$PLIST"
plutil -replace DTXcodeBuild -string "$XCODE_BUILD" "$PLIST"
plutil -replace DTCompiler -string com.apple.compilers.llvm.clang.1_0 "$PLIST"
plutil -replace BuildMachineOSBuild -string "$(sw_vers -buildVersion)" "$PLIST"

codesign --force --sign "${MAC_SIGN_IDENTITY:-Apple Distribution}" --entitlements "$OUT/entitlements.plist" "$APP"
codesign --verify --strict "$APP"
rm -rf "$FINAL_APP"
mv "$APP" "$FINAL_APP"
APP="$FINAL_APP"
productbuild --component "$APP" /Applications --sign "${MAC_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer}" "$PKG"
echo "Built $PKG ($BUNDLE_ID)"
