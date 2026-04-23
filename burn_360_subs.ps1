# burn_360_subs.ps1
# Burn subtitles into 360 video files with correct spherical positioning
# Supported projections: 360 3D Top-Bottom (more to come)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ffmpeg    = Join-Path $scriptDir "bin\ffmpeg\ffmpeg.exe"
$ffprobe   = Join-Path $scriptDir "bin\ffmpeg\ffprobe.exe"

# ── Check dependencies ───────────────────────────────────────────────────────
if (-not (Test-Path $ffmpeg)) {
    Write-Host "[ERREUR] FFmpeg non trouve: $ffmpeg" -ForegroundColor Red
    Write-Host "         Executez INSTALLER.bat d'abord."
    Read-Host "`nAppuyez sur Entree pour quitter"
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  360 Subtitle Burner" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ── Input video ──────────────────────────────────────────────────────────────
$videoPath = (Read-Host "Fichier video (chemin)").Trim().Trim('"')
if (-not (Test-Path -LiteralPath $videoPath)) {
    Write-Host "[ERREUR] Fichier non trouve: $videoPath" -ForegroundColor Red
    Read-Host "`nAppuyez sur Entree pour quitter"
    exit 1
}

# ── Input subtitles ──────────────────────────────────────────────────────────
$subPath = (Read-Host "Fichier sous-titres (.srt)").Trim().Trim('"')
if (-not (Test-Path -LiteralPath $subPath)) {
    Write-Host "[ERREUR] Fichier non trouve: $subPath" -ForegroundColor Red
    Read-Host "`nAppuyez sur Entree pour quitter"
    exit 1
}

# ── Projection type ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Type de projection :" -ForegroundColor Yellow
Write-Host "  [1] 360 3D Top-Bottom (TB)"
Write-Host ""
$projChoice = (Read-Host "Choix [1]").Trim()
if ([string]::IsNullOrWhiteSpace($projChoice)) { $projChoice = "1" }

# ── Probe video dimensions ───────────────────────────────────────────────────
Write-Host ""
Write-Host "[...] Detection des dimensions..." -NoNewline

$probeOut = & $ffprobe -v error -select_streams v:0 `
    -show_entries stream=width,height -of csv=p=0 `
    "$videoPath" 2>$null

$dims = ($probeOut.Trim()) -split ","
if ($dims.Count -lt 2 -or -not [int]::TryParse($dims[0], [ref]0)) {
    Write-Host " echec" -ForegroundColor Red
    Write-Host "[ERREUR] Impossible de lire les dimensions de la video." -ForegroundColor Red
    Read-Host "`nAppuyez sur Entree pour quitter"
    exit 1
}
$vidW = [int]$dims[0]
$vidH = [int]$dims[1]
Write-Host " ${vidW}x${vidH}" -ForegroundColor Green

# ── Output path ──────────────────────────────────────────────────────────────
$dir      = [IO.Path]::GetDirectoryName($videoPath)
$basename = [IO.Path]::GetFileNameWithoutExtension($videoPath)
$ext      = [IO.Path]::GetExtension($videoPath)
$ts       = Get-Date -Format "yyyyMMdd_HHmmss"
$outPath  = Join-Path $dir "${basename}_subtitled_${ts}${ext}"

# Copy SRT to a temp path with no special characters to avoid all filtergraph escaping issues
$tempSrt = Join-Path $env:TEMP "burn360_subs_temp.srt"
Copy-Item -LiteralPath $subPath -Destination $tempSrt -Force
$subEsc = $tempSrt.Replace('\', '/').Replace(':', '\:')
Write-Host "[INFO] SRT temp : $tempSrt" -ForegroundColor DarkGray

# ── Process by projection type ───────────────────────────────────────────────
switch ($projChoice) {

    "1" {
        # ── 360 3D Top-Bottom ────────────────────────────────────────────────
        # Frame layout: top half = left eye, bottom half = right eye
        # Each half is a full equirectangular 360 image at half height.
        # Subtitles must appear in both halves at the same relative position.
        # Target: just below the equator of each half (~60% from top = 40% from bottom)
        # This maps to a comfortable downward gaze in the headset, near-equatorial
        # so distortion is minimal. Zero horizontal disparity keeps text at infinity.

        Write-Host ""
        Write-Host "Projection : 360 3D Top-Bottom" -ForegroundColor Cyan

        if ($vidH % 2 -ne 0) {
            Write-Host "[AVERTISSEMENT] Hauteur impaire (${vidH}px) - ajustement a $($vidH - 1)px" -ForegroundColor Yellow
            $vidH = $vidH - 1
        }

        $halfH    = [int]($vidH / 2)
        # libass uses PlayResY=288 (ASS/SSA spec default) for SRT files regardless of video size.
        # force_style values must be in those 288-unit coordinates, not pixels.
        # Scale factor: how many pixels each ASS unit covers on screen.
        $assScale = $halfH / 288.0
        # Font size: ~3.8% of half-height in pixels → converted to ASS units
        $fontSizePx  = [math]::Max(16, [int]($halfH * 0.038))
        $fontSizeAss = [math]::Max(6,  [int]($fontSizePx / $assScale))
        # MarginV: 40% of half-height from bottom in pixels → converted to ASS units
        # This places text at 60% from top of each half (below equator, minimal distortion)
        $marginVAss  = [int](288 * 0.40)   # = 115, constant regardless of resolution
        $pctFromTop  = [int]((1 - 0.40) * 100)

        Write-Host "  Hauteur par oeil : ${halfH}px"
        Write-Host "  Taille police    : ${fontSizePx}px (ASS: ${fontSizeAss})"
        Write-Host "  Position         : ${pctFromTop}% depuis le haut de chaque demi-image"
        Write-Host ""
        Write-Host "[...] Encodage en cours..." -ForegroundColor Yellow
        Write-Host "      Patience pour les videos 4K/8K..."
        Write-Host ""

        $style = "FontName=Arial,FontSize=${fontSizeAss}," +
                 "PrimaryColour=&H00FFFFFF,OutlineColour=&H00000000," +
                 "BorderStyle=1,Outline=0.2,Shadow=0," +
                 "MarginV=${marginVAss},Alignment=2"

        # Filter graph:
        # 1. Split into top (left eye) and bottom (right eye)
        # 2. Burn identical subtitles into each at the same relative position
        # 3. Stack back vertically
        # NOTE: Use ${curly_braces} around variable names to prevent PowerShell from
        # treating the colon in ':force_style' as a scope separator (e.g. $var:name).
        $filterGraph = (
            "[0:v]split=2[top][bot];" +
            "[top]crop=iw:ih/2:0:0,subtitles='${subEsc}':force_style='${style}'[topsub];" +
            "[bot]crop=iw:ih/2:0:ih/2,subtitles='${subEsc}':force_style='${style}'[botsub];" +
            "[topsub][botsub]vstack[vout]"
        )

        & $ffmpeg -y -i "$videoPath" `
            -filter_complex $filterGraph `
            -map "[vout]" -map "0:a?" `
            -c:v libx264 -crf 18 -preset medium `
            -c:a copy `
            -pix_fmt yuv420p `
            "$outPath"

        if (Test-Path -LiteralPath $outPath) {
            $sizeMB = [math]::Round((Get-Item -LiteralPath $outPath).Length / 1MB, 1)
            Write-Host ""
            Write-Host "[OK] Fichier cree : $outPath" -ForegroundColor Green
            Write-Host "     Taille       : ${sizeMB} Mo" -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "[ERREUR] L'encodage a echoue." -ForegroundColor Red
            Write-Host "         Verifiez que le fichier SRT est valide et que FFmpeg supporte libass."
        }
    }


    # ── Future projection types go here ──────────────────────────────────────
    # "2" { ... 360 3D Side-by-Side ... }
    # "3" { ... 360 Mono equirectangular ... }
    # "4" { ... 360 Mono fisheye ... }

    default {
        Write-Host "[ERREUR] Type de projection non reconnu: $projChoice" -ForegroundColor Red
    }
}

# Clean up temp SRT copy
if (Test-Path $tempSrt) { Remove-Item $tempSrt -Force }

Write-Host ""
Read-Host "Appuyez sur Entree pour quitter"
