#Requires -RunAsAdministrator
<#
.SYNOPSIS
    bye-tcp-internet - exact-state snapshot and restore.

.DESCRIPTION
    Records the current state (exists / type / data) of every registry value
    that universal.reg and gmvelocity.reg write, and can put each one back
    exactly as it was: values that did not exist are deleted, values that
    existed get their original type and data back.

    The first snapshot ever taken is kept as baseline.json (the state before
    this tool touched the machine). -Restore uses the baseline by default.
    After a successful restore of the baseline it is archived, so the next
    apply records a fresh baseline.

    Only the values listed in $Managed below can be read or written. Anything
    else found in a snapshot file is ignored.

    Storage: %ProgramData%\bye-tcp-internet\snapshots (Administrators/SYSTEM only)

.PARAMETER Backup
    Take a snapshot now.

.PARAMETER Restore
    Restore from baseline.json (or from -Path).

.PARAMETER Path
    Snapshot file to restore instead of the baseline.

.PARAMETER List
    Show available snapshots.

.EXAMPLE
    .\snapshot.ps1 -Backup
.EXAMPLE
    .\snapshot.ps1 -Restore -WhatIf
.EXAMPLE
    .\snapshot.ps1 -Restore -Path "C:\ProgramData\bye-tcp-internet\snapshots\20261006-120000.json"
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [switch]$Backup,
    [switch]$Restore,
    [string]$Path,
    [switch]$List
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Single source of truth: every value written by universal.reg / gmvelocity.reg.
$Managed = @(
    @{ Key = 'SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
       Names = @('DefaultTTL', 'EnablePMTUDiscovery', 'EnablePMTUBHDetect', 'SackOpts',
                 'Tcp1323Opts', 'MaxUserPort', 'TcpTimedWaitDelay', 'EnableECNCapability') },
    @{ Key = 'SYSTEM\CurrentControlSet\Services\Dnscache\Parameters'
       Names = @('MaxNegativeCacheTtl', 'NegativeCacheTime', 'NetFailureCacheTime') },
    @{ Key = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
       Names = @('NetworkThrottlingIndex', 'SystemResponsiveness') },
    @{ Key = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
       Names = @('GPU Priority', 'Priority', 'Scheduling Category', 'SFIO Priority') },
    @{ Key = 'SOFTWARE\Policies\Microsoft\Windows\Psched'
       Names = @('NonBestEffortLimit') }
)

$SnapDir  = Join-Path $env:ProgramData 'bye-tcp-internet\snapshots'
$Baseline = Join-Path $SnapDir 'baseline.json'

