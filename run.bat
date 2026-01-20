@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

REM === Configuration ===
set "SCRIPT_DIR=%~dp0"
set "FFMPEG=%SCRIPT_DIR%bin\ffmpeg\ffmpeg.exe"
set "WHISPER=%SCRIPT_DIR%bin\whisper\Release\whisper-cli.exe"
set "MODEL=%SCRIPT_DIR%bin\whisper\ggml-base.bin"

REM Verification des dependances
if not exist "!FFMPEG!" (
    echo [ERREUR] FFmpeg non trouve: !FFMPEG!
    echo Executez setup.ps1 d'abord.
    pause
    exit /b 1
)
if not exist "!WHISPER!" (
    echo [ERREUR] whisper-cli.exe non trouve: !WHISPER!
    echo Executez INSTALLER.bat d'abord.
    pause
    exit /b 1
)
if not exist "!MODEL!" (
    echo [ERREUR] Modele Whisper non trouve: !MODEL!
    echo Executez setup.ps1 d'abord.
    pause
    exit /b 1
)

if "%~1"=="" (
    echo.
    echo ========================================
    echo   Automatic Subtitles - Version Portable
    echo ========================================
    echo.
    echo Glissez-deposez des fichiers audio ou un dossier sur ce script !
    echo.
    echo Formats supportes: mp3, m4a, wav, flac, aac, ogg, wma
    echo.
    pause
    exit /b
)

set count=0
set errors=0

:loop
if "%~1"=="" goto end

REM Verifie si c'est un dossier
if exist "%~1\" (
    echo.
    echo Traitement du dossier : %~1
    for %%F in ("%~1\*.mp3" "%~1\*.m4a" "%~1\*.wav" "%~1\*.flac" "%~1\*.aac" "%~1\*.ogg" "%~1\*.wma") do (
        call :convert "%%F"
    )
) else (
    REM C'est un fichier
    call :convert "%~1"
)

shift
goto loop

:convert
set "input=%~1"
set "basename=%~n1"
set "filepath=%~dp1"

REM Enleve le backslash final si present
if "!filepath:~-1!"=="\" set "filepath=!filepath:~0,-1!"

REM Genere le timestamp
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set timestamp=!datetime:~0,8!_!datetime:~8,6!

set "output=!filepath!\!basename!_!timestamp!.mp4"
set "srtfile=!filepath!\!basename!.srt"

REM Convertit les backslashes en slashes et echappe les deux-points pour ffmpeg
set "srtfile_ffmpeg=!srtfile:\=/!"
set "srtfile_ffmpeg=!srtfile_ffmpeg::=\\:!"

echo.
echo ========================================
echo [!count!] Traitement : %~nx1
echo ========================================

echo [1/3] Conversion audio en WAV 16kHz...
set "wavfile=!filepath!\!basename!_temp.wav"
"!FFMPEG!" -y -i "!input!" -ar 16000 -ac 1 -c:a pcm_s16le "!wavfile!" -hide_banner -loglevel error

if not exist "!wavfile!" (
    echo    [ERREUR] Conversion WAV echouee
    set /a errors+=1
    set /a count+=1
    goto :eof
)

echo [2/3] Transcription avec Whisper...
"!WHISPER!" -m "!MODEL!" -l fr -osrt -of "!filepath!\!basename!" -f "!wavfile!"

REM Supprimer le fichier WAV temporaire
del "!wavfile!" 2>nul

if not exist "!srtfile!" (
    echo    [ERREUR] Fichier SRT non cree
    set /a errors+=1
    set /a count+=1
    goto :eof
) else (
    echo    [OK] Sous-titres generes
)

echo [3/3] Creation de la video avec sous-titres...
"!FFMPEG!" -i "!input!" -filter_complex "[0:a]showwaves=s=854x480:mode=p2p:colors=blue:draw=full,subtitles=!srtfile_ffmpeg!:force_style='FontName=Arial,FontSize=20,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=3'[v]" -map "[v]" -map 0:a -c:v libx264 -crf 30 -preset fast -c:a aac -b:a 96k -pix_fmt yuv420p -y "!output!" -hide_banner -loglevel error

if !errorlevel!==0 (
    echo    [OK] Video creee : !basename!_!timestamp!.mp4
    REM Supprime le fichier .srt temporaire
    del "!srtfile!" 2>nul
) else (
    echo    [ERREUR] Conversion video echouee
    set /a errors+=1
)

set /a count+=1
goto :eof

:end
echo.
echo ========================================
if !errors!==0 (
    echo   Termine ! !count! fichier(s) traite(s) avec succes.
) else (
    echo   Termine ! !count! fichier(s) traite(s), !errors! erreur(s).
)
echo ========================================
echo.
pause
