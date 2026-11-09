#!/system/bin/sh
# GhostBoot: LineageOS 24 (Android 17) Environment Initializer for Xperia 5 III (pdx214)

MNT="/data/lineage/mnt"

# Ensure loop device nodes loop100 to loop160 exist
for i in $(seq 100 160); do
    if [ ! -b "/dev/block/loop$i" ]; then
        mknod "/dev/block/loop$i" b 7 "$i" 2>/dev/null
    fi
done

mount_if_needed() {
    src="$1"
    dst="$2"
    type="$3"
    flags="$4"
    if ! mount | grep -q " $dst "; then
        mkdir -p "$dst"
        if [ -n "$type" ]; then
            mount -t "$type" -o "$flags" "$src" "$dst"
        else
            mount "$flags" "$src" "$dst"
        fi
    fi
}

echo "[*] Mounting LineageOS 24 base partitions..."
mount_if_needed /data/lineage/system.img "$MNT" ext4 rw
mount_if_needed /data/lineage/system_ext.img "$MNT/system_ext" ext4 ro
mount_if_needed /data/lineage/product.img "$MNT/product" ext4 ro
mount_if_needed /data/lineage/vendor.img "$MNT/vendor" erofs ro

echo "[*] Binding virtual filesystems..."
mount_if_needed /dev "$MNT/dev" "" "--rbind"
mount_if_needed /dev/binderfs "$MNT/dev/binderfs" "" "--bind"
mount_if_needed /proc "$MNT/proc" "" "--bind"
mount_if_needed /sys "$MNT/sys" "" "--bind"
mount_if_needed /data/lineage/linkerconfig "$MNT/linkerconfig" "" "--bind"
mount_if_needed /data/lineage/data_storage "$MNT/data" "" "--bind"

echo "[*] Mounting APEX modular runtime containers..."
mount_if_needed tmpfs "$MNT/apex" tmpfs rw
for img in /data/lineage/apex_images/*.img; do
    base=$(basename "$img")
    pkg=${base%.img}
    target="$MNT/apex/$pkg"
    mkdir -p "$target"
    mount_if_needed "$img" "$target" ext4 ro
done

# Ensure connectivity native library is accessible in system/lib64
if [ ! -f "$MNT/system/lib64/libcom.android.tethering.connectivity_native.so" ]; then
    cp "$MNT/apex/com.android.tethering/lib64/libcom.android.tethering.connectivity_native.so" "$MNT/system/lib64/" 2>/dev/null
fi

echo "[+] LineageOS 24 (Android 17, pdx214) environment is active!"

