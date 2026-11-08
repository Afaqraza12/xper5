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

echo "[*] Leaking current boot KASLR text base via hardware perf counter..."
LEAK_OUTPUT=$(adb shell "DIAG_LEAK_ONLY=1 /data/local/tmp/gl" 2>/dev/null || true)
LIVE_TEXT_BASE=$(echo "$LEAK_OUTPUT" | grep -o 'text_base=[0-9a-fA-F]*' | cut -d= -f2 || true)

if [ -n "$LIVE_TEXT_BASE" ]; then
    echo "[+] Live kernel text_base detected: 0x${LIVE_TEXT_BASE}"
    python3 "${WORKSPACE_DIR}/scripts/resolve_symbols.py" \
        "${WORKSPACE_DIR}/kernelsu.ko" \
        "${WORKSPACE_DIR}/kallsyms.txt" \
        "${WORKSPACE_DIR}/Module.symvers" \
        "0x${LIVE_TEXT_BASE}"
else
    echo "[-] Error: Failed to leak live KASLR text_base via DIAG_LEAK_ONLY!"
    exit 1
fi

echo "[*] Transferring dynamically adapted kernelsu.ko to /data/local/tmp/..."
adb push "${WORKSPACE_DIR}/kernelsu.ko" /data/local/tmp/kernelsu.ko

echo "[*] Starting real-time dmesg capture to live_kernel.log..."
adb shell "/data/local/tmp/su -c 'dmesg -w'" > "${WORKSPACE_DIR}/live_kernel.log" 2>&1 &
LOGGER_PID=$!
sleep 1

echo "[*] Inserting module into live kernel..."
adb shell "/data/local/tmp/su -c 'insmod /data/local/tmp/kernelsu.ko'" 2>&1 || true

sleep 2
kill $LOGGER_PID 2>/dev/null || true

echo "[*] Verifying module in live kernel..."
MODULE_STATUS=$(adb shell "/data/local/tmp/su -c 'cat /proc/modules'" 2>/dev/null | grep -i "kernelsu" || true)

if [ -n "$MODULE_STATUS" ]; then
    echo "[+] Found loaded module: $MODULE_STATUS"
    echo "[*] Auto-crowning manager app (ReSukiSU / OriginSU / KernelSU)..."
    for pkg in com.resukisu.resukisu com.originsu.manager me.weishu.kernelsu; do
        M_LINE=$(adb shell "/data/local/tmp/su -c 'grep -m1 ^$pkg\  /data/system/packages.list 2>/dev/null'" 2>/dev/null || true)
        M_UID=$(echo "$M_LINE" | awk '{print $2}')
        if [ -n "$M_UID" ]; then
            echo "[+] Detected $pkg (UID $M_UID), crowning as manager in kernel..."
            adb shell "/data/local/tmp/su -c 'echo $M_UID > /sys/module/kernelsu/parameters/ksu_debug_manager_appid'"
            break
        fi
    done
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

