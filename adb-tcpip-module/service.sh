#!/system/bin/sh
# Boot hook: restore last switch state (runs in background, never blocks boot)
MODDIR=${0%/*}

(
    # wait for system boot completed
    i=0
    while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
        sleep 2
        i=$((i + 1))
    done

    # wait for wlan0 to get an IPv4 address
    j=0
    while [ $j -lt 90 ]; do
        if ip -f inet -o addr show wlan0 2>/dev/null | grep -q 'inet '; then
            break
        fi
        sleep 2
        j=$((j + 1))
    done

    if [ "$(cat "$MODDIR/state" 2>/dev/null)" = "on" ]; then
        sh "$MODDIR/ctl.sh" on > /data/local/tmp/adb_tcpip_sw_boot.log 2>&1
    fi
) &
