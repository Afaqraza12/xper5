#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Loading KernelSU LKM for Sony Xperia 5 III (SOG05) ==="

if [ ! -f "${WORKSPACE_DIR}/kernelsu.ko" ]; then
    echo "[-] Error: kernelsu.ko not found in workspace!"
    exit 1
fi

echo "[*] Transferring kernelsu.ko to /data/local/tmp/..."
adb push "${WORKSPACE_DIR}/kernelsu.ko" /data/local/tmp/kernelsu.ko

echo "[*] Inserting module into live kernel..."
adb shell "/data/local/tmp/su -c 'insmod /data/local/tmp/kernelsu.ko'" 2>&1 || adb shell "/system/bin/su -c 'insmod /data/local/tmp/kernelsu.ko'" 2>&1 || true

echo "[*] Verifying module in live kernel..."
MODULE_STATUS=$(adb shell "/data/local/tmp/su -c 'cat /proc/modules'" 2>/dev/null | grep -i "kernelsu" || true)

if [ -n "$MODULE_STATUS" ]; then
    echo "[+] Found loaded module: $MODULE_STATUS"
    echo "[*] Checking KernelSU kernel initialization logs:"
    adb shell "/data/local/tmp/su -c 'dmesg | grep -i kernelsu | tail -n 20'" 2>/dev/null || true
    echo "=========================================================="
    echo "[+] SUCCESS! KernelSU is loaded into the kernel."
    echo "[+] You can now open ReSukiSU on your phone to manage root permissions."
else
    echo "[-] insmod failed! Module is not present in /proc/modules."
    echo "[*] Checking dmesg for kernel diagnostic logs:"
    adb shell "/data/local/tmp/su -c 'dmesg | grep -i -E \"(kernelsu|module)\" | tail -n 25'" 2>/dev/null || adb shell "dmesg | grep -i -E '(kernelsu|module)' | tail -n 25" || true
    exit 1
fi

