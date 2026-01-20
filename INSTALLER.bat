@echo off
echo ========================================
echo   Installation des composants portables
echo ========================================
echo.
echo Ce script va telecharger:
echo   - FFmpeg (~90 Mo)
echo   - whisper.cpp (~20 Mo)
echo   - Modele Whisper base (~148 Mo)
echo   - Python embedded (~15 Mo)
echo.
echo Total: environ 280 Mo
echo.
pause
powershell -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
