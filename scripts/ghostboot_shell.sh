#!/system/bin/sh
# GhostBoot: LineageOS 24 (Android 17) Interactive Shell

MNT="/data/lineage/mnt"

# Ensure environment is initialized
/data/adb/ghostboot/ghostboot_env.sh >/dev/null 2>&1

echo "=========================================================="
echo "    GHOSTBOOT: LINEAGEOS 24.0 (ANDROID 17) ON XPERIA      "
echo "    Target Device : Sony Xperia 5 III (pdx214 / SOG05)   "
echo "    Bootloader    : LOCKED (Userspace Hijack)             "
echo "    Base Kernel   : Linux 5.4.210-qgki                    "
echo "    OS Version    : Android 17 CinnamonBun (API Level 37)"
echo "=========================================================="
echo "[*] Connected to LineageOS 24 userspace terminal."
echo "[*] To play LineageOS 24 boot graphics on screen: run 'ghostboot-display'"
echo "Type 'exit' to return to stock root shell."
echo ""

# Create custom shell profile inside chroot so prompt clearly identifies LineageOS 24
mkdir -p "$MNT/tmp"
cat << 'ENVEVAL' > "$MNT/tmp/lineagerc"
export PS1="lineageOS-24.0 (Android 17) [pdx214]:\w # "
export PATH=/apex/com.android.art/bin:/apex/com.android.runtime/bin:/system/bin:/system_ext/bin:/product/bin:/vendor/bin
export ANDROID_ROOT=/system
export ANDROID_DATA=/data
export ANDROID_ART_ROOT=/apex/com.android.art
export ANDROID_I18N_ROOT=/apex/com.android.i18n
export ANDROID_TZDATA_ROOT=/apex/com.android.tzdata
ENVEVAL

ENV=/tmp/lineagerc chroot "$MNT" /system/bin/sh -i
