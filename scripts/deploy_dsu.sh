#!/bin/bash
# ==============================================================================
# GHOSTBOOT DSU: BARE-METAL DYNAMIC SYSTEM UPDATES DEPLOYER
# Sony Xperia 5 III (pdx214 / SOG05) - Snapdragon 888
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING_DIR="$DIR/dsu_staging"
SYSTEM_IMG="$STAGING_DIR/system.img"
REMOTE_TMP="/data/local/tmp/system.raw.img"

echo "=========================================================="
echo "    GHOSTBOOT DSU DEPLOYER (XPERIA 5 III pdx214)         "
echo "=========================================================="

# 1. Device check
echo "[*] Verifying ADB connection..."
DEVICE=$(adb devices | grep -w "device" | awk '{print $1}' | head -n 1)
if [ -z "$DEVICE" ]; then
    echo "[-] Error: No ADB device found in 'device' state."
    exit 1
fi
echo "[+] Target device connected: $DEVICE"

# 2. Root check
echo "[*] Checking root authorization..."
ROOT_CHECK=$(adb shell "su -c id" 2>&1)
if [[ "$ROOT_CHECK" != *"uid=0"* ]]; then
    echo "[-] Error: Root authorization failed: $ROOT_CHECK"
    exit 1
fi
echo "[+] Root confirmed: $ROOT_CHECK"

# 3. Storage check on /data
echo "[*] Checking storage capacity on /data..."
AVAIL_KB=$(adb shell "su -c 'df -P /data | tail -n 1'" | awk '{print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
echo "[+] Available storage on /data: ${AVAIL_GB} GB"
if [ "$AVAIL_GB" -lt 15 ]; then
    echo "[-] Warning: Storage is tight (needs at least 15 GB for GSI + Userdata)."
    exit 1
fi

if [ ! -f "$SYSTEM_IMG" ]; then
    echo "[-] Error: system.img not found at $SYSTEM_IMG!"
    exit 1
fi

RAW_SIZE=$(stat -f %z "$SYSTEM_IMG" 2>/dev/null || stat -c %s "$SYSTEM_IMG")
echo "[+] Raw GSI System Size: $RAW_SIZE bytes ($((RAW_SIZE / 1024 / 1024)) MB)"

# 4. Service initialization
echo "[*] Initializing Android gsid service..."
adb shell "su -c 'start gsid && sleep 1'"
GSID_STATUS=$(adb shell "service check gsiservice")
echo "[+] $GSID_STATUS"

# 5. Clean stale DSU installation
echo "[*] Cleaning any stale DSU installation..."
adb shell "su -c 'gsi_tool wipe 2>/dev/null || true'"

# 6. Push raw system image to device tmp
echo "[*] Transferring raw system image to device ($((RAW_SIZE / 1024 / 1024)) MB)..."
adb push "$SYSTEM_IMG" "$REMOTE_TMP"

# 7. Userdata allocation (8 GiB = 8589934592 bytes)
USERDATA_SIZE=8589934592
echo "[*] Userdata size: 8 GiB ($USERDATA_SIZE bytes)"

# 8. Install via gsi_tool
echo "[*] Installing GSI into dynamic DSU partition on device..."
adb shell "su -c 'gsi_tool install --gsi-size $RAW_SIZE --userdata-size $USERDATA_SIZE --wipe < $REMOTE_TMP'"

# 9. Clean up temporary push
echo "[*] Cleaning up temporary image from /data/local/tmp..."
adb shell "su -c 'rm -f $REMOTE_TMP'"

# 10. Enable single-boot
echo "[*] Configuring one-shot single boot (-s)..."
adb shell "su -c 'gsi_tool enable -s'"

# 11. Final verification
STATUS=$(adb shell "su -c 'gsi_tool status'")
echo "=========================================================="
echo "    GHOSTBOOT DSU PROVISIONING STATUS: $STATUS           "
echo "=========================================================="

if [[ "$STATUS" == *"installed"* || "$STATUS" == *"running"* || "$STATUS" == *"single-boot"* ]]; then
    echo "[+] SUCCESS: Android 12 GSI is staged and armed for boot!"
    echo "[*] Mode: Single-Boot (Automatic fallback to stock Android 13 if rebooted)"
    echo "[*] To boot into native Android 12 now, execute:"
    echo "      adb reboot"
else
    echo "[*] Status output: $STATUS"
fi
