#!/bin/zsh
# Device build + install wrapper for xtool 1.16.x + Xcode 26.5.
#
# Xcode 26.5's SwiftPM compiles via the new Swift Build system, which puts
# products in .build/out/Products/Debug-iphoneos/. xtool still packages the
# executable and resource bundles from the legacy SwiftPM layout at
# .build/arm64-apple-ios/debug/, so without this sync step every install
# ships whatever binary was last built with the OLD toolchain (verified
# 2026-06-09: devices were running May 23 code). Raw `xtool dev build` /
# `xtool dev run` are NOT safe on their own.
#
# Two passes: pass 1 compiles fresh products (its packaging may be stale or
# fail on a clean checkout — ignored), the sync copies products into the
# legacy path, pass 2 repackages instantly from the synced files. The fresh
# ipa is then installed on the connected device.
#
# Usage: scripts/xtool-build.sh [--no-install]
set -e
cd "$(dirname "$0")/.."

INSTALL=1
ARGS=()
for a in "$@"; do
    if [[ "$a" == "--no-install" ]]; then INSTALL=0; else ARGS+=("$a"); fi
done

PRODUCTS=".build/out/Products/Debug-iphoneos"
LEGACY=".build/arm64-apple-ios/debug"

xtool dev build --ipa "${ARGS[@]}" || true   # pass 1: compile; stale/failed packaging tolerated

[[ -f "$PRODUCTS/Tanuki-App" ]] || { echo "✗ no build product — compile failed"; exit 1; }
mkdir -p "$LEGACY"
cp -f "$PRODUCTS/Tanuki-App" "$LEGACY/Tanuki-App"
for b in GRDB_GRDB.bundle Kingfisher_Kingfisher.bundle; do
    rm -rf "$LEGACY/$b"
    cp -R "$PRODUCTS/$b" "$LEGACY/$b"
done

xtool dev build --ipa "${ARGS[@]}"           # pass 2: incremental no-op compile + fresh packaging

cmp -s "$PRODUCTS/Tanuki-App" "$LEGACY/Tanuki-App" \
    && echo "✓ packaged from fresh build product" \
    || { echo "✗ packaging input is stale — do not install"; exit 1; }

[[ $INSTALL == 1 ]] || exit 0
if xtool install xtool/Tanuki.ipa; then
    echo "✓ installed on device"
else
    echo "✗ install failed — is the device connected and unlocked? Fresh ipa is at xtool/Tanuki.ipa"
fi
