@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CodexApp.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Codex installation/update failed with exit code %EXIT_CODE%.
) else (
    echo Done.
)
pause
exit /b %EXIT_CODE%
