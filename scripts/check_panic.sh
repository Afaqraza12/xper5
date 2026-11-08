#!/usr/bin/env bash
set -e

echo "=== Extracting Kernel Panic Log from /sys/fs/pstore/ ==="

if ! adb shell "/data/local/tmp/su -c id" 2>/dev/null | grep -q "uid=0"; then
    echo "[-] Root not active. Running deploy_sog05.sh first..."
    bash "$(dirname "$0")/deploy_sog05.sh"
fi

echo "[*] Listing /sys/fs/pstore files:"
adb shell "/data/local/tmp/su -c 'ls -la /sys/fs/pstore/'" || true

echo "[*] Dumping latest panic log:"
adb shell "/data/local/tmp/su -c 'cat /sys/fs/pstore/console-ramoops-0 2>/dev/null || cat /sys/fs/pstore/console-ramoops 2>/dev/null || cat /sys/fs/pstore/dmesg-ramoops-0 2>/dev/null'" > kernel_panic.log

if [ -s kernel_panic.log ]; then
    echo "[+] SUCCESS! Dumped panic log to kernel_panic.log:"
    tail -n 60 kernel_panic.log
else
    echo "[-] No pstore panic file found or empty."
fi
