# Script de configuration automatique - Automatic Subtitles (Portable)
# Execute avec: powershell -ExecutionPolicy Bypass -File setup.ps1

$ErrorActionPreference = "Stop"
$baseDir = $PSScriptRoot

# Forcer TLS 1.2 pour les telechargements HTTPS (important pour GitHub)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Configuration Automatic Subtitles" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Creation des dossiers
$folders = @("bin\ffmpeg", "bin\whisper", "bin\python", "output", "temp")
foreach ($folder in $folders) {
    $path = Join-Path $baseDir $folder
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "[OK] Dossier cree: $folder" -ForegroundColor Green
    }
}

# Fonction de telechargement avec barre de progression
function Download-File {
    param($url, $output, $description)
    Write-Host "[...] Telechargement: $description" -ForegroundColor Yellow
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing
        Write-Host "[OK] $description telecharge" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "[ERREUR] Echec du telechargement: $_" -ForegroundColor Red
        return $false
    }
}

# ============================================
# 1. FFmpeg
# ============================================
Write-Host ""
Write-Host "--- FFmpeg ---" -ForegroundColor Magenta
$ffmpegExe = Join-Path $baseDir "bin\ffmpeg\ffmpeg.exe"
if (Test-Path $ffmpegExe) {
    Write-Host "[OK] FFmpeg deja installe" -ForegroundColor Green
} else {
    $ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    $ffmpegZip = Join-Path $baseDir "temp\ffmpeg.zip"

    if (Download-File $ffmpegUrl $ffmpegZip "FFmpeg") {
        Write-Host "[...] Extraction de FFmpeg..." -ForegroundColor Yellow
        Expand-Archive -Path $ffmpegZip -DestinationPath (Join-Path $baseDir "temp\ffmpeg_extract") -Force

        # Trouver le dossier extrait et copier les executables
        $extractedDir = Get-ChildItem (Join-Path $baseDir "temp\ffmpeg_extract") -Directory | Select-Object -First 1
        $binPath = Join-Path $extractedDir.FullName "bin"
        Copy-Item (Join-Path $binPath "*") (Join-Path $baseDir "bin\ffmpeg") -Force

        Write-Host "[OK] FFmpeg installe" -ForegroundColor Green
    }
}

# ============================================
# 2. whisper.cpp
# ============================================
Write-Host ""
Write-Host "--- whisper.cpp ---" -ForegroundColor Magenta
$whisperExe = Join-Path $baseDir "bin\whisper\main.exe"
if (Test-Path $whisperExe) {
    Write-Host "[OK] whisper.cpp deja installe" -ForegroundColor Green
} else {
    $whisperZip = Join-Path $baseDir "temp\whisper.zip"
    $whisperDownloaded = $false

    # Methode 1: Essayer via l'API GitHub
    Write-Host "[...] Recherche de la derniere version de whisper.cpp..." -ForegroundColor Yellow
    try {
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/ggerganov/whisper.cpp/releases/latest" -UseBasicParsing
        $asset = $releases.assets | Where-Object { $_.name -match "whisper.*win.*x64.*zip" -or $_.name -match "whisper.*bin-x64.*zip" } | Select-Object -First 1

        if ($asset) {
            $whisperDownloaded = Download-File $asset.browser_download_url $whisperZip "whisper.cpp"
        }
    } catch {
        Write-Host "[INFO] API GitHub non accessible, utilisation de l'URL directe..." -ForegroundColor Yellow
    }

    # Methode 2: URL directe de secours (version stable connue)
    if (-not $whisperDownloaded) {
        $fallbackUrl = "https://github.com/ggerganov/whisper.cpp/releases/download/v1.7.2/whisper-bin-x64.zip"
        Write-Host "[...] Tentative avec URL de secours (v1.7.2)..." -ForegroundColor Yellow
        $whisperDownloaded = Download-File $fallbackUrl $whisperZip "whisper.cpp v1.7.2"
    }

    if ($whisperDownloaded -and (Test-Path $whisperZip)) {
        Write-Host "[...] Extraction de whisper.cpp..." -ForegroundColor Yellow
        Expand-Archive -Path $whisperZip -DestinationPath (Join-Path $baseDir "bin\whisper") -Force
        Write-Host "[OK] whisper.cpp installe" -ForegroundColor Green
    } else {
        Write-Host "[ATTENTION] Telechargement echoue." -ForegroundColor Yellow
        Write-Host "    Telechargez manuellement depuis: https://github.com/ggerganov/whisper.cpp/releases" -ForegroundColor Yellow
        Write-Host "    Extrayez dans: bin\whisper\" -ForegroundColor Yellow
    }
}

# ============================================
# 3. Modele Whisper (base)
# ============================================
Write-Host ""
Write-Host "--- Modele Whisper (base) ---" -ForegroundColor Magenta
$modelFile = Join-Path $baseDir "bin\whisper\ggml-base.bin"
if (Test-Path $modelFile) {
    Write-Host "[OK] Modele deja telecharge" -ForegroundColor Green
} else {
    $modelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
    Download-File $modelUrl $modelFile "Modele ggml-base.bin (~148 Mo)"
}

# ============================================
# 4. Python Embedded
# ============================================
Write-Host ""
Write-Host "--- Python Embedded ---" -ForegroundColor Magenta
$pythonExe = Join-Path $baseDir "bin\python\python.exe"
if (Test-Path $pythonExe) {
    Write-Host "[OK] Python deja installe" -ForegroundColor Green
} else {
    $pythonUrl = "https://www.python.org/ftp/python/3.12.4/python-3.12.4-embed-amd64.zip"
    $pythonZip = Join-Path $baseDir "temp\python.zip"

    if (Download-File $pythonUrl $pythonZip "Python 3.12 Embedded") {
        Write-Host "[...] Extraction de Python..." -ForegroundColor Yellow
        Expand-Archive -Path $pythonZip -DestinationPath (Join-Path $baseDir "bin\python") -Force
        Write-Host "[OK] Python installe" -ForegroundColor Green
    }
}

# ============================================
# Nettoyage
# ============================================
Write-Host ""
Write-Host "--- Nettoyage ---" -ForegroundColor Magenta
$tempDir = Join-Path $baseDir "temp"
if (Test-Path $tempDir) {
    Remove-Item $tempDir -Recurse -Force
    Write-Host "[OK] Fichiers temporaires supprimes" -ForegroundColor Green
}

# ============================================
# Resume
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Configuration terminee !" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verifiez que les fichiers suivants existent:" -ForegroundColor White
Write-Host "  - bin\ffmpeg\ffmpeg.exe" -ForegroundColor Gray
Write-Host "  - bin\whisper\main.exe" -ForegroundColor Gray
Write-Host "  - bin\whisper\ggml-base.bin" -ForegroundColor Gray
Write-Host "  - bin\python\python.exe" -ForegroundColor Gray
Write-Host ""
Write-Host "Vous pouvez maintenant utiliser 'run.bat'" -ForegroundColor Green
Write-Host ""
Read-Host "Appuyez sur Entree pour fermer"
