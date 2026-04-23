@echo off
title Video Translator - Traduction avec Doublage
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "translate_gui.ps1"
