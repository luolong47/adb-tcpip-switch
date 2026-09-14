#!/system/bin/sh
# Invoked from APatch Manager -> Action button: flip the switch
MODDIR=${0%/*}
sh "$MODDIR/ctl.sh" toggle
