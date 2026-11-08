#!/usr/bin/env bash
# get_magisk.sh - Downloads and extracts official Magisk arm64 binaries
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"
mkdir -p "$BIN_DIR"

MAGISK_VER="v27.0"
MAGISK_URL="https://github.com/topjohnwu/Magisk/releases/download/${MAGISK_VER}/Magisk-${MAGISK_VER}.apk"

if [ -f "$BIN_DIR/magisk" ] && [ -f "$BIN_DIR/magiskpolicy" ]; then
    echo "[+] Magisk binaries already present in $BIN_DIR"
    exit 0
fi

echo "[*] Downloading Magisk ${MAGISK_VER}..."
curl -L -o "$BIN_DIR/Magisk.apk" "$MAGISK_URL"

echo "[*] Extracting arm64 binaries from APK..."
unzip -o -q "$BIN_DIR/Magisk.apk" "lib/arm64-v8a/*" -d "$BIN_DIR"

mv "$BIN_DIR/lib/arm64-v8a/libmagisk.so" "$BIN_DIR/magisk"
mv "$BIN_DIR/lib/arm64-v8a/libmagiskpolicy.so" "$BIN_DIR/magiskpolicy"
[ -f "$BIN_DIR/lib/arm64-v8a/libmagiskboot.so" ] && mv "$BIN_DIR/lib/arm64-v8a/libmagiskboot.so" "$BIN_DIR/magiskboot"

chmod +x "$BIN_DIR/magisk" "$BIN_DIR/magiskpolicy"
rm -rf "$BIN_DIR/lib"

echo "[+] Done! Magisk binaries extracted to $BIN_DIR:"
ls -lh "$BIN_DIR"
