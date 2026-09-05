#!/usr/bin/env bash
set -euo pipefail

# Builds Vendor/idevice's IDevice.xcframework for aarch64-apple-ios only.
#
# We only ever run this on a physical iOS device - there's no reason to pay
# for the simulator/Catalyst/macOS slices idevice's own `just xcframework`
# recipe also builds; those platforms already have Xcode and real VS Code.
# macOS only (cross-compiles Rust for an Apple target, then runs
# `xcodebuild -create-xcframework`).

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDEVICE_DIR="$REPO_ROOT/Vendor/idevice"

cd "$IDEVICE_DIR"

rustup target add aarch64-apple-ios

(
  cd ffi
  BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$(xcrun --sdk iphoneos --show-sdk-path)" \
    IPHONEOS_DEPLOYMENT_TARGET=17.0 \
    cargo build --release --target aarch64-apple-ios --features obfuscate
)

# ffi/build.rs regenerates ffi/idevice.h (via cbindgen) as part of the
# cargo build above; copy it where the Swift package's module map expects it.
cp ffi/idevice.h swift/include/idevice.h

rm -rf swift/IDevice.xcframework
xcodebuild -create-xcframework \
  -library target/aarch64-apple-ios/release/libidevice_ffi.a -headers swift/include \
  -output swift/IDevice.xcframework

echo "Built $IDEVICE_DIR/swift/IDevice.xcframework (aarch64-apple-ios only)"
