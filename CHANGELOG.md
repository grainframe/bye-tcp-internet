# Changelog

All notable changes to **bye-tcp-internet** are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.3.0] — 2026-10-06

### Added
- `snapshot.ps1` — exact-state backup/restore of every registry value the profiles write. Records exists / type / data; restore puts the original data back or deletes values that did not exist (and keys that did not exist, if left empty). First snapshot is kept as `baseline.json` (state before first apply) and is the default restore point. Supports `-WhatIf` and `-List`. Writes only the values it manages; snapshot directory is Administrators/SYSTEM only.
- `apply.bat`: snapshot is taken automatically before every apply (apply is aborted if the snapshot fails); new menu item `[6]` restores the original state.
- `verify.ps1`: "Effective state" block compares registry values with the live stack (`EcnCapability`, `Timestamps`, dynamic port range) and prints `[WARN]` on mismatch; `PASS/FAIL/WARN` summary; exit code `0`/`1`.
- `.gitattributes` — `.reg`, `.bat`, `.ps1` are stored as committed (CRLF).

### Fixed
- `verify.ps1`: the `NetworkThrottlingIndex` check could never pass — a `REG_DWORD` of `0xFFFFFFFF` is read as signed Int32 (`-1`), which never equals `4294967295`. DWORD values are now normalised to unsigned.
- `verify.ps1`: after a rollback every check printed `[FAIL]`. With no profile active it now only lists current values.
- Non-ASCII characters removed from `.reg`, `.bat`, `.ps1` (BOM-less UTF-8 is read as ANSI by Windows PowerShell 5.1 and may be misread by regedit, garbling text); files use CRLF.
- README: rollback description corrected. Static rollback files delete values, except `NetworkThrottlingIndex` / `SystemResponsiveness` (set to `10` / `20`); `Tasks\Games` values are deleted, not reset. Exact restore is `snapshot.ps1 -Restore`.

### Changed
- Version `1.3.0` in all file headers. Registry values written by the profiles are unchanged.

---

## [1.2.0] — 2026-03-05

### Added
- `verify.ps1` — post-apply verification script. Auto-detects active profile (UNIVERSAL / GMVELOCITY / ROLLBACK), checks all registry keys against expected values, prints live `netsh` and `Get-NetTCPSetting` output.
- `apply.bat` — interactive installer. Admin elevation check, profile selection menu, applies chosen `.reg`, prompts for reboot.
- `CHANGELOG.md` — full version history (this file).
- `EnableECNCapability=0` added to `universal.reg` (was missing; ECN causes compatibility issues on many ISP networks).
- `DefaultTTL`, `EnablePMTUBHDetect`, `Tcp1323Opts`, `QoS Psched` keys added to `gmvelocity.reg` — profile is now a complete superset of `universal.reg`.
- `MaxNegativeCacheTtl=0` added to `gmvelocity.reg` DNS section.

### Changed
- `gmvelocity.reg`: duplicate `[Tcpip\Parameters]` sections merged into one.
- `SystemResponsiveness` set to `0` in `gmvelocity.reg` (was `0x14`); `0x14` kept in `universal.reg`.
- Author tag corrected: `ceo14` → `softgrain` across all files.
- All `.reg` comments rewritten to explain *why*, not just *what*.

### Fixed
- `universal-rollback.reg` and `gmvelocity-rollback.reg` now delete **all** keys written by their respective apply files (previously `Tcp1323Opts`, `DefaultTTL`, `EnablePMTUBHDetect`, `QoS Psched` were missing from rollbacks).

---

## [1.1.0] — 2026-03-03

### Added
- `gmvelocity.reg` — Low-Latency gaming profile.
- `gmvelocity-rollback.reg` — rollback for gaming profile.
- MMCSS `Tasks\Games` priority overrides (`GPU Priority`, `Scheduling Category`, `SFIO Priority`).
- DNS aggressive mode: `NegativeCacheTime=0`, `NetFailureCacheTime=0`.
- `EnableECNCapability=0` in gaming profile.
- Rollback architecture: both profiles now ship with dedicated rollback files.

### Changed
- README restructured: added Profiles section, Technical Scope, Methodology & Safety.

---

## [1.0.0] — 2026-02-XX

### Added
- Initial release.
- `universal.reg` — baseline TCP/IP profile for Windows 10/11.
- `universal-rollback.reg` — full rollback to Windows hardcoded defaults.
- Core TCP keys: `DefaultTTL`, `EnablePMTUDiscovery`, `SackOpts`, `Tcp1323Opts`, `MaxUserPort`, `TcpTimedWaitDelay`.
- DNS tuning: `MaxNegativeCacheTtl`, `NegativeCacheTime`, `NetFailureCacheTime`.
- Multimedia throttling: `NetworkThrottlingIndex=0xFFFFFFFF`, `SystemResponsiveness=0x14`.
- QoS: `NonBestEffortLimit=0`.
