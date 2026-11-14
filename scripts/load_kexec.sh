#!/usr/bin/env bash
# load_kexec.sh - Dynamic KASLR-aware loader for kexec modules
# Mirrors scripts/load_ksu.sh exactly for full kernel stability
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=== Loading Kexec LKM for Sony Xperia 5 III (SOG05) ==="

MOD_DIR="${WORKSPACE_DIR}/5.4-custom-kernel/cfi_build"
if [ ! -f "${MOD_DIR}/kexec_mod_arm64.ko" ] || [ ! -f "${MOD_DIR}/kexec_mod.ko" ]; then
    echo "[-] Error: kexec modules not found in ${MOD_DIR}!"
    exit 1
fi

echo "[*] Checking temporary root status..."
if ! adb shell "su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[-] Root is not active!"
    exit 1
fi

echo "[*] Leaking current boot KASLR text base via hardware perf counter..."
LEAK_OUTPUT=$(adb shell "DIAG_LEAK_ONLY=1 /data/local/tmp/gl" 2>/dev/null || true)
LIVE_TEXT_BASE=$(echo "$LEAK_OUTPUT" | grep -o 'text_base=[0-9a-fA-F]*' | cut -d= -f2 || true)

if [ -n "$LIVE_TEXT_BASE" ]; then
    echo "[+] Live kernel text_base detected: 0x${LIVE_TEXT_BASE}"
    KALLSYMS_PATH="${WORKSPACE_DIR}/kallsyms.txt"
    if [ ! -f "$KALLSYMS_PATH" ] && [ -f "${WORKSPACE_DIR}/kallsyms.gz" ]; then
        KALLSYMS_PATH="${WORKSPACE_DIR}/kallsyms.gz"
    fi

    echo "[*] Resolving live symbols for kexec_mod_arm64.ko..."
    python3 "${WORKSPACE_DIR}/scripts/resolve_symbols.py" \
        "${MOD_DIR}/kexec_mod_arm64.ko" \
        "$KALLSYMS_PATH" \
        "${WORKSPACE_DIR}/Module.symvers" \
        "0x${LIVE_TEXT_BASE}"

    echo "[*] Resolving live symbols for kexec_mod.ko..."
    python3 "${WORKSPACE_DIR}/scripts/resolve_symbols.py" \
        "${MOD_DIR}/kexec_mod.ko" \
        "$KALLSYMS_PATH" \
        "${WORKSPACE_DIR}/Module.symvers" \
        "0x${LIVE_TEXT_BASE}"
else
    echo "[-] Error: Failed to leak live KASLR text_base via DIAG_LEAK_ONLY!"
    exit 1
fi

echo "[*] Transferring dynamically adapted modules to /data/kexec/..."
adb push "${MOD_DIR}/kexec_mod_arm64.ko" /data/local/tmp/kexec_mod_arm64.ko
adb push "${MOD_DIR}/kexec_mod.ko" /data/local/tmp/kexec_mod.ko
adb shell "su -c 'mv /data/local/tmp/kexec_mod_arm64.ko /data/kexec/kexec_mod_arm64.ko && mv /data/local/tmp/kexec_mod.ko /data/kexec/kexec_mod.ko && chmod 644 /data/kexec/kexec_mod*.ko'"

echo "[*] Inserting kexec_mod_arm64.ko into live kernel..."
adb shell "su -c 'insmod /data/kexec/kexec_mod_arm64.ko'" 2>&1 || true

echo "[*] Inserting kexec_mod.ko into live kernel..."
adb shell "su -c 'insmod /data/kexec/kexec_mod.ko'" 2>&1 || true

echo "[*] Checking loaded modules:"
adb shell "su -c 'lsmod | grep kexec || true'"

echo "[*] Verifying /dev/kexec and /sys/kernel/kexec_loaded..."
adb shell "su -c 'ls -la /dev/kexec /sys/kernel/kexec_loaded 2>/dev/null || true'"

echo "=========================================================="
echo "[+] Kexec module load procedure completed."
