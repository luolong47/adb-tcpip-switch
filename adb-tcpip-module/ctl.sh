#!/system/bin/sh
# ADB TCP/IP Switch - control script
# Usage: sh /data/adb/modules/adb_tcpip_sw/ctl.sh <on|off|toggle|status|setport N>
# Output: single-line JSON on stdout

MODDIR=${0%/*}
STATE_FILE="$MODDIR/state"
PORT_FILE="$MODDIR/port"
LOG_FILE="/data/local/tmp/adb_tcpip_sw.log"

[ -f "$PORT_FILE" ] || echo 5555 > "$PORT_FILE"
[ -f "$STATE_FILE" ] || echo off > "$STATE_FILE"

PORT=$(cat "$PORT_FILE" 2>/dev/null)
case "$PORT" in
    '' | *[!0-9]*) PORT=5555 ;;
esac
if [ "$PORT" -lt 1 ] 2>/dev/null || [ "$PORT" -gt 65535 ] 2>/dev/null; then
    PORT=5555
fi

log() {
    echo "$(date '+%m-%d %H:%M:%S') $*" >> "$LOG_FILE" 2>/dev/null
}

get_ip() {
    ip -f inet -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1
}

# /proc/net/tcp6 lines carry a 128-bit (32-hex-digit) remote address,
# so match rem as [0-9A-F]+:0000 instead of a fixed width. 0A = LISTEN.
is_listening() {
    HX=$(printf '%04X' "$PORT")
    if grep -qiE ":${HX} [0-9A-F]+:0000 0A" /proc/net/tcp; then return 0; fi
    if grep -qiE ":${HX} [0-9A-F]+:0000 0A" /proc/net/tcp6; then return 0; fi
    return 1
}

status_json() {
    ST=$(cat "$STATE_FILE" 2>/dev/null)
    [ -n "$ST" ] || ST=off
    LIP=$(get_ip)
    [ -n "$LIP" ] || LIP="0.0.0.0"
    if is_listening; then LS=true; else LS=false; fi
    printf '{"state":"%s","port":%d,"ip":"%s","listening":%s,"cmd":"adb connect %s:%d"}\n' \
        "$ST" "$PORT" "$LIP" "$LS" "$LIP" "$PORT"
}

# Write a live status badge into module.prop's description, so the Manager
# module list shows current state without opening the WebUI (same trick
# ReZygisk uses with its "[Monitor: ...]" badge). Value must stay sed-safe:
# no '|', '&' or backslash.
update_desc() {
    [ -f "$MODDIR/module.prop" ] || return 0
    ST=$(cat "$STATE_FILE" 2>/dev/null)
    [ -n "$ST" ] || ST=off
    if [ "$ST" = "on" ]; then
        if is_listening; then
            BADGE="[🟢 ON · ✅ :${PORT} listening]"
        else
            BADGE="[🟢 ON · ⏳ :${PORT} not listening yet]"
        fi
    else
        BADGE="[⚫ OFF · :${PORT} closed]"
    fi
    NEW="description=${BADGE} WebUI switch for adb wireless debugging. TCP listens only while enabled."
    # write only when changed, so a periodic sync loop causes no flash wear
    CUR=$(sed -n 's/^description=//p' "$MODDIR/module.prop" 2>/dev/null)
    [ "$CUR" = "${NEW#description=}" ] && return 0
    sed -i "s|^description=.*|${NEW}|" "$MODDIR/module.prop"
}

restart_adbd() {
    stop adbd
    sleep 1
    start adbd
    sleep 1
}

case "$1" in
    on)
        echo on > "$STATE_FILE"
        setprop service.adb.tcp.port "$PORT"
        restart_adbd
        log "on port=$PORT"
        update_desc
        status_json
        ;;
    off)
        echo off > "$STATE_FILE"
        setprop service.adb.tcp.port -1
        restart_adbd
        log "off"
        update_desc
        status_json
        ;;
    toggle)
        if [ "$(cat "$STATE_FILE" 2>/dev/null)" = "on" ]; then
            exec sh "$0" off
        else
            exec sh "$0" on
        fi
        ;;
    setport)
        NP="$2"
        case "$NP" in
            '' | *[!0-9]*)
                echo '{"error":"port must be a number"}'
                exit 1
                ;;
        esac
        if [ "$NP" -lt 1024 ] 2>/dev/null || [ "$NP" -gt 65535 ] 2>/dev/null; then
            echo '{"error":"port must be 1024-65535"}'
            exit 1
        fi
        echo "$NP" > "$PORT_FILE"
        if [ "$(cat "$STATE_FILE" 2>/dev/null)" = "on" ]; then
            setprop service.adb.tcp.port "$NP"
            restart_adbd
        fi
        log "setport $NP"
        update_desc
        status_json
        ;;
    syncdesc)
        update_desc
        ;;
    status | *)
        status_json
        ;;
esac
