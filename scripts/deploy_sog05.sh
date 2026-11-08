#!/usr/bin/env bash
# deploy_sog05.sh - One-click deployment & test runner for Sony Xperia 5 III (SOG05)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPLOIT_BIN="$REPO_ROOT/exploit/build/sog05-5.4.210/bin/exploit_static"
BIN_DIR="$SCRIPT_DIR/bin"

echo "=================================================="
echo " GhostLock 5.4 Xperia (SOG05) Auto-Deploy & Root "
echo "=================================================="

# 1. Check ADB connection
echo "[1/6] Checking ADB device connection..."
if ! command -v adb >/dev/null 2>&1; then
    echo "[-] Error: 'adb' command not found in PATH."
    exit 1
fi

DEVICE_STATUS=$(adb get-state 2>/dev/null || true)
if [ "$DEVICE_STATUS" != "device" ]; then
    echo "[-] Error: No authorized ADB device found. Please enable USB debugging."
    adb devices
    exit 1
fi
echo "[+] Device connected: $(adb shell getprop ro.product.model 2>/dev/null || echo 'Android Device')"

# 2. Check for exploit binary
echo "[2/6] Checking exploit binary..."
if [ ! -f "$EXPLOIT_BIN" ]; then
    echo "[-] Exploit binary not found at $EXPLOIT_BIN"
    echo "[*] Attempting local build with make..."
    if [ -n "$ANDROID_NDK_ROOT" ] || [ -n "$NDK_ROOT" ]; then
        make -C "$REPO_ROOT/exploit" PROJECT=sog05-5.4.210 -j4 bin
    else
        echo "[-] Please build the binary first or set NDK_ROOT."
        echo "    Example: make -C exploit PROJECT=sog05-5.4.210 NDK_ROOT=/path/to/ndk bin"
        exit 1
    fi
fi

# 3. Check / Fetch Magisk files
echo "[3/6] Verifying Magisk in-RAM binaries..."
if [ ! -f "$BIN_DIR/magisk" ] || [ ! -f "$BIN_DIR/magiskpolicy" ]; then
    echo "[*] Fetching Magisk binaries..."
    bash "$SCRIPT_DIR/get_magisk.sh"
fi

# 4. Push payload to device
echo "[4/6] Pushing payload to /data/local/tmp..."
adb push "$EXPLOIT_BIN" /data/local/tmp/gl
adb push "$BIN_DIR/magisk" /data/local/tmp/magisk
adb push "$BIN_DIR/magiskpolicy" /data/local/tmp/magiskpolicy
adb push "$SCRIPT_DIR/post_exploit.sh" /data/local/tmp/post_exploit.sh

adb shell "chmod 755 /data/local/tmp/gl /data/local/tmp/magisk /data/local/tmp/magiskpolicy /data/local/tmp/post_exploit.sh"

# Install Magisk Manager APK if available and not installed
if [ -f "$BIN_DIR/Magisk.apk" ]; then
    if ! adb shell pm list packages | grep -q "com.topjohnwu.magisk"; then
        echo "[*] Installing Magisk Manager app on device..."
        adb install -r "$BIN_DIR/Magisk.apk" || true
    fi
fi

# 5. Run the exploit
echo "[5/6] Triggering GhostLock kernel exploit..."
echo "[*] Running /data/local/tmp/gl (device may take a few moments)..."
adb shell "/data/local/tmp/gl"

# Give post-exploit hook a couple of seconds to finish
sleep 2

# 6. Check results and pull dump
echo "[6/6] Verifying root status..."
if adb shell "/data/local/tmp/su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[SUCCESS] Root access confirmed via /data/local/tmp/su!"
    
    # Check Magisk daemon
    if adb shell "/data/local/tmp/su -c ps -A" 2>/dev/null | grep -q "magiskd"; then
        echo "[SUCCESS] Magisk daemon is running in RAM!"
    fi

    # Display post-exploit log
    echo "--- Post-Exploit Log ---"
    adb shell "cat /data/local/tmp/post_exploit.log 2>/dev/null" || true
    echo "------------------------"

    # Pull system dumps if created
    OUTPUT_DUMP="$REPO_ROOT/dumps_$(date +%Y%m%d_%H%M%S)"
    echo "[*] Pulling partition and system dumps to $OUTPUT_DUMP..."
    adb pull /data/local/tmp/xperia_dump "$OUTPUT_DUMP" 2>/dev/null || true
    echo "[+] Done! Full root active until next reboot."
else
    echo "[-] Exploit run did not yield uid=0. If device rebooted, run again."
fi
