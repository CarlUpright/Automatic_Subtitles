@echo off
title Installation Video Translator
cd /d "%~dp0"
echo =====================================
echo  Installation des dependances
echo  Video Translator
echo =====================================
echo.
echo Cette installation va telecharger:
echo  - PyTorch (~2 GB)
echo  - Demucs (~300 MB)
echo  - edge-tts (leger)
echo.
echo Espace disque requis: ~2.5 GB
echo.
pause
powershell -ExecutionPolicy Bypass -File "setup_translator.ps1"
