@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0burn_360_subs.ps1"
