@echo off
setlocal

set SCRIPT_DIR=%~dp0

where py >nul 2>nul
if %ERRORLEVEL%==0 (
    py -3 "%SCRIPT_DIR%verify_ip.py" %*
) else (
    python "%SCRIPT_DIR%verify_ip.py" %*
)

set RC=%ERRORLEVEL%
echo.
echo verify_ip finished with exit code %RC%

if "%1"=="--no-pause" goto :end
pause

:end
exit /b %RC%
