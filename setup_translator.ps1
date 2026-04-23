# Setup Video Translator - Installation des dépendances
# Installe PyTorch, Demucs, Coqui TTS dans l'environnement Python embedded

Add-Type -AssemblyName PresentationFramework

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonDir = Join-Path $scriptDir "bin\python"
$pythonExe = Join-Path $pythonDir "python.exe"
$pipExe = Join-Path $pythonDir "Scripts\pip.exe"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Video Translator - Installation   " -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Vérifier Python
if (-not (Test-Path $pythonExe)) {
    Write-Host "[ERREUR] Python non trouvé dans bin\python\" -ForegroundColor Red
    Write-Host "Exécutez d'abord INSTALLER.bat pour installer les composants de base." -ForegroundColor Yellow
    Read-Host "Appuyez sur Entrée pour quitter"
    exit 1
}

Write-Host "[OK] Python trouvé: $pythonExe" -ForegroundColor Green

# Vérifier/Installer pip
Write-Host ""
Write-Host "[1/4] Configuration de pip..." -ForegroundColor Yellow

# Modifier pth file pour permettre l'installation de packages
$pthFile = Get-ChildItem -Path $pythonDir -Filter "python*._pth" | Select-Object -First 1
if ($pthFile) {
    $pthContent = Get-Content $pthFile.FullName -Raw
    if ($pthContent -notmatch "^import site" -and $pthContent -notmatch "^\s*import site") {
        Write-Host "  Activation des packages site..." -ForegroundColor Gray
        $pthContent = $pthContent + "`nimport site"
        Set-Content -Path $pthFile.FullName -Value $pthContent
    }
}

# Installer pip si nécessaire
if (-not (Test-Path $pipExe)) {
    Write-Host "  Installation de pip..." -ForegroundColor Gray
    & $pythonExe -m ensurepip --upgrade 2>$null
    if (-not (Test-Path $pipExe)) {
        # Télécharger get-pip.py
        $getPip = Join-Path $env:TEMP "get-pip.py"
        Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $getPip
        & $pythonExe $getPip
    }
}

& $pythonExe -m pip install --upgrade pip --quiet 2>$null
Write-Host "[OK] pip configuré" -ForegroundColor Green

# Installer PyTorch
Write-Host ""
Write-Host "[2/4] Installation de PyTorch (CPU)..." -ForegroundColor Yellow
Write-Host "  Cela peut prendre plusieurs minutes..." -ForegroundColor Gray

& $pythonExe -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu --quiet

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] PyTorch installé" -ForegroundColor Green
} else {
    Write-Host "[WARN] Problème avec PyTorch, tentative alternative..." -ForegroundColor Yellow
    & $pythonExe -m pip install torch torchaudio --quiet
}

# Installer Demucs
Write-Host ""
Write-Host "[3/4] Installation de Demucs (séparation vocale)..." -ForegroundColor Yellow
Write-Host "  Cela peut prendre quelques minutes..." -ForegroundColor Gray

& $pythonExe -m pip install demucs --quiet

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Demucs installé" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Échec de l'installation de Demucs" -ForegroundColor Red
}

# Installer edge-tts
Write-Host ""
Write-Host "[4/4] Installation de edge-tts (synthèse vocale Microsoft)..." -ForegroundColor Yellow

& $pythonExe -m pip install edge-tts pysrt scipy numpy --quiet

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] edge-tts installé" -ForegroundColor Green
} else {
    Write-Host "[ERREUR] Échec de l'installation de edge-tts" -ForegroundColor Red
}

# Vérification finale
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Vérification de l'installation     " -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan

$testScript = @"
import sys
errors = []

try:
    import torch
    print(f"[OK] PyTorch {torch.__version__}")
except ImportError as e:
    errors.append(f"PyTorch: {e}")

try:
    import demucs
    print("[OK] Demucs")
except ImportError as e:
    errors.append(f"Demucs: {e}")

try:
    import edge_tts
    print("[OK] edge-tts")
except ImportError as e:
    errors.append(f"edge-tts: {e}")

try:
    import pysrt
    print("[OK] pysrt")
except ImportError as e:
    errors.append(f"pysrt: {e}")

if errors:
    print("\n[ERREURS]")
    for err in errors:
        print(f"  - {err}")
    sys.exit(1)
else:
    print("\n[SUCCESS] Tous les composants sont installés!")
    sys.exit(0)
"@

$testFile = Join-Path $env:TEMP "test_translator.py"
Set-Content -Path $testFile -Value $testScript -Encoding UTF8

& $pythonExe $testFile

Remove-Item $testFile -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan

if ($LASTEXITCODE -eq 0) {
    Write-Host "  Installation terminée avec succès! " -ForegroundColor Green
    Write-Host ""
    Write-Host "Vous pouvez maintenant utiliser Video Translator.bat" -ForegroundColor White
} else {
    Write-Host "  Installation incomplète            " -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Certains composants n'ont pas pu être installés." -ForegroundColor Yellow
    Write-Host "Vérifiez votre connexion internet et réessayez." -ForegroundColor Yellow
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Appuyez sur Entrée pour fermer"
