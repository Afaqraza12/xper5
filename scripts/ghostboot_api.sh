#!/system/bin/sh
echo "Content-type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

QS="$QUERY_STRING"
CMD=$(echo "$QS" | sed -n 's/.*cmd=\([^&]*\).*/\1/p')

if [ "$CMD" = "info" ]; then
    REL=$(chroot /data/lineage/mnt /system/bin/sh -c 'cat /system/build.prop | grep "ro.build.version.release=" | head -n 1 | cut -d= -f2' | tr -d '\r\n')
    SDK=$(chroot /data/lineage/mnt /system/bin/sh -c 'cat /system/build.prop | grep "ro.build.version.sdk=" | head -n 1 | cut -d= -f2' | tr -d '\r\n')
    PATCH=$(chroot /data/lineage/mnt /system/bin/sh -c 'cat /system/build.prop | grep "ro.build.version.security_patch=" | head -n 1 | cut -d= -f2' | tr -d '\r\n')
    DEV=$(chroot /data/lineage/mnt /system/bin/sh -c 'cat /system/build.prop | grep "ro.lineage.device=" | head -n 1 | cut -d= -f2' | tr -d '\r\n')
    MODEL=$(chroot /data/lineage/mnt /system/bin/sh -c 'cat /vendor/build.prop | grep "ro.product.vendor.model=" | head -n 1 | cut -d= -f2' | tr -d '\r\n')
    KERN=$(uname -r | tr -d '\r\n')
    UPTIME=$(uptime | tr -d '\r\n' | sed 's/"//g')
    echo "{\"release\":\"$REL\",\"sdk\":\"$SDK\",\"patch\":\"$PATCH\",\"device\":\"$DEV\",\"model\":\"$MODEL\",\"kernel\":\"$KERN\",\"uptime\":\"$UPTIME\"}"

elif [ "$CMD" = "art" ]; then
    OUT=$(chroot /data/lineage/mnt /apex/com.android.art/bin/dalvikvm64 -cp /system/framework/abx.jar com.android.commands.abx.Abx 2>&1 | head -n 10 | sed 's/"/\\"/g')
    echo "{\"output\":\"$OUT\"}"

elif [ "$CMD" = "exec" ]; then
    PARAM=$(echo "$QS" | sed -n 's/.*c=\([^&]*\).*/\1/p' | sed 's/+/ /g' | sed 's/%20/ /g' | sed 's/%2F/\//g' | sed 's/%3A/:/g' | sed 's/%3B/;/g')
    [ -z "$PARAM" ] && PARAM="uname -a"
    OUT=$(chroot /data/lineage/mnt /system/bin/sh -c "$PARAM" 2>&1 | head -n 30 | sed 's/"/\\"/g')
    echo "{\"cmd\":\"$PARAM\",\"output\":\"$OUT\"}"

elif [ "$CMD" = "files" ]; then
    DIR=$(echo "$QS" | sed -n 's/.*path=\([^&]*\).*/\1/p' | sed 's/%2F/\//g')
    [ -z "$DIR" ] && DIR="/system/bin"
    FILES=$(chroot /data/lineage/mnt /system/bin/sh -c "ls -m $DIR 2>&1" | sed 's/"/\\"/g')
    echo "{\"path\":\"$DIR\",\"files\":\"$FILES\"}"

else
    echo "{\"status\":\"ok\",\"engine\":\"LineageOS 24 GhostBoot\"}"
fi

