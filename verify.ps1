# ==========================================================
# bye-tcp-internet - Post-Apply Verification Script
# Author: softgrain
# GitHub: https://github.com/grainframe/bye-tcp-internet
# Version: 1.3.0
# ==========================================================
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File verify.ps1
#
# Exit code: 0 = no registry FAIL, 1 = at least one registry FAIL.
# [WARN] = key is set in the registry but the live TCP stack reports
#          something else (informational, does not change the exit code).
# ==========================================================

$ErrorActionPreference = "SilentlyContinue"

$script:nPass = 0
$script:nFail = 0
$script:nWarn = 0

# --- Output helpers ---
function Pass($msg) { $script:nPass++; Write-Host "  [PASS] $msg" -ForegroundColor Green }
function Fail($msg) { $script:nFail++; Write-Host "  [FAIL] $msg" -ForegroundColor Red }
function Warn($msg) { $script:nWarn++; Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Info($msg) { Write-Host "  [INFO] $msg" -ForegroundColor Cyan }
function Head($msg) { Write-Host "`n$msg" -ForegroundColor White }

# --- Registry helpers ---
function Get-RegValue($path, $name) {
    try {
        return (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name
    } catch {
        return $null
    }
}

# REG_DWORD is returned by .NET/PowerShell as a signed Int32, so 0xFFFFFFFF
# reads as -1. Normalise to unsigned so values can be compared with their
# documented numbers.
function Get-RegDword($path, $name) {
    $v = Get-RegValue $path $name
    if ($null -eq $v) { return $null }
    if ($v -is [int]) { return [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$v), 0) }
    return $v
}

function Show([object]$v) { if ($null -eq $v) { return "<not set>" } else { return "$v" } }

# Check a value against the expected one. $expected = $null means "must be absent".
function Check($label, $actual, $expected, $note = "") {
    $suffix = if ($note) { " $note" } else { "" }
    if ($null -eq $expected) {
        if ($null -eq $actual) { Pass "$label not set" } else { Fail "$label = $(Show $actual) (expected: not set)" }
    } elseif ($null -ne $actual -and $actual -eq $expected) {
        Pass "$label = $expected$suffix"
    } else {
        Fail "$label = $(Show $actual) (expected $expected)"
    }
}

$tcpPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
$dnsPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters"
$mmPath  = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
$gamesPath = "$mmPath\Tasks\Games"
$qosPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched"

# --- Detect active profile ---
$mmcssGames = Get-RegValue $gamesPath "Scheduling Category"
$negDns     = Get-RegDword $dnsPath "NegativeCacheTime"

if ($mmcssGames -eq "High" -and $negDns -eq 0) {
    $profileName = "GMVELOCITY (Low-Latency)"
} elseif ($null -ne (Get-RegValue $tcpPath "TcpTimedWaitDelay")) {
    $profileName = "UNIVERSAL (Baseline)"
} else {
    $profileName = "NONE (no overrides / rollback applied)"
}
$isGaming = $profileName -match "GMVELOCITY"
$isActive = $profileName -notmatch "NONE"

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host "  bye-tcp-internet - Verification v1.3.0  " -ForegroundColor White
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host "  Detected profile: $profileName" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor DarkGray

if (-not $isActive) {
    # Nothing to verify: show what is currently set, without judging it.
    # (After snapshot.ps1 -Restore these are the machine's original values.)
    Head "[ Current values of keys managed by this project ]"
    $rows = @(
        @($tcpPath, "DefaultTTL"), @($tcpPath, "EnablePMTUDiscovery"), @($tcpPath, "EnablePMTUBHDetect"),
        @($tcpPath, "SackOpts"), @($tcpPath, "Tcp1323Opts"), @($tcpPath, "MaxUserPort"),
        @($tcpPath, "TcpTimedWaitDelay"), @($tcpPath, "EnableECNCapability"),
        @($dnsPath, "MaxNegativeCacheTtl"), @($dnsPath, "NegativeCacheTime"), @($dnsPath, "NetFailureCacheTime"),
        @($mmPath, "NetworkThrottlingIndex"), @($mmPath, "SystemResponsiveness"),
        @($gamesPath, "GPU Priority"), @($gamesPath, "Priority"),
        @($gamesPath, "Scheduling Category"), @($gamesPath, "SFIO Priority"),
        @($qosPath, "NonBestEffortLimit")
    )
    foreach ($r in $rows) { Info ("{0} = {1}" -f $r[1], (Show (Get-RegDword $r[0] $r[1]))) }
} else {

    # ======================================================
    # BLOCK 1: TCP/IP Core Parameters
    # ======================================================
    Head "[ TCP/IP Core Parameters ]"
    Check "DefaultTTL"           (Get-RegDword $tcpPath "DefaultTTL")           64
    Check "EnablePMTUDiscovery"  (Get-RegDword $tcpPath "EnablePMTUDiscovery")  1 "(ON)"
    Check "EnablePMTUBHDetect"   (Get-RegDword $tcpPath "EnablePMTUBHDetect")   0 "(OFF)"
    Check "SackOpts"             (Get-RegDword $tcpPath "SackOpts")             1 "(ON)"
    Check "Tcp1323Opts"          (Get-RegDword $tcpPath "Tcp1323Opts")          1 "(Window Scaling ON, Timestamps OFF)"
    Check "MaxUserPort"          (Get-RegDword $tcpPath "MaxUserPort")          65534
    Check "TcpTimedWaitDelay"    (Get-RegDword $tcpPath "TcpTimedWaitDelay")    30 "s"
    Check "EnableECNCapability"  (Get-RegDword $tcpPath "EnableECNCapability")  0 "(OFF)"

    # ======================================================
    # BLOCK 2: DNS Cache Parameters
    # ======================================================
    Head "[ DNS Cache Parameters ]"
    if ($isGaming) {
        Check "MaxNegativeCacheTtl" (Get-RegDword $dnsPath "MaxNegativeCacheTtl") 0
        Check "NegativeCacheTime"   (Get-RegDword $dnsPath "NegativeCacheTime")   0
        Check "NetFailureCacheTime" (Get-RegDword $dnsPath "NetFailureCacheTime") 0
    } else {
        Check "MaxNegativeCacheTtl" (Get-RegDword $dnsPath "MaxNegativeCacheTtl") 60 "s"
        Check "NegativeCacheTime"   (Get-RegDword $dnsPath "NegativeCacheTime")   60 "s"
        Check "NetFailureCacheTime" (Get-RegDword $dnsPath "NetFailureCacheTime") 30 "s"
    }

    # ======================================================
    # BLOCK 3: Multimedia / MMCSS
    # ======================================================
    Head "[ Multimedia & MMCSS ]"
    Check "NetworkThrottlingIndex" (Get-RegDword $mmPath "NetworkThrottlingIndex") 4294967295 "(0xFFFFFFFF, unlimited)"
    if ($isGaming) {
        Check "SystemResponsiveness" (Get-RegDword $mmPath "SystemResponsiveness") 0 "(gaming)"
        Check "Tasks\Games GPU Priority"        (Get-RegDword $gamesPath "GPU Priority")        8
        Check "Tasks\Games Priority"            (Get-RegDword $gamesPath "Priority")            6
        Check "Tasks\Games Scheduling Category" (Get-RegValue $gamesPath "Scheduling Category") "High"
        Check "Tasks\Games SFIO Priority"       (Get-RegValue $gamesPath "SFIO Priority")       "High"
    } else {
        Check "SystemResponsiveness" (Get-RegDword $mmPath "SystemResponsiveness") 20 "(balanced)"
        Info "MMCSS Tasks\Games check skipped (not a GMVELOCITY profile)"
    }

    # ======================================================
    # BLOCK 4: QoS Policy
    # ======================================================
    Head "[ QoS Policy ]"
    Check "NonBestEffortLimit" (Get-RegDword $qosPath "NonBestEffortLimit") 0 "(no reserved bandwidth)"

    # ======================================================
    # BLOCK 5: Effective state (what the live stack reports)
    # A registry value being present does not prove the stack uses it.
    # ======================================================
    Head "[ Effective state - live TCP stack ]"
    $live = $null
    try { $live = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop } catch { $live = $null }

    if ($null -eq $live) {
        Info "Get-NetTCPSetting not available on this OS version - effective checks skipped."
    } else {
        $ecnReg = Get-RegDword $tcpPath "EnableECNCapability"
        if ("$($live.EcnCapability)" -eq "Disabled") { Pass "ECN capability: Disabled (live)" }
        else { Warn "EnableECNCapability=$(Show $ecnReg) in registry, live stack reports EcnCapability=$($live.EcnCapability)" }

        $tcp1323 = Get-RegDword $tcpPath "Tcp1323Opts"
        if ("$($live.Timestamps)" -eq "Disabled") { Pass "TCP timestamps: Disabled (live)" }
        else { Warn "Tcp1323Opts=$(Show $tcp1323) in registry, live stack reports Timestamps=$($live.Timestamps)" }

        Info "AutoTuning (not touched by profile): $($live.AutoTuningLevelEffective)"
        Info "Congestion provider (not touched by profile): $($live.CongestionProvider)"

        $start = $live.DynamicPortRangeStartPort
        $num   = $live.DynamicPortRangeNumberOfPorts
        if ($null -eq $start -or $null -eq $num) {
            # Locale-independent fallback: first two numbers in the netsh output.
            $nums = [regex]::Matches((netsh int ipv4 show dynamicport tcp | Out-String), '\d+') | ForEach-Object { [int]$_.Value }
            if ($nums.Count -ge 2) { $start = $nums[0]; $num = $nums[1] }
        }
        if ($null -ne $start -and $null -ne $num) {
            Info "Dynamic TCP port range (live): start=$start count=$num   [registry MaxUserPort=$(Show (Get-RegDword $tcpPath 'MaxUserPort'))]"
        }
    }
}

# ==========================================================
# Live netsh read (informational)
# ==========================================================
Head "[ Live TCP Stack - netsh int tcp show global ]"
Write-Host ""
netsh int tcp show global 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
if ($isActive) {
    $color = if ($script:nFail -gt 0) { "Red" } else { "Green" }
    Write-Host ("  PASS: {0}   FAIL: {1}   WARN: {2}" -f $script:nPass, $script:nFail, $script:nWarn) -ForegroundColor $color
    if ($script:nFail -gt 0) { Write-Host "  If any [FAIL] - re-apply the .reg and reboot." -ForegroundColor DarkGray }
} else {
    Write-Host "  No profile active - nothing to verify." -ForegroundColor White
}
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host ""

if ($script:nFail -gt 0) { exit 1 } else { exit 0 }
