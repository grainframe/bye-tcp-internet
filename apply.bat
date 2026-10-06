@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1

:: ==========================================================
:: bye-tcp-internet - Interactive Installer
:: Author: softgrain / github.com/grainframe/bye-tcp-internet
:: Version: 1.3.0
:: ==========================================================

:: --- Admin check ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR] Administrator privileges required.
    echo  Right-click apply.bat and select "Run as administrator".
    echo.
    pause
    exit /b 1
)

:menu
cls
echo.
echo  ==========================================
echo   bye-tcp-internet  v1.3.0
echo   github.com/grainframe/bye-tcp-internet
echo  ==========================================
echo.
echo   Select profile to apply:
echo.
echo   [1]  universal      - Baseline (workstations, servers)
echo   [2]  gmvelocity     - Low-Latency (gaming)
echo.
echo   [3]  Rollback universal  (deletes overrides)
echo   [4]  Rollback gmvelocity (deletes overrides)
echo.
echo   [5]  Run verify.ps1 (post-apply check)
echo   [6]  Restore ORIGINAL state from snapshot (exact)
echo   [0]  Exit
echo.
set /p choice=" > "

if "%choice%"=="1" goto apply_universal
if "%choice%"=="2" goto apply_gmvelocity
if "%choice%"=="3" goto rollback_universal
if "%choice%"=="4" goto rollback_gmvelocity
if "%choice%"=="5" goto run_verify
if "%choice%"=="6" goto restore_snapshot
if "%choice%"=="0" exit /b 0

echo.
echo  Invalid choice. Try again.
timeout /t 1 >nul
goto menu


:apply_universal
cls
echo.
echo  Applying: universal.reg
echo  ------------------------------------------
if not exist "%~dp0universal.reg" (
    echo  [ERROR] universal.reg not found in current directory.
    goto end
)
call :snapshot_backup || goto end
reg import "%~dp0universal.reg"
if %errorlevel% equ 0 (
    echo  [OK] universal.reg applied successfully.
) else (
    echo  [ERROR] Failed to apply universal.reg.
    goto end
)
goto reboot_prompt


:apply_gmvelocity
cls
echo.
echo  Applying: gmvelocity.reg
echo  ------------------------------------------
if not exist "%~dp0gmvelocity.reg" (
    echo  [ERROR] gmvelocity.reg not found in current directory.
    goto end
)
call :snapshot_backup || goto end
reg import "%~dp0gmvelocity.reg"
if %errorlevel% equ 0 (
    echo  [OK] gmvelocity.reg applied successfully.
) else (
    echo  [ERROR] Failed to apply gmvelocity.reg.
    goto end
)
goto reboot_prompt


:rollback_universal
cls
echo.
echo  Applying: universal-rollback.reg
echo  ------------------------------------------
if not exist "%~dp0universal-rollback.reg" (
    echo  [ERROR] universal-rollback.reg not found.
    goto end
)
reg import "%~dp0universal-rollback.reg"
if %errorlevel% equ 0 (
    echo  [OK] Rollback applied. All universal overrides removed.
) else (
    echo  [ERROR] Rollback failed.
    goto end
)
goto reboot_prompt


:rollback_gmvelocity
cls
echo.
echo  Applying: gmvelocity-rollback.reg
echo  ------------------------------------------
if not exist "%~dp0gmvelocity-rollback.reg" (
    echo  [ERROR] gmvelocity-rollback.reg not found.
    goto end
)
reg import "%~dp0gmvelocity-rollback.reg"
if %errorlevel% equ 0 (
    echo  [OK] Rollback applied. All gmvelocity overrides removed.
) else (
    echo  [ERROR] Rollback failed.
    goto end
)
goto reboot_prompt


:run_verify
cls
echo.
echo  Running verify.ps1...
echo  ------------------------------------------
if not exist "%~dp0verify.ps1" (
    echo  [ERROR] verify.ps1 not found.
    goto end
)
powershell -ExecutionPolicy Bypass -File "%~dp0verify.ps1"
goto end


:restore_snapshot
cls
echo.
echo  Restoring original state from snapshot
echo  ------------------------------------------
if not exist "%~dp0snapshot.ps1" (
    echo  [ERROR] snapshot.ps1 not found.
    goto end
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0snapshot.ps1" -Restore
if %errorlevel% equ 0 (
    echo  [OK] Original values restored.
) else (
    echo  [ERROR] Restore failed. Nothing else was changed.
    goto end
)
goto reboot_prompt


:reboot_prompt
echo.
echo  ------------------------------------------
echo  Changes take effect after reboot.
echo.
set /p reboot=" Reboot now? [Y/N] > "
if /i "%reboot%"=="Y" shutdown /r /t 5 /c "bye-tcp-internet: applying network profile"
if /i "%reboot%"=="y" shutdown /r /t 5 /c "bye-tcp-internet: applying network profile"


:end
echo.
pause
exit /b 0


:snapshot_backup
if not exist "%~dp0snapshot.ps1" (
    echo  [ERROR] snapshot.ps1 not found - refusing to apply without a snapshot.
    exit /b 1
)
echo  Saving snapshot of current values...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0snapshot.ps1" -Backup
if %errorlevel% neq 0 (
    echo  [ERROR] Snapshot failed. Nothing was changed.
    exit /b 1
)
exit /b 0
