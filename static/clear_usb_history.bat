@echo off
:: Auto-elevate as admin
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

echo ============================
echo Clearing USB History...
echo ============================

:: 1. Clear Event Viewer logs
echo Clearing Event Logs...
powershell -Command "wevtutil clear-log 'Microsoft-Windows-DriverFrameworks-UserMode/Operational'"
powershell -Command "wevtutil clear-log 'System'"
powershell -Command "wevtutil clear-log 'Setup'"

:: 2. Delete USBSTOR and Enum\USB Registry keys
echo Deleting USB Registry Keys...
powershell -Command "Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR' -Recurse -Force -ErrorAction SilentlyContinue"
powershell -Command "Remove-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB' -Recurse -Force -ErrorAction SilentlyContinue"

:: 3. Delete USB setup log file
echo Deleting setupapi.dev.log...
del /f /q "%windir%\inf\setupapi.dev.log"

echo.
echo USB connection history cleared.
echo Please reboot your system for full effect.
pause
