# ghostlock_5.4_xperia (Sony Xperia 5 III - SOG05)

Temporary root for Sony Xperia 5 III (SOG05) 5.4 kernels, based on GhostLock
(CVE-2026-43499). Includes a persistent `su` daemon.

## Supported device

| Kernel | Device | Firmware Build |
| --- | --- | --- |
| `5.4.210-qgki-g55a0c74ba38a` | Sony Xperia 5 III (SOG05) | KDDI 61.2.D.0.153 |

## Build and run

```sh
# Build static binary for SOG05
make -C exploit NDK_ROOT="$NDK" -j4 bin

# Push and run via adb
adb push exploit/build/sog05-5.4.210/bin/exploit_static /data/local/tmp/gl
adb shell 'chmod 755 /data/local/tmp/gl; /data/local/tmp/gl'
```

Reboot clears root. A failed attempt may reboot the device; rerun.

## su

The exploit creates `/data/local/tmp/su` and starts a root daemon once the
anchor has root and SELinux is permissive:

```sh
/data/local/tmp/su
/data/local/tmp/su -c id
```

See [README_origin.md](README_origin.md) for the original project notes and
[LICENSE](LICENSE) for the terms.
