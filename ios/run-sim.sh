#!/usr/bin/env bash
# Build the MCAT Speedrun iOS app and run it in the Simulator.
#
# IMPORTANT: the project folder is on iCloud Drive, which stamps files with
# attributes that break code signing. So we build into a LOCAL DerivedData path
# (outside iCloud) and let xcodebuild sign normally — exactly what Xcode does.
# That produces a valid signature, which is what Firebase Auth's keychain needs.
# Uses the free personal team already baked into the project (no App Store acct).
#
# Usage: ios/run-sim.sh [simulator-name]   (default: "iPhone 17")
set -euo pipefail

cd "$(dirname "$0")/MCATSpeedrun"
SIM_NAME="${1:-iPhone 17}"
DD="$HOME/Library/Caches/mcat-ios-deriveddata"   # local, NOT in the iCloud folder

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Building + signing (DerivedData: $DD)"
xcodebuild -project MCATSpeedrun.xcodeproj -scheme MCATSpeedrun \
  -sdk iphonesimulator -configuration Debug \
  -destination "platform=iOS Simulator,name=${SIM_NAME}" \
  -derivedDataPath "$DD" -allowProvisioningUpdates build | tail -4

APP="$DD/Build/Products/Debug-iphonesimulator/MCATSpeedrun.app"

echo "==> Launching on ${SIM_NAME}"
open -a Simulator
xcrun simctl bootstatus "${SIM_NAME}" -b >/dev/null 2>&1 || true
xcrun simctl install "${SIM_NAME}" "$APP"
xcrun simctl launch "${SIM_NAME}" com.mcatspeedrun.app
echo "==> Launched com.mcatspeedrun.app"
