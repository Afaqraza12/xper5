#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Loading KernelSU LKM for Sony Xperia 5 III (SOG05) ==="

if [ ! -f "${WORKSPACE_DIR}/kernelsu.ko" ]; then
    echo "[-] Error: kernelsu.ko not found in workspace!"
    exit 1
fi

echo "[*] Checking temporary root status..."
if ! adb shell "/data/local/tmp/su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[-] Temporary root is not active! Running deploy_sog05.sh first..."
    bash "${SCRIPT_DIR}/deploy_sog05.sh"
fi

echo "[*] Dumping live kernel symbol table from /proc/kallsyms..."
adb shell "/data/local/tmp/su -c 'cat /proc/kallsyms'" > "${WORKSPACE_DIR}/live_kallsyms.txt"

if ! grep -q -v "0000000000000000" "${WORKSPACE_DIR}/live_kallsyms.txt" 2>/dev/null; then
    echo "[-] Warning: live_kallsyms.txt seems masked or empty! Checking..."
fi

echo "[*] Dynamically resolving symbols for current boot KASLR slide..."
python3 "${WORKSPACE_DIR}/scripts/resolve_symbols.py" \
    "${WORKSPACE_DIR}/kernelsu.ko" \
    "${WORKSPACE_DIR}/live_kallsyms.txt" \
    "${WORKSPACE_DIR}/Module.symvers"

echo "[*] Transferring dynamically adapted kernelsu.ko to /data/local/tmp/..."
adb push "${WORKSPACE_DIR}/kernelsu.ko" /data/local/tmp/kernelsu.ko

echo "[*] Inserting module into live kernel..."
adb shell "/data/local/tmp/su -c 'insmod /data/local/tmp/kernelsu.ko'" 2>&1 || true

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