function Write-Status {
    param([string]$Message, [string]$Level = 'INFO')
    $color = switch ($Level) {
        'OK'   { 'Green'  }
        'SET'  { 'Yellow' }
        'DEL'  { 'Yellow' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red'    }
        default { 'Cyan'  }
    }
    Write-Host ("[{0,-4}] {1}" -f $Level, $Message) -ForegroundColor $color
}

function Open-Base {
    # Explicit 64-bit view: a 32-bit PowerShell would otherwise be redirected
    # to Wow6432Node for HKLM\SOFTWARE.
    [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
}

function Initialize-SnapDir {
    if (Test-Path -LiteralPath $SnapDir) { return }
    New-Item -ItemType Directory -Path $SnapDir -Force | Out-Null
    # Administrators (S-1-5-32-544) and SYSTEM (S-1-5-18) only, locale independent.
    # A snapshot is later written back into HKLM, so it must not be user-writable.
    $parent = Split-Path $SnapDir -Parent
    & icacls.exe $parent /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed on $parent (exit $LASTEXITCODE)" }
}

function Format-Data($v) {
    if ($null -eq $v) { return '<none>' }
    if ($v -is [int]) { return ('0x{0:x8}' -f [uint32]([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$v), 0))) }
    return [string]$v
}

# ---------------------------------------------------------------- Backup ----
function Invoke-Backup {
    Initialize-SnapDir
    $base = Open-Base
    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($m in $Managed) {
        $k = $base.OpenSubKey($m.Key, $false)
        $values = New-Object System.Collections.Generic.List[object]
        foreach ($n in $m.Names) {
            if ($null -ne $k -and ($k.GetValueNames() -contains $n)) {
                $values.Add([pscustomobject]@{
                    Name   = $n
                    Exists = $true
                    Kind   = $k.GetValueKind($n).ToString()
                    Data   = $k.GetValue($n, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                })
            } else {
                $values.Add([pscustomobject]@{ Name = $n; Exists = $false; Kind = $null; Data = $null })
            }
        }
        $entries.Add([pscustomobject]@{
            Key        = $m.Key
            KeyExisted = ($null -ne $k)
            Values     = $values.ToArray()
        })
        if ($null -ne $k) { $k.Close() }
    }
    $base.Close()

    $snap = [pscustomobject]@{
        Tool          = 'bye-tcp-internet'
        SchemaVersion = 1
        Created       = (Get-Date).ToString('s')
        Computer      = $env:COMPUTERNAME
        Entries       = $entries.ToArray()
    }
    $json = $snap | ConvertTo-Json -Depth 6

    $file = Join-Path $SnapDir ("{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Set-Content -LiteralPath $file -Value $json -Encoding UTF8
    $present = @($entries | ForEach-Object { $_.Values } | Where-Object { $_.Exists }).Count
    $total   = @($entries | ForEach-Object { $_.Values }).Count
    Write-Status "Snapshot saved: $file ($present of $total managed values currently set)" 'OK'

    if (-not (Test-Path -LiteralPath $Baseline)) {
        Copy-Item -LiteralPath $file -Destination $Baseline
        Write-Status "Baseline created (state before first apply): $Baseline" 'OK'
    } else {
        Write-Status 'Baseline already exists - it keeps the original pre-apply state.' 'INFO'
    }
}

# --------------------------------------------------------------- Restore ----
function Invoke-Restore {
    $file = if ($Path) { $Path } else { $Baseline }
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Snapshot not found: $file (nothing to restore - was apply.bat run on this machine?)"
    }
    $snap = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    if ($snap.Tool -ne 'bye-tcp-internet' -or $snap.SchemaVersion -ne 1) {
        throw "Not a bye-tcp-internet snapshot (schema 1): $file"
    }
    Write-Status "Restoring from: $file (taken $($snap.Created) on $($snap.Computer))"

    $base = Open-Base
    $changed = 0; $same = 0; $skipped = 0

    foreach ($entry in $snap.Entries) {
        $m = $Managed | Where-Object { $_.Key -eq $entry.Key }
        if (-not $m) { Write-Status "ignored (not a managed key): $($entry.Key)" 'WARN'; $skipped++; continue }

        foreach ($v in $entry.Values) {
            if ($m.Names -notcontains $v.Name) {
                Write-Status "ignored (not a managed value): $($entry.Key)\$($v.Name)" 'WARN'; $skipped++; continue
            }
            $label = "$($entry.Key)\$($v.Name)"
            $cur   = $base.OpenSubKey($entry.Key, $false)
            $has   = ($null -ne $cur -and ($cur.GetValueNames() -contains $v.Name))
            $now   = if ($has) { $cur.GetValue($v.Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
            if ($null -ne $cur) { $cur.Close() }

            if ($v.Exists) {
                # (no switch here: 'continue' inside a switch would not skip the loop item)
                if ($v.Kind -eq 'DWord') {
                    $kind = [Microsoft.Win32.RegistryValueKind]::DWord;  $data = [int]$v.Data
                } elseif ($v.Kind -eq 'String') {
                    $kind = [Microsoft.Win32.RegistryValueKind]::String; $data = [string]$v.Data
                } else {
                    Write-Status "unsupported type '$($v.Kind)': $label" 'WARN'; $skipped++; continue
                }
                if ($has -and $now -eq $data) { $same++; continue }
                if ($PSCmdlet.ShouldProcess($label, "set $(Format-Data $data)")) {
                    $w = $base.CreateSubKey($entry.Key)
                    $w.SetValue($v.Name, $data, $kind)
                    $w.Close()
                }
                Write-Status ("{0} : {1} -> {2}" -f $label, (Format-Data $now), (Format-Data $data)) 'SET'
                $changed++
            } else {
                if (-not $has) { $same++; continue }
                if ($PSCmdlet.ShouldProcess($label, 'delete value')) {
                    $w = $base.OpenSubKey($entry.Key, $true)
                    $w.DeleteValue($v.Name, $false)
                    $w.Close()
                }
                Write-Status ("{0} : {1} -> <deleted>" -f $label, (Format-Data $now)) 'DEL'
                $changed++
            }
        }

        # Remove a key we would otherwise leave behind empty, but only if it did not exist before.
        if (-not $entry.KeyExisted) {
            $k = $base.OpenSubKey($entry.Key, $false)
            if ($null -ne $k) {
                $empty = ($k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0)
                $k.Close()
                if ($empty -and $PSCmdlet.ShouldProcess($entry.Key, 'delete empty key (did not exist before)')) {
                    $base.DeleteSubKey($entry.Key, $false)
                    Write-Status "removed empty key: $($entry.Key)" 'DEL'
                }
            }
        }
    }
    $base.Close()

    Write-Host ''
    Write-Status "changed: $changed   already correct: $same   ignored: $skipped" 'OK'

    if (-not $WhatIfPreference -and -not $Path -and (Test-Path -LiteralPath $Baseline)) {
        $archive = Join-Path $SnapDir ("restored-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Move-Item -LiteralPath $Baseline -Destination $archive
        Write-Status "Baseline archived as $archive - next apply records a fresh baseline." 'INFO'
    }
    Write-Status 'Reboot to make the restored values take effect.' 'INFO'
}

# ------------------------------------------------------------------ List ----
function Invoke-List {
    if (-not (Test-Path -LiteralPath $SnapDir)) { Write-Status 'No snapshots (directory does not exist).'; return }
    $files = Get-ChildItem -LiteralPath $SnapDir -Filter '*.json' | Sort-Object LastWriteTime
    if (-not $files) { Write-Status 'No snapshots.'; return }
    foreach ($f in $files) {
        $tag = if ($f.Name -eq 'baseline.json') { '  <- baseline (default restore point)' } else { '' }
        Write-Host ("  {0}  {1}{2}" -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $f.Name, $tag)
    }
}

# ------------------------------------------------------------------ Main ----
try {
    $modes = @($Backup, $Restore, $List | Where-Object { $_ }).Count
    if ($modes -ne 1) {
        Write-Host 'Usage: snapshot.ps1 -Backup | -Restore [-Path file] [-WhatIf] | -List'
        exit 2
    }
    if ($Backup)  { Invoke-Backup }
    if ($Restore) { Invoke-Restore }
    if ($List)    { Invoke-List }
    exit 0
} catch {
    Write-Status $_.Exception.Message 'FAIL'
    exit 1
}
