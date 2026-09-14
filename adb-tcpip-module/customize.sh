# customize.sh - executed by the module installer with $MODPATH set

chmod 0755 "$MODPATH"/*.sh 2>/dev/null
chmod 0755 "$MODPATH/webroot" 2>/dev/null
chmod 0644 "$MODPATH/module.prop" 2>/dev/null
chmod 0644 "$MODPATH/webroot/index.html" 2>/dev/null

# defaults (ctl.sh creates them on first run anyway)
[ -f "$MODPATH/state" ] || echo off > "$MODPATH/state"
[ -f "$MODPATH/port" ] || echo 5555 > "$MODPATH/port"
chmod 0644 "$MODPATH/state" "$MODPATH/port" 2>/dev/null

# the old standalone boot script is superseded by this module's service.sh
rm -f /data/adb/service.d/99-adb-tcpip.sh
