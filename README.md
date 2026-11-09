# GhostLock SOG05 — KernelSU-Next LKM & One-Click Root

[![Build SOG05 one-click APK](https://github.com/Afaqraza12/xper5/actions/workflows/build-apk.yml/badge.svg)](https://github.com/Afaqraza12/xper5/actions/workflows/build-apk.yml)
[![Build KernelSU LKM (5.4)](https://github.com/Afaqraza12/xper5/actions/workflows/build-ksu.yml/badge.svg)](https://github.com/Afaqraza12/xper5/actions/workflows/build-ksu.yml)
[![Build exploit](https://github.com/Afaqraza12/xper5/actions/workflows/build.yml/badge.svg)](https://github.com/Afaqraza12/xper5/actions/workflows/build.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPL%20v2-blue.svg)](LICENSE)
[![Platform: Android 13](https://img.shields.io/badge/Android-13%20(Tiramisu)-green.svg)]()
[![Kernel: 5.4.210-qgki](https://img.shields.io/badge/Kernel-5.4.210--qgki-orange.svg)]()

> Fully autonomous, pure **KernelSU-Next** loadable kernel module (LKM) root solution and **standalone on-device 1-Click APK loader** for the **Sony Xperia 5 III (SOG05 / pdx214)** on Android 13 without requiring bootloader unlocking or a PC after reboot.

---

## 📱 Target Specifications

| Parameter | Specification |
| :--- | :--- |
| **Device Model** | Sony Xperia 5 III (`SOG05` / `pdx214` / `SO-53B` / `XQ-BQ42`) |
| **SoC** | Qualcomm Snapdragon 888 5G (`SM8350` / `lahaina`) |
| **Firmware Build** | KDDI `61.2.D.0.153` (Android 13) |
| **Stock Kernel** | `5.4.210-qgki-g55a0c74ba38a` (`aarch64`) |
| **KernelSU Version** | KernelSU-Next `v4.1.0` (Code `34678`) |
| **Supported Managers** | [ReSukiSU / BakaSU](https://github.com/resukisu/resukisu) (`com.resukisu.resukisu`), OriginSU, KernelSU |

---

## ✨ Features & Breakthroughs

- ⚡ **100% On-Device One-Click Root**:
  - Load KernelSU directly from the phone using the bundled Android app driven by **Shizuku UserService**.
  - **Zero PC dependency** after reboots — pair Shizuku over Wireless Debugging and tap *"One-click root"*.
- 🧩 **Native Dynamic Symbol Rebasing (`kspatch`)**:
  - High-performance, statically linked ARM64 ELF tool replaces external Python scripts.
  - Dynamically calculates the live boot KASLR slide and rebases all 34 unexported kernel symbols (`do_mount`, `selinux_state`, `ksys_umount`, `task_work_add`, etc.) from `SHN_UNDEF` to `SHN_ABS` on the fly.
- 🛡️ **Full ReSukiSU Manager Compatibility**:
  - **No Red Banner**: Kernel reports version `34678` (`v4.1.0`), matching modern ReSukiSU manager expectations.
  - **No SECCOMP Signal 31 Crashes**: Auto-crowns the manager UID in the kernel (`ksu_manager_appid=10419`), disabling Zygote SECCOMP restrictions before `libksud.so` executes.
  - **App Profile Version 2 Auto-Migration**: Automatically transforms incoming v2 profile structures into kernel-native v4 profiles, preventing *"Failed to update app profile"* errors when toggling Superuser permissions.
- 🧹 **Zero Magisk Remnants**:
  - Cleaned of all Magisk daemons, socket shims, and conflicting selinux rules. Pure KernelSU root environment.

---

## 🏗️ Architecture & Pipeline

```
                     ┌──────────────────────────────────────────────┐
                     │          Device Boot (Stock Kernel)          │
                     └──────────────────────┬───────────────────────┘
                                            │
               ┌────────────────────────────┴────────────────────────────┐
               ▼                                                         ▼
    ┌──────────────────────┐                                  ┌──────────────────────┐
    │  Option A: Mobile    │                                  │  Option B: PC ADB    │
    │  (SOG05 Root App)    │                                  │  (scripts/load_ksu)  │
    └──────────┬───────────┘                                  └──────────┬───────────┘
               │                                                         │
  Connect Shizuku (UID 2000)                                   Execute deploy_sog05.sh
  Extract libgl.so, libkspatch.so                              Push exploit to /data/local/tmp
               │                                                         │
               ├────────────────────────────┬────────────────────────────┘
                                            │
                                            ▼
                    ┌────────────────────────────────────────────────┐
                    │  1. Gain Temporary Root (GhostLock CVE)        │
                    │     Spawns background root su server daemon    │
                    └───────────────────────┬────────────────────────┘
                                            │
                                            ▼
                    ┌────────────────────────────────────────────────┐
                    │  2. Hardware Perf Counter KASLR Leak           │
                    │     Discovers live boot kernel text_base       │
                    └───────────────────────┬────────────────────────┘
                                            │
                                            ▼
                    ┌────────────────────────────────────────────────┐
                    │  3. Dynamic Symbol Patcher (kspatch)           │
                    │     Calculates slide: live_addr - ref_addr     │
                    │     Patches 34 SHN_ABS symbols into .ko        │
                    └───────────────────────┬────────────────────────┘
                                            │
                                            ▼
                    ┌────────────────────────────────────────────────┐
                    │  4. Insert KernelSU-Next LKM Module            │
                    │     su -c 'insmod kernelsu_live.ko'            │
                    │     Mounts /data/adb/ksu, hooks syscalls       │
                    └───────────────────────┬────────────────────────┘
                                            │
                                            ▼
                    ┌────────────────────────────────────────────────┐
                    │  5. Crown Superuser Manager App                │
                    │     Sets ksu_debug_manager_appid=10419         │
                    │     Disables SECCOMP filter for manager        │
                    └───────────────────────┬────────────────────────┘
                                            │
                                            ▼
                    ┌────────────────────────────────────────────────┐
                    │    Root Active! Open ReSukiSU to Grant Root    │
                    └────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start Guide

### Method 1: On-Device One-Click Root (Recommended)

No computer required after initial setup!

1. **Install Prerequisites on your phone**:
   - Install **[Shizuku](https://shizuku.rikka.app/)** (Google Play or GitHub).
   - Install **[ReSukiSU / BakaSU](https://github.com/resukisu/resukisu/releases)** manager APK.
   - Install the **SOG05 Root** APK:
     Download [`out/app-arm64-v8a-release.apk`](out/app-arm64-v8a-release.apk) or grab it from [GitHub Actions Artifacts](https://github.com/Afaqraza12/xper5/actions/workflows/build-apk.yml).
2. **Start Shizuku**:
   - Open Shizuku -> Start via **Wireless Debugging** (Settings -> Developer Options -> Wireless Debugging -> Pair with code).
3. **Run 1-Click Root**:
   - Open **SOG05 Root**.
   - Tap **"Grant Shizuku permission"** when prompted.
   - Tap **"One-click root"**.
   - Watch the real-time log window complete all stages and report `SUCCESS!`.
4. **Manage Root**:
   - Open **ReSukiSU** and grant Superuser permissions to Termux, Root Checker, or your favorite apps!

---

### Method 2: PC USB ADB Deployment

If you prefer deploying and testing directly from your terminal over USB:

1. Connect your Xperia 5 III via USB with **USB Debugging enabled**.
2. Run the automated deployment script:
   ```bash
   bash scripts/load_ksu.sh
   ```
3. The script will:
   - Check and deploy temporary root via `deploy_sog05.sh`.
   - Leak the live boot KASLR base address.
   - Adapt `kernelsu.ko` using `scripts/resolve_symbols.py`.
   - Clean legacy Magisk artifacts.
   - Insert `kernelsu.ko` into the running kernel.
   - Crown the ReSukiSU manager app ID.

---

## 📁 Repository Directory Structure

```text
ghostlock_5.4_xperia-main/
├── .github/workflows/
│   ├── build-apk.yml       # Automated CI workflow building the one-click APK
│   ├── build-ksu.yml       # Automated CI workflow compiling KernelSU LKM
│   └── build.yml           # Automated CI workflow compiling exploit binary
├── apk/                    # Standalone One-Click Android Application
│   ├── app/                # Application module (MainActivity, RootService, AIDL)
│   ├── build.gradle.kts    # AGP 8.7 build configuration
│   └── settings.gradle.kts # Gradle repository configuration
├── exploit/                # GhostLock kernel exploit C source & headers
│   ├── src/                # Core exploit stages, KASLR leaks & su daemon
│   └── Makefile            # NDK build targets
├── out/                    # Ready-to-use binaries
│   ├── app-arm64-v8a-release.apk # Pre-built installable One-Click Root APK
│   └── kernelsu.ko         # Latest patched KernelSU-Next LKM module
├── scripts/                # PC automation & kernel build helper scripts
│   ├── deploy_sog05.sh     # USB ADB exploit runner
│   ├── extract_symvers.py  # Module.symvers symbol version generator
│   ├── load_ksu.sh         # PC ADB dynamic KernelSU loader
│   ├── patch_ksu.py        # Automated patcher for KernelSU-Next in CI
│   ├── post_exploit.sh     # Post-exploit device setup hook
│   └── resolve_symbols.py  # Python ELF symbol rebase tool for PC
├── sog05-5.4.210/          # Pre-built target payload binaries
│   └── bin/exploit_static  # Compiled ARM64 static exploit binary
├── tools/kspatch/          # On-Device ELF symbol patcher
│   └── kspatch.c           # Lightweight C tool rebasing unexported symbols
├── kallsyms.gz             # Reference kernel symbols for SOG05
├── kernel_config           # Device stock kernel configuration
├── kheaders.tar.xz         # Live device kernel headers (fixes cred offset alignment)
└── Module.symvers          # Validated symbol version database for SM8350 5.4.210
```

---

## 🔬 Technical Deep-Dive

### 1. Structure Alignment & `kheaders.tar.xz` Overlay
Upstream Qualcomm SM8350 kernel trees introduce subtle discrepancies in `struct task_struct` member offsets due to configuration variants. Without matching headers, `current_uid()` reads offset `0x810` instead of `0x808`, resulting in immediate kernel panic upon syscall interception. By overlaying the device's live `/sys/kernel/kheaders.tar.xz` during compilation in CI, structure alignment matches the live kernel with 100% binary fidelity.

### 2. Live KASLR Slide & Symbol Resolution
Stock Android kernels strip unexported symbols from the global symbol export table (`EXPORT_SYMBOL`). KernelSU relies on 34 internal functions (such as `task_work_add`, `ksys_umount`, and `selinux_state`).
`kspatch` solves this entirely on-device by computing:
$$\text{live\_address} = \text{ref\_address} + (\text{live\_text\_base} - \text{ref\_text\_base})$$
and updating the relocation section in the `.ko` ELF header from `SHN_UNDEF` (0) to `SHN_ABS` (`0xfff1`).

### 3. ReSukiSU App Profile Version 2 Migration
Modern ReSukiSU managers submit version 2 profile configuration payloads when users toggle app Superuser permissions. KernelSU-Next expects version 4. In [scripts/patch_ksu.py](scripts/patch_ksu.py), we hooked `ksu_set_app_profile()` to automatically invoke `migrate_profile()`, ensuring seamless allowlist updates.

---

## ⚠️ Safety & Responsible Usage

- **Temporary Root**: Because this solution relies on a Loadable Kernel Module (LKM), root is non-destructive. If you ever reboot your device, the system returns to its original stock state.
- **Safety Boundary**: This project is intended for research, device ownership, and software longevity on end-of-life hardware. Keep partition dumps (such as TA partition DRM keys) backed up safely.

---

## 📜 License & Acknowledgments

- **GhostLock**: Kernel privilege escalation based on CVE-2026-43499.
- **KernelSU-Next**: GPL v2 licensed kernel root subsystem by the KernelSU-Next community.
- **ReSukiSU / BakaSU**: Modern superuser management interface.
- **Shizuku**: Privileged API framework by Rikka.
