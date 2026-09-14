<#
.SYNOPSIS
    安装 / 卸载 ADB TCP/IP Switch 模块（可刷 zip 方式）。

.DESCRIPTION
    1) 连上手机的 adb
    2) 把 dist/adb_tcpip_sw-v1.0.zip 推到手机
    3) 优先用 `apd module install` 装（APatch 命令行安装）
       若 apd 不支持该子命令，会提示改用 APatch Manager 图形界面本地安装
    4) 卸载时删除模块目录并把 adbd 恢复成仅 USB

.PARAMETER Ip       手机 IP，默认 192.168.6.223
.PARAMETER Port     当前 adb 端口，默认 5555
.PARAMETER PushOnly 只把 zip 推到手机，不执行安装（用于 Manager 手动选包安装）
.PARAMETER Uninstall 卸载模块

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -PushOnly
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
#>
[CmdletBinding()]
param(
    [string]$Ip = "192.168.6.223",
    [int]$Port = 5555,
    [switch]$PushOnly,
    [switch]$Uninstall,
    [switch]$SkipConnect
)

$ErrorActionPreference = 'Continue'
$Mod    = "adb_tcpip_sw"
$Zip    = Join-Path $PSScriptRoot "dist\adb_tcpip_sw-v1.0.0.zip"
$Remote = "/sdcard/Download/adb_tcpip_sw-v1.0.0.zip"

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Write-Host "PATH 里没有 adb。" -ForegroundColor Red
    exit 1
}

if (-not $SkipConnect) {
    Write-Host "连接 ${Ip}:${Port} ..."
    & adb connect "$Ip`:$Port"
    Start-Sleep -Seconds 1
}

$devices = & adb devices
if (-not ($devices -match "\d+\.\d+\.\d+\.\d+:\d+\s+device") -and -not ($devices -match "`tdevice$")) {
    Write-Host "没有在线设备。先用 USB 连一次，或在模块开关打开的状态下 adb connect。" -ForegroundColor Red
    exit 1
}

if ($Uninstall) {
    Write-Host "卸载模块 $Mod ..."
    & adb shell "su -c 'rm -rf /data/adb/modules/$Mod; setprop service.adb.tcp.port -1; stop adbd; sleep 1; start adbd'"
    Write-Host "已卸载，adbd 恢复 USB 模式。重启后彻底生效。" -ForegroundColor Green
    exit 0
}

if (-not (Test-Path $Zip)) {
    Write-Host "找不到 $Zip ，先运行: python build.py" -ForegroundColor Red
    exit 1
}

Write-Host "推送 $Zip -> $Remote"
& adb push "$Zip" "$Remote"
if ($LASTEXITCODE -ne 0) {
    Write-Host "推送失败。" -ForegroundColor Red
    exit 1
}

if ($PushOnly) {
    Write-Host ""
    Write-Host "已推到手机: $Remote" -ForegroundColor Cyan
    Write-Host "现在去 APatch Manager -> 模块 -> 本地安装，选中这个文件即可。"
    exit 0
}

# apd 是否与 KernelSU 同构（module install）
$modHelp = (& adb shell "su -c 'apd module --help'") -join "`n"
if ($modHelp -match 'install') {
    Write-Host "apd module install ..."
    $out = & adb shell "su -c 'apd module install $Remote'"
    Write-Host $out
    if ($out -notmatch 'install|success|Success|完成') {
        Write-Host "apd 返回内容看起来不像成功，请检查上面输出。" -ForegroundColor Yellow
    }
} else {
    Write-Host ""
    Write-Host "apd 没有 module install 子命令，改用图形界面：" -ForegroundColor Yellow
    Write-Host "  APatch Manager -> 模块 -> 本地安装 -> 选择 $Remote"
}

Write-Host ""
Write-Host "装完在 APatch Manager 里确认 $Mod 已启用，重启一次手机。"
Write-Host "之后在模块详情页点开 WebUI 就能用开关控制 5555。" -ForegroundColor Cyan
