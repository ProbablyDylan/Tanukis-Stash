#!/bin/zsh
# Device build wrapper for xtool 1.16.x + Xcode 26.5.
#
# Xcode 26.5's SwiftPM compiles via the new Swift Build system, which puts
# products in .build/out/Products/Debug-iphoneos/. xtool still packages the
# executable and resource bundles from the legacy SwiftPM layout at
# .build/arm64-apple-ios/debug/, so without this sync step every install
# ships whatever binary was last built with the OLD toolchain (verified
# 2026-06-09: devices were running May 23 code).
#
# Two passes: pass 1 compiles fresh products (its packaging may be stale or
# fail on a clean checkout — ignored), the sync copies products into the
# legacy path, pass 2 repackages instantly from the synced files.
#
# Usage: scripts/xtool-build.sh [--ipa]   (then `xtool install xtool/Tanuki.ipa`
#        or `xtool dev run` as usual — packaging stays fresh until the next
#        source change)
set -e
cd "$(dirname "$0")/.."

PRODUCTS=".build/out/Products/Debug-iphoneos"
LEGACY=".build/arm64-apple-ios/debug"

xtool dev build "$@" || true   # pass 1: compile; stale/failed packaging tolerated

[[ -f "$PRODUCTS/Tanuki-App" ]] || { echo "✗ no build product — compile failed"; exit 1; }
mkdir -p "$LEGACY"
cp -f "$PRODUCTS/Tanuki-App" "$LEGACY/Tanuki-App"
for b in GRDB_GRDB.bundle Kingfisher_Kingfisher.bundle; do
    rm -rf "$LEGACY/$b"
    cp -R "$PRODUCTS/$b" "$LEGACY/$b"
done

xtool dev build "$@"           # pass 2: incremental no-op compile + fresh packaging

cmp -s "$PRODUCTS/Tanuki-App" "$LEGACY/Tanuki-App" \
    && echo "✓ packaged from fresh build product" \
    || { echo "✗ packaging input is stale — do not install"; exit 1; }
