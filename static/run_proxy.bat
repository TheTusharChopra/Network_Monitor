@echo off
setlocal

:: Get the directory of the batch file
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%agent_with_proxy.ps1"
set "DEBUG_LOG=%SCRIPT_DIR%run_agent_debug.log"

:: Log debug information
echo %DATE% %TIME% - Starting run_proxy.bat >> "%DEBUG_LOG%"
echo %DATE% %TIME% - Script directory: %SCRIPT_DIR% >> "%DEBUG_LOG%"
echo %DATE% %TIME% - PowerShell script path: %PS_SCRIPT% >> "%DEBUG_LOG%"

:: Check if agent_with_proxy.ps1 exists
if not exist "%PS_SCRIPT%" (
    echo %DATE% %TIME% - ERROR: agent_with_proxy.ps1 not found at %PS_SCRIPT% >> "%DEBUG_LOG%"
    echo ERROR: agent_with_proxy.ps1 not found at %PS_SCRIPT%
    echo Please ensure agent_with_proxy.ps1 is in the same directory as run_proxy.bat
    exit /b 1
)

:: Change to the batch file's directory
cd /d "%SCRIPT_DIR%"
echo %DATE% %TIME% - Changed working directory to: %CD% >> "%DEBUG_LOG%"

:: Check if already running as Administrator
net session >nul 2>&1
if %ERRORLEVEL% equ 0 (
    :: Already elevated, run PowerShell script directly
    echo %DATE% %TIME% - Running as Administrator, executing %PS_SCRIPT% >> "%DEBUG_LOG%"
    powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
) else (
    :: Not elevated, relaunch as Administrator
    echo %DATE% %TIME% - Not running as Administrator, elevating... >> "%DEBUG_LOG%"
    powershell -Command "Start-Process cmd -ArgumentList '/c cd /d %SCRIPT_DIR% && powershell -ExecutionPolicy Bypass -File \"%PS_SCRIPT%\"' -Verb RunAs"
)

endlocal