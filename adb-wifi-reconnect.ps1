<#
.SYNOPSIS
    一键连回手机的无线 adb（5555）。

.DESCRIPTION
    手机重启后 IP 可能被路由器重新分配，本脚本先直连上次记录的 IP；
    不通则并行扫描同网段 /24 的 5555 端口，找到就 adb connect。

.PARAMETER Ip
    上次连接过的手机 IP，默认 192.168.6.223。扫描时以其前三段作为网段。

.PARAMETER Port
    端口，默认 5555。

.PARAMETER NoScan
    只连指定 IP，不扫描网段。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\adb-wifi-reconnect.ps1
    powershell -ExecutionPolicy Bypass -File .\adb-wifi-reconnect.ps1 -Ip 192.168.6.100
#>
[CmdletBinding()]
param(
    [string]$Ip    = "192.168.6.223",
    [int]   $Port  = 5555,
    [switch]$NoScan
)

$ErrorActionPreference = 'Continue'

function Test-TcpPort {
    param([string]$Address, [int]$Port, [int]$TimeoutMs = 700)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($Address, $Port)
        if ($task.Wait($TimeoutMs) -and $client.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Find-AdbHosts {
    param([string]$Prefix, [int]$Port)

    $probe = {
        param($addr, $port)
        $c = New-Object System.Net.Sockets.TcpClient
        try {
            $t = $c.ConnectAsync($addr, $port)
            if ($t.Wait(700) -and $c.Connected) { return $addr }
        } catch { }
        finally { $c.Dispose() }
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, 128)
    $pool.Open()
    $pending = @()
    foreach ($i in 1..254) {
        $addr = "$Prefix.$i"
        $ps = [powershell]::Create().AddScript($probe).AddArgument($addr).AddArgument($Port)
        $ps.RunspacePool = $pool
        $pending += [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
    }

    $found = @()
    foreach ($p in $pending) {
        try {
            $r = $p.PS.EndInvoke($p.Handle)
            if ($r) { $found += $r }
        } catch { }
        finally { $p.PS.Dispose() }
    }
    $pool.Close()
    return $found
}

function Connect-Adb {
    param([string]$Address, [int]$Port)
    $out = & adb connect "$Address`:$Port" 2>&1
    Write-Host "  adb connect $Address`:$Port -> $out"
    return ($out -match 'connected|already connected')
}

Write-Host "目标: ${Ip}:${Port}"

$candidates = @()
if (Test-TcpPort -Address $Ip -Port $Port) {
    $candidates += $Ip
} elseif (-not $NoScan) {
    $prefix = ($Ip -split '\.')[0..2] -join '.'
    Write-Host "$Ip 无响应，扫描 $prefix.0/24 的 $Port 端口 ..."
    $candidates = Find-AdbHosts -Prefix $prefix -Port $Port
    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-Host "网段内未发现监听 $Port 的设备。确认：手机已开机、WiFi 已连、开机脚本已生效。" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "发现: $($candidates -join ', ')"
} else {
    Write-Host "$Ip 无响应（已跳过扫描）。" -ForegroundColor Yellow
    exit 1
}

$ok = $false
foreach ($c in $candidates) {
    if (Connect-Adb -Address $c -Port $Port) { $ok = $true }
}

if ($ok) {
    Write-Host "`n当前设备列表:" -ForegroundColor Cyan
    & adb devices -l
} else {
    Write-Host "`n连接失败。若从未授权过这台电脑，请先用 USB 连一次并在手机上点允许。" -ForegroundColor Yellow
    exit 1
}
