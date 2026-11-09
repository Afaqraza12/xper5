#!/system/bin/sh
# GhostDisplay: Launch LineageOS 24 (Android 17) Desktop UI on Sony Xperia 5 III (pdx214)

echo "=========================================================="
echo "    GHOSTBOOT: LINEAGEOS 24.0 (ANDROID 17) pdx214        "
echo "    Hardware Display Surface Bridge on Snapdragon 888    "
echo "=========================================================="

MNT="/data/lineage/mnt"
GHOST_DIR="/data/adb/ghostboot"
TERMUX_DIR="/data/data/com.termux"

# 1. Initialize environment and mounts
echo "[*] Initializing LineageOS 24 environment..."
/data/adb/ghostboot/ghostboot_env.sh >/dev/null 2>&1

# 2. Ensure display sockets and symlinks
mkdir -p /data/local/tmp/.X11-unix "$TERMUX_DIR/usr/tmp/.X11-unix" "$MNT/tmp/.X11-unix"
chmod 1777 /data/local/tmp/.X11-unix "$TERMUX_DIR/usr/tmp/.X11-unix" "$MNT/tmp/.X11-unix"
mount --bind "$TERMUX_DIR/usr/tmp/.X11-unix" "$MNT/tmp/.X11-unix" 2>/dev/null
mount --bind "$TERMUX_DIR/usr/tmp/.X11-unix" /data/local/tmp/.X11-unix 2>/dev/null

# Ensure files symlink
[ ! -e "$TERMUX_DIR/files" ] && ln -s "$TERMUX_DIR" "$TERMUX_DIR/files" 2>/dev/null

# Bind termux into lineage chroot if needed
mkdir -p "$MNT/data/data/com.termux"
mount --bind "$TERMUX_DIR" "$MNT/data/data/com.termux" 2>/dev/null

# 3. Ensure Xlorie GPU server is active
if ! ps -ef | grep -v grep | grep -q "ghostdisplay-x11"; then
    echo "[*] Starting Xlorie GPU display server on :0..."
    nohup /data/adb/ghostboot/start_xlorie.sh </dev/null >/dev/null 2>&1 &
    sleep 1
fi

# 4. Bring display surface to front
echo "[*] Presenting LineageOS display surface on phone screen..."
am start -n com.termux.x11/.MainActivity --ez fullscreen true >/dev/null 2>&1
sleep 1

# Environment for X11 clients
export DISPLAY=:0
export PATH="$TERMUX_DIR/usr/bin:$PATH"
export LD_LIBRARY_PATH="$TERMUX_DIR/usr/lib"
export HOME="$TERMUX_DIR/home"
export XAUTHORITY="$TERMUX_DIR/home/.Xauthority"

# 5. Start Openbox Window Manager if not running
if ! ps -ef | grep -v grep | grep -q "openbox"; then
    echo "[*] Starting Openbox Window Manager..."
    nohup openbox </dev/null >/dev/null 2>&1 &
    sleep 1
fi

# 6. Apply LineageOS 24 Wallpaper
echo "[*] Setting LineageOS 24 Ascension Teal Wallpaper..."
feh --bg-fill /data/adb/ghostboot/wallpaper.jpg 2>/dev/null

# 7. Start Tint2 Status Dock if not running
if ! ps -ef | grep -v grep | grep -q "tint2"; then
    echo "[*] Starting LineageOS System Dock (tint2)..."
    nohup tint2 -c "$TERMUX_DIR/home/.config/tint2/tint2rc" </dev/null >/dev/null 2>&1 &
fi

# 8. Start interactive LineageOS 24 Root Terminal if not running
if ! ps -ef | grep -v grep | grep -q "aterm"; then
    echo "[*] Launching LineageOS 24 Root Terminal..."
    nohup aterm -fn 10x20 -geometry 75x38+30+60 \
        -title "LineageOS 24 (Android 17) [pdx214]" \
        -bg "#0c191f" -fg "#6ee7b7" -cr "#38bdf8" \
        -e /data/adb/ghostboot/lineage_shell.sh </dev/null >/dev/null 2>&1 &
fi

echo "=========================================================="
echo "   [+] LINEAGEOS 24 (ANDROID 17) IS LIVE ON YOUR SCREEN!  "
echo "   Look at your Xperia 5 III display right now!           "
echo "=========================================================="
