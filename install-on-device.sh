#!/system/bin/sh
# Runs ON the phone as root. Installs the module from /data/local/tmp.
# Invoked by install.ps1 - do not run by hand unless you know what this does.

SRC=/data/local/tmp/adb_tcpip_sw
DST=/data/adb/modules/adb_tcpip_sw

rm -rf "$DST"
mkdir -p "$DST"
cp -R "$SRC"/. "$DST"/

# strip CRLF (toybox tr understands \r)
for f in "$DST"/*.sh; do
    [ -f "$f" ] || continue
    tr -d '\r' < "$f" > "$f.new"
    mv "$f.new" "$f"
    chmod 0755 "$f"
done

chmod 0755 "$DST" "$DST/webroot"
chmod 0644 "$DST/module.prop"
chmod 0644 "$DST/webroot/index.html"

# defaults
[ -f "$DST/state" ] || echo off > "$DST/state"
[ -f "$DST/port" ] || echo 5555 > "$DST/port"
chmod 0644 "$DST/state" "$DST/port"

# legacy: the old standalone boot script is superseded by the module's service.sh
rm -f /data/adb/service.d/99-adb-tcpip.sh
rm -f /data/local/tmp/adb-tcpip.sh

rm -rf "$SRC"

echo "=== installed ==="
ls -l "$DST"
echo "state=$(cat "$DST/state") port=$(cat "$DST/port")"
