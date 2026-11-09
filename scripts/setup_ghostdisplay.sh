#!/system/bin/sh
# GhostDisplay Setup: Deploy Hardware-Accelerated Native Display Bridge for LineageOS 24
# Target: Sony Xperia 5 III (pdx214 / SOG05)

echo "=========================================================="
echo "    GHOSTDISPLAY: NATIVE GPU DISPLAY BRIDGE SETUP         "
echo "=========================================================="

MNT="/data/lineage/mnt"
GHOST_DIR="/data/adb/ghostboot"
TERMUX_DIR="/data/data/com.termux"
SOCKET_DIR="/data/local/tmp/.X11-unix"

mkdir -p "$GHOST_DIR"
mkdir -p "$SOCKET_DIR"
chmod 1777 "$SOCKET_DIR"

# Ensure files symlink for Termux paths
[ ! -e "$TERMUX_DIR/files" ] && ln -s "$TERMUX_DIR" "$TERMUX_DIR/files" 2>/dev/null

# Deploy loader.apk
if [ -f /data/local/tmp/loader.apk ]; then
    cp /data/local/tmp/loader.apk "$GHOST_DIR/loader.apk"
    chmod 644 "$GHOST_DIR/loader.apk"
    echo "[+] Deployed Xlorie display loader.apk"
fi

# Ensure XKB keyboard definitions are deployed
if [ ! -d "$GHOST_DIR/xkb" ] && [ -f /data/local/tmp/xkb.tar.gz ]; then
    tar -xzf /data/local/tmp/xkb.tar.gz -C "$GHOST_DIR/"
    echo "[+] Deployed XKB keyboard configurations"
fi

# Deploy configs & scripts if staged
mkdir -p "$TERMUX_DIR/home/.config/openbox" "$TERMUX_DIR/home/.config/tint2"
[ -f /data/local/tmp/openbox_menu.xml ] && cp /data/local/tmp/openbox_menu.xml "$TERMUX_DIR/home/.config/openbox/menu.xml"
[ -f /data/local/tmp/tint2rc ] && cp /data/local/tmp/tint2rc "$TERMUX_DIR/home/.config/tint2/tint2rc"
[ -f "$TERMUX_DIR/usr/etc/xdg/openbox/rc.xml" ] && cp "$TERMUX_DIR/usr/etc/xdg/openbox/rc.xml" "$TERMUX_DIR/home/.config/openbox/rc.xml"
[ -f /data/local/tmp/banner.sh ] && cp /data/local/tmp/banner.sh "$GHOST_DIR/banner.sh" && chmod 755 "$GHOST_DIR/banner.sh"
[ -f /data/local/tmp/start_desktop.sh ] && cp /data/local/tmp/start_desktop.sh "$GHOST_DIR/start_desktop.sh" && chmod 755 "$GHOST_DIR/start_desktop.sh"
chown -R 10387:10387 "$TERMUX_DIR/home/.config" 2>/dev/null

# Deploy termux-x11 native server launcher
cat << 'EOF' > "$GHOST_DIR/start_xlorie.sh"
#!/system/bin/sh
export CLASSPATH=/data/adb/ghostboot/loader.apk
export TMPDIR=/data/local/tmp
export XKB_CONFIG_ROOT=/data/adb/ghostboot/xkb
mkdir -p /data/local/tmp/.X11-unix
chmod 1777 /data/local/tmp/.X11-unix
exec /system/bin/app_process -Xnoimage-dex2oat / --nice-name="ghostdisplay-x11" com.termux.x11.Loader :0
EOF
chmod +x "$GHOST_DIR/start_xlorie.sh"

# Link ghostdisplay commands
cp "$GHOST_DIR/start_desktop.sh" /data/adb/ksu/bin/ghostdisplay
chmod +x /data/adb/ksu/bin/ghostdisplay
cp "$GHOST_DIR/start_desktop.sh" "$MNT/system/bin/ghostdisplay" 2>/dev/null
cp "$GHOST_DIR/start_desktop.sh" "$MNT/system/bin/ghostboot-display" 2>/dev/null
chmod +x "$MNT/system/bin/ghostdisplay" "$MNT/system/bin/ghostboot-display" 2>/dev/null

echo "[+] GhostDisplay configuration completed successfully!"
