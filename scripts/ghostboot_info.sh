#!/system/bin/sh
# GhostBoot: Status & Diagnostics for LineageOS 24 (pdx214)

MNT="/data/lineage/mnt"

echo "=========================================================="
echo "           GHOSTBOOT SYSTEM DIAGNOSTICS                   "
echo "=========================================================="

echo "[*] Base Kernel:"
uname -a

echo ""
echo "[*] LineageOS 24 Release Properties:"
chroot "$MNT" /system/bin/sh -c '
echo -n "OS Release         : " && cat /system/build.prop | grep "ro.build.version.release=" | head -n 1 | cut -d= -f2
echo -n "SDK Version        : " && cat /system/build.prop | grep "ro.build.version.sdk=" | head -n 1 | cut -d= -f2
echo -n "Security Patch     : " && cat /system/build.prop | grep "ro.build.version.security_patch=" | head -n 1 | cut -d= -f2
echo -n "Lineage Codename   : " && cat /system/build.prop | grep "ro.lineage.device=" | head -n 1 | cut -d= -f2
echo -n "Vendor Model       : " && cat /vendor/build.prop | grep "ro.product.vendor.model=" | head -n 1 | cut -d= -f2
'

echo ""
echo "[*] ART Virtual Machine Test:"
chroot "$MNT" /apex/com.android.art/bin/dalvikvm64 -cp /system/framework/abx.jar com.android.commands.abx.Abx 2>&1 | head -n 4

echo ""
echo "[*] Active Mount Points:"
echo -n "Lineage Partitions : "
mount | grep -c "$MNT"
echo -n "APEX Modules       : "
mount | grep -c "$MNT/apex"
echo "=========================================================="

