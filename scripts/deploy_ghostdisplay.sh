#!/bin/bash
# GhostDisplay Auto-Deployer for Sony Xperia 5 III (SOG05 / pdx214)

echo "=========================================================="
echo "    GHOSTDISPLAY AUTO-DEPLOYER (XPERIA 5 III pdx214)     "
echo "=========================================================="
echo "[*] Waiting for device connection over USB..."

adb wait-for-device
echo "[+] Device detected!"

echo "[*] Verifying root authorization..."
ROOT_CHECK=$(adb shell "su -c id" 2>/dev/null)
if [[ "$ROOT_CHECK" != *"uid=0"* ]]; then
    echo "[-] Root authorization failed or not active. Please grant root in KernelSU."
    exit 1
fi
echo "[+] Root confirmed: $ROOT_CHECK"

# Locate loader.apk
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/loader.apk" ]; then
    LOADER_SRC="$SCRIPT_DIR/loader.apk"
elif [ -f "/tmp/deb_extract/data/data/com.termux/files/usr/libexec/termux-x11/loader.apk" ]; then
    LOADER_SRC="/tmp/deb_extract/data/data/com.termux/files/usr/libexec/termux-x11/loader.apk"
else
    echo "[*] Extracting loader.apk from deb package..."
    mkdir -p /tmp/deb_extract
    cd /tmp/deb_extract && ar -x /tmp/termux-x11.deb && tar -xf data.tar.xz
    LOADER_SRC="/tmp/deb_extract/data/data/com.termux/files/usr/libexec/termux-x11/loader.apk"
fi

echo "[*] Pushing display bridge binaries, configs & scripts to device..."
adb push "$LOADER_SRC" /data/local/tmp/loader.apk
[ -f /tmp/xkb.tar.gz ] && adb push /tmp/xkb.tar.gz /data/local/tmp/xkb.tar.gz
adb push "$SCRIPT_DIR/setup_ghostdisplay.sh" /data/local/tmp/setup_ghostdisplay.sh
adb push "$SCRIPT_DIR/openbox_menu.xml" /data/local/tmp/openbox_menu.xml
adb push "$SCRIPT_DIR/tint2rc" /data/local/tmp/tint2rc
adb push "$SCRIPT_DIR/banner.sh" /data/local/tmp/banner.sh
adb push "$SCRIPT_DIR/start_desktop.sh" /data/local/tmp/start_desktop.sh

echo "[*] Configuring GPU display server..."
adb shell "su -c 'sh /data/local/tmp/setup_ghostdisplay.sh'"

echo "[*] Initializing GhostDisplay on phone screen..."
adb shell "su -c ghostdisplay"

echo ""
echo "=========================================================="
echo "   [+] GHOSTDISPLAY IS LIVE ON YOUR PHONE SCREEN!         "
echo "   Look at your Xperia 5 III display right now!           "
echo "=========================================================="
