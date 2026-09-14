#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
打包 APatch / KernelSU / Magisk 通用的可刷模块 zip。

产物: dist/adb_tcpip_sw-v1.0.1.zip
用法: python build.py
"""
import os
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "adb-tcpip-module")
OUT_DIR = os.path.join(ROOT, "dist")
VERSION = os.environ.get("VERSION", "v1.0.1")
OUT = os.path.join(OUT_DIR, "adb_tcpip_sw-%s.zip" % VERSION)

# 兜底用：adb-tcpip-module/customize.sh 不存在时的默认内容
CUSTOMIZE_SH = """\
# customize.sh - executed by the module installer with $MODPATH set
chmod 0755 "$MODPATH"/*.sh 2>/dev/null
chmod 0755 "$MODPATH/webroot" 2>/dev/null
chmod 0644 "$MODPATH/module.prop" 2>/dev/null
chmod 0644 "$MODPATH/webroot/index.html" 2>/dev/null

# defaults (created on first run by ctl.sh anyway)
[ -f "$MODPATH/state" ] || echo off > "$MODPATH/state"
[ -f "$MODPATH/port" ] || echo 5555 > "$MODPATH/port"
chmod 0644 "$MODPATH/state" "$MODPATH/port" 2>/dev/null

# the old standalone boot script is superseded by this module's service.sh
rm -f /data/adb/service.d/99-adb-tcpip.sh
"""

# recovery / 自定义刷入路径的委托脚本：交给机器上实际存在的 root 方案处理
UPDATE_BINARY = """\
#!/system/bin/sh
# Generic module installer shim.
# Normal installs go through APatch Manager / `apd module install`, this only
# exists so the zip is also accepted by recovery-style flashers.

ZIP="$3"

if [ -z "$ZIP" ] || [ ! -f "$ZIP" ]; then
    echo "usage: update-binary <api> <outfd> <zip>"
    exit 1
fi

if command -v apd >/dev/null 2>&1; then
    exec apd module install "$ZIP"
elif command -v ksud >/dev/null 2>&1; then
    exec ksud module install "$ZIP"
elif command -v magisk >/dev/null 2>&1; then
    exec magisk --install-module "$ZIP"
fi

echo "no supported root solution found (apd/ksud/magisk)"
exit 1
"""

UPDATER_SCRIPT = "#MAGISK\n"


def add(zf, arcname, data, mode):
    """mode 为 unix 权限位；以 / 结尾的条目补 MS-DOS 目录标志 0x10。"""
    zi = zipfile.ZipInfo(arcname, date_time=(2026, 9, 15, 4, 30, 0))
    attr = mode << 16
    if arcname.endswith("/"):
        attr |= 0x10
    zi.external_attr = attr
    zi.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(zi, data)


def main():
    if not os.path.isdir(SRC):
        raise SystemExit("module source dir not found: %s" % SRC)

    os.makedirs(OUT_DIR, exist_ok=True)

    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as zf:
        # META-INF first, as flashers expect
        add(zf, "META-INF/com/google/android/update-binary", UPDATE_BINARY, 0o755)
        add(zf, "META-INF/com/google/android/updater-script", UPDATER_SCRIPT, 0o644)

        # module payload (customize.sh is added separately below)
        for entry in sorted(os.listdir(SRC)):
            path = os.path.join(SRC, entry)
            if os.path.isfile(path):
                if entry == "customize.sh":
                    continue
                with open(path, "rb") as f:
                    data = f.read()
                mode = 0o755 if entry.endswith(".sh") else 0o644
                add(zf, entry, data, mode)
            elif os.path.isdir(path):
                for sub, _, files in os.walk(path):
                    rel = os.path.relpath(sub, SRC).replace("\\", "/")
                    add(zf, rel + "/", b"", 0o755 | 0x0)
                    for name in sorted(files):
                        fp = os.path.join(sub, name)
                        with open(fp, "rb") as f:
                            data = f.read()
                        mode = 0o755 if name.endswith(".sh") else 0o644
                        add(zf, "%s/%s" % (rel, name), data, mode)

        # prefer the real file so the repo stays the single source of truth
        custom = os.path.join(SRC, "customize.sh")
        if os.path.isfile(custom):
            with open(custom, "rb") as f:
                add(zf, "customize.sh", f.read(), 0o755)
        else:
            add(zf, "customize.sh", CUSTOMIZE_SH, 0o755)

    print("built: %s" % OUT)
    with zipfile.ZipFile(OUT) as zf:
        for i in zf.infolist():
            print("  %s  %s" % (oct(i.external_attr >> 16), i.filename))


if __name__ == "__main__":
    main()
