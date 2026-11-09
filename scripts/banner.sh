#!/system/bin/sh
clear
echo -e "\033[1;36m"
cat << 'ASCII'
  _     _                              ____  _  _   
 | |   (_)_ __   ___  __ _  __ _  ___ / ___|| || |  
 | |   | | '_ \ / _ \/ _` |/ _` |/ _ \\___ \| || |_ 
 | |___| | | | |  __/ (_| | (_| |  __/ ___) |__   _|
 |_____|_|_| |_|\___|\__,_|\__, |\___||____/   |_|  
                           |___/                    
         LINEAGEOS 24.0 (ANDROID 17) pdx214
ASCII
echo -e "\033[0m"
echo -e "\033[1;32m[✓] Hardware Display Engine : \033[0mQualcomm Adreno 660 GPU (/dev/kgsl-3d0)"
echo -e "\033[1;32m[✓] Display Resolution     : \033[0m1080x2197 OLED @ 120Hz Hardware Refresh"
echo -e "\033[1;32m[✓] Target Device          : \033[0mSony Xperia 5 III (SOG05 / pdx214)"
echo -e "\033[1;32m[✓] Base Linux Kernel      : \033[0m5.4.210-qgki (Snapdragon 888)"
echo -e "\033[1;32m[✓] Android Runtime (ART)  : \033[0mAndroid 17 CinnamonBun (API Level 37)"
echo -e "\033[1;32m[✓] Userspace Isolation    : \033[0mActive Chroot Jail (/data/lineage/mnt)"
echo -e "\033[1;32m[✓] SELinux Security Mode  : \033[0mPermissive Root Container (u:r:ksu:s0)"
echo ""
echo -e "\033[1;33mUseful commands:\033[0m"
echo -e "  • \033[1;37mghostboot-info\033[0m    : LineageOS 24 build properties"
echo -e "  • \033[1;37mdalvikvm64\033[0m        : Execute Android 17 ART bytecode"
echo -e "  • \033[1;37mexit\033[0m              : Close session"
echo "------------------------------------------------------------------"
echo ""
