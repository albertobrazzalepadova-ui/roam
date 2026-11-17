#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${ROAM_DEVICE:-2EA5531C-5005-58E3-B569-E710755E6851}"
# Sign in with Apple needs a paid Apple Developer team: ROAM_APPLE_SIGNIN=1 ./install.sh
EXTRA=()
if [ "${ROAM_APPLE_SIGNIN:-0}" = "1" ]; then EXTRA+=(CODE_SIGN_ENTITLEMENTS=Roam/Roam.entitlements); fi
xcodebuild -project Roam.xcodeproj -scheme Roam -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath /tmp/roam-install DEVELOPMENT_TEAM=8A54VYSXGR PRODUCT_BUNDLE_IDENTIFIER=it.robertolibanora.roam -allowProvisioningUpdates ${EXTRA[@]+"${EXTRA[@]}"} build
xcrun devicectl device install app --device "$DEVICE" /tmp/roam-install/Build/Products/Debug-iphoneos/Roam.app
xcrun devicectl device process launch --device "$DEVICE" it.robertolibanora.roam
