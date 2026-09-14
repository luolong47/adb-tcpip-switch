#!/system/bin/sh
# Module removal: make sure adbd goes back to USB-only
setprop service.adb.tcp.port -1
stop adbd
sleep 1
start adbd
