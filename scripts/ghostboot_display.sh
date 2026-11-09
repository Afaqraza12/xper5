#!/system/bin/sh
# GhostBoot Display: Play official LineageOS 24 boot animation on the physical screen

BOOTANIM_ZIP="/data/lineage/mnt/product/media/bootanimation.zip"

if [ ! -f "$BOOTANIM_ZIP" ]; then
    echo "[-] Error: LineageOS bootanimation.zip not found at $BOOTANIM_ZIP"
    exit 1
fi

echo "=========================================================="
echo "    GHOSTBOOT DISPLAY: LINEAGEOS 24 ON PHYSICAL SCREEN    "
echo "=========================================================="
echo "[*] Mounting LineageOS 24 animation over display subsystem..."
mount --bind "$BOOTANIM_ZIP" /system/media/bootanimation.zip 2>/dev/null
mount --bind "$BOOTANIM_ZIP" /oem/media/bootanimation.zip 2>/dev/null

echo "[*] Launching LineageOS 24 graphical animation on screen..."
echo "[*] LOOK AT YOUR PHONE SCREEN NOW!"
echo "[*] (Press ENTER or Ctrl+C when you want to return to stock UI)"

setprop service.bootanim.exit 0
/system/bin/bootanimation &
ANIM_PID=$!

# Wait for user input to stop
read _dummy

echo "[*] Stopping animation and restoring screen..."
setprop service.bootanim.exit 1
kill $ANIM_PID 2>/dev/null
killall bootanimation 2>/dev/null
echo "[+] Screen restored to homescreen!"

