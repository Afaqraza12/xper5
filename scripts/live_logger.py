#!/usr/bin/env python3
import subprocess
import sys
import os
import time

log_path = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else 'live_kernel.log')
print(f"[*] Live kernel logger active: streaming to {log_path} ...", flush=True)

with open(log_path, 'a', encoding='utf-8', buffering=1) as log_file:
    log_file.write(f"\n=== Live Kernel Logger Started at {time.strftime('%Y-%m-%d %H:%M:%S')} ===\n")
    log_file.flush()
    while True:
        res = subprocess.run(['adb', 'get-state'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if 'device' not in res.stdout:
            time.sleep(1)
            continue
        
        cmd = 'adb shell "/data/local/tmp/su -c \'dmesg -w\' 2>/dev/null"'
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, shell=True)
        try:
            for line in proc.stdout:
                log_file.write(line)
                log_file.flush()
        except Exception:
            pass
        time.sleep(2)
