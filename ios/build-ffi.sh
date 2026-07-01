#!/usr/bin/env bash
# Build the shared Rust engine (mcat-ffi -> rslib/mcat_core) into
# mcat_ffi.xcframework for the SwiftUI app.
#
# By default only the iOS Simulator slice is built (fast, for local dev). Pass
# `--device` to also build the arm64 device slice for a real device / App Store.
#
# Usage: ios/build-ffi.sh [--device]
set -euo pipefail

cd "$(dirname "$0")/mcat-ffi"
# Local target dir so the sandbox doesn't redirect it somewhere transient.
export CARGO_TARGET_DIR="$PWD/target"

SIM_TARGET="aarch64-apple-ios-sim"
DEV_TARGET="aarch64-apple-ios"
WITH_DEVICE="${1:-}"

rustup target add "$SIM_TARGET" >/dev/null 2>&1 || true
echo "==> Building mcat-ffi for the simulator ($SIM_TARGET)"
cargo build --release --target "$SIM_TARGET"

ARGS=(-library "target/$SIM_TARGET/release/libmcat_ffi.a" -headers include)

if [ "$WITH_DEVICE" = "--device" ]; then
  rustup target add "$DEV_TARGET" >/dev/null 2>&1 || true
  echo "==> Building mcat-ffi for the device ($DEV_TARGET)"
  cargo build --release --target "$DEV_TARGET"
  ARGS+=(-library "target/$DEV_TARGET/release/libmcat_ffi.a" -headers include)
fi

OUT="../MCATSpeedrun/mcat_ffi.xcframework"
echo "==> Assembling $OUT"
rm -rf "$OUT"
xcodebuild -create-xcframework "${ARGS[@]}" -output "$OUT"
echo "==> Done: $OUT"
