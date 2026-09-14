# ADB TCP/IP Switch

**https://github.com/luolong47/adb-tcpip-switch**

给 Redmi K60（APatch root）做的 adb 无线调试开关模块：**开关打开时 adbd 才监听 TCP 5555，关闭即彻底停止监听**。带一个在 APatch Manager 里点开的 WebUI 页面，和 Zygisk Next 那种一样。

## 为什么不是裸脚本

`adb tcpip 5555` 改的是 `service.adb.tcp.port`，属于运行时属性，adbd 一重启就丢。网上流传的
`setprop persist.adb.tcp.port 5555` 在 Android 15 上**已经无效**——全盘 grep 过
`/system/etc/init/hw/init.rc`、`/apex/com.android.adbd/etc/init.rc`、`/vendor`、`/odm` 的 rc 文件，
`adb.tcp` 零匹配，init 不再处理这个属性。所以只能用 root 层的开机脚本自己拉起来。

## 文件结构

```
adb-tcpip-module/            <- 模块本体，会落到 /data/adb/modules/adb_tcpip_sw
├── module.prop              模块信息
├── ctl.sh                   控制脚本 on/off/toggle/status/setport，输出 JSON
├── service.sh               开机钩子：按上次开关状态恢复（后台执行，不卡开机）
├── uninstall.sh             卸载时把 adbd 恢复成 USB
├── state                    开关状态持久化（on/off，首次运行自动生成）
├── port                     端口号持久化（默认 5555）
└── webroot/index.html       WebUI 页面

build.py                     <- 打包脚本，产物 dist/adb_tcpip_sw-v1.0.1.zip
install.ps1                  <- PC 端安装 / 卸载 / 只推包
install-on-device.sh         <- （备用）不走 zip 时的手工 root 安装器
```

## 产物：可刷 zip

```bash
python build.py      # -> dist/adb_tcpip_sw-v1.0.1.zip
```

zip 结构（标准模块格式，APatch / KernelSU / Magisk 通用，`.sh` 权限位已写进 zip）：

```
META-INF/com/google/android/update-binary   0755  委托给 apd/ksud/magisk 的 shim
META-INF/com/google/android/updater-script  0644  #MAGISK
module.prop  ctl.sh  service.sh  uninstall.sh  customize.sh
webroot/index.html
```

## 安装

三种方式，任选：

**1) 命令行自动装**
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```
连 adb → 推 zip 到 `/sdcard/Download/` → `apd module install` → 装完提示重启。
脚本会先探测 `apd module --help`，若你的 APatch 版本没有这个子命令，会提示走图形界面。

**2) 只推包，Manager 手动刷**（最稳）
```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -PushOnly
# 然后 APatch Manager -> 模块 -> 本地安装 -> 选 /sdcard/Download/adb_tcpip_sw-v1.0.1.zip
```

**3) 纯手工**
```bash
adb push dist/adb_tcpip_sw-v1.0.1.zip /sdcard/Download/
adb shell su -c "apd module install /sdcard/Download/adb_tcpip_sw-v1.0.1.zip"
```

安装时 `customize.sh` 会兜底修权限，并顺手删掉之前那个
`/data/adb/service.d/99-adb-tcpip.sh`（功能已被模块的 `service.sh` 取代，留着会打架）。

装完在 **APatch Manager → 模块** 里确认 `adb_tcpip_sw` 已启用，**重启一次手机**。

## 使用

- **WebUI**：模块详情页点开网页 → 大开关、手机 IP、端口、实际监听状态、一键复制 `adb connect` 命令、改端口。
- **命令行**：`adb shell su -c "sh /data/adb/modules/adb_tcpip_sw/ctl.sh on|off|status|setport 5555"`
- **模块列表徽章**：Manager 的模块列表里直接显示 `[🟢 ON · ✅ :5555 listening]`，状态一变就更新（改写 `module.prop` 的 description，仅在文本变化时落盘）。

状态存在 `state` 文件里，**重启后按上次状态自动恢复**（on 才监听）。开关只通过 WebUI（或命令行）控制，Manager 的 Action 按钮不提供。

## WebUI 机制（写页面时用到的）

- 宿主给 WebView 注入 `window.apatch`，APatch 系通用写法是 `window.ksu = window.apatch`（Zygisk Next 的 index.html 里就是这么干的）。
- 执行 root 命令：`ksu.exec(cmd)`，异步，返回 `{errno, stdout, stderr}`（有时是 JSON 字符串，页面里已兼容）。
- 页面位置：`/data/adb/modules/<id>/webroot/index.html`；`/internal/insets.css` 是宿主提供的安全区样式。

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

或手机上 `adb shell su -c "rm -rf /data/adb/modules/adb_tcpip_sw"`，再把 adbd 复原。

## 附：IP 变了怎么办

`adb-wifi-reconnect.ps1` 可以先连上次 IP、不通就并行扫 `/24` 网段的 5555。想彻底省事就在路由器
给手机做 DHCP 静态绑定（或在手机 WiFi 里设静态 IP），端口和 IP 都固定后脚本一次命中。
