#!/bin/sh
# package_gvu_universal.sh — assemble GVU files for the spruceOS Emu/MEDIA package
#
# Usage:  sh cross-compile/universal/package_gvu_universal.sh [VERSION]
# Output: gvu_spruce_universal_v<VERSION>.zip  (in the project root)
#
# The zip extracts to Emu/MEDIA/ so users can unzip directly to SD card root.
# Only GVU-owned files are included — the emu config.json, launcher scripts,
# and ffplay/mpv binaries are managed by the spruceOS repo.
#
# Requires: build/gvu32, build/gvu64, build/fetch_subs32, build/fetch_subs64
#           build/libs32/, build/libs32_a30/, build/libs64/
#           resources/ directory

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

VERSION="${1:-dev}"
# Strip a leading 'v' so we don't double it when the caller passes a git tag
# like "v0.2.2" (result: gvu_spruce_universal_v0.2.2.zip)
VERSION="${VERSION#v}"
OUT_ZIP="$REPO_ROOT/gvu_spruce_universal_v${VERSION}.zip"
STAGE="$REPO_ROOT/build/universal-stage"
EMU="$STAGE/Emu/MEDIA"

echo "=== Packaging GVU universal ${VERSION} (emu mode) ==="

# Clean and recreate staging area
# Zip contains Emu/MEDIA/... so users extract directly to SD card root
rm -rf "$STAGE"
mkdir -p "$EMU/bin32"
mkdir -p "$EMU/bin64"
mkdir -p "$EMU/gvu_lib32"
mkdir -p "$EMU/gvu_lib32_a30"
mkdir -p "$EMU/gvu_lib64"
mkdir -p "$EMU/resources"

# Binaries
cp "$REPO_ROOT/build/gvu32"  "$EMU/bin32/gvu"
cp "$REPO_ROOT/build/gvu64"  "$EMU/bin64/gvu"
cp "$REPO_ROOT/build/fetch_subs32" "$EMU/bin32/fetch_subs"
cp "$REPO_ROOT/build/fetch_subs64" "$EMU/bin64/fetch_subs"
chmod +x "$EMU/bin32/gvu" "$EMU/bin64/gvu" \
         "$EMU/bin32/fetch_subs" "$EMU/bin64/fetch_subs"

# GVU-specific shared libraries
# gvu_lib32/     — SDL2 + zlib for MiyooMini family (glibc 2.28+)
# gvu_lib32_a30/ — VERNEED-patched SDL2 for A30 (glibc 2.23)
# gvu_lib64/     — aarch64 libs for Brick/Flip/Smart Pro
if [ -d "$REPO_ROOT/build/libs32" ]; then
    cp "$REPO_ROOT/build/libs32/"*.so* "$EMU/gvu_lib32/" 2>/dev/null || true
fi
if [ -d "$REPO_ROOT/build/libs32_a30" ]; then
    cp "$REPO_ROOT/build/libs32_a30/"*.so* "$EMU/gvu_lib32_a30/" 2>/dev/null || true
fi
if [ -d "$REPO_ROOT/build/libs64" ]; then
    cp "$REPO_ROOT/build/libs64/"*.so* "$EMU/gvu_lib64/" 2>/dev/null || true
fi

# Resources (fonts, icons, certs, helper scripts)
cp -r "$REPO_ROOT/resources/." "$EMU/resources/"

# Create zip — contents: Emu/MEDIA/...
cd "$STAGE"
rm -f "$OUT_ZIP"
zip -r "$OUT_ZIP" Emu/
echo "=== Created: $OUT_ZIP ==="
ls -lh "$OUT_ZIP"
