@echo off
setlocal

set SCRIPT_DIR=%~dp0
set PYTHON=%SCRIPT_DIR%bin\python\python.exe

if not exist "%PYTHON%" (
    echo.
    echo  ERROR: Python not found at %PYTHON%
    echo  Run INSTALLER.bat first.
    echo.
    pause
    exit /b 1
)

"%PYTHON%" "%SCRIPT_DIR%translate_cli.py" %*

echo.
pause
