# Automatic Subtitles - Interface Graphique Portable
# Utilise WPF (integre a Windows)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# Forcer TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ffmpeg = Join-Path $scriptDir "bin\ffmpeg\ffmpeg.exe"
$ffprobe = Join-Path $scriptDir "bin\ffmpeg\ffprobe.exe"
$whisper = Join-Path $scriptDir "bin\whisper\Release\whisper-cli.exe"
$model = Join-Path $scriptDir "bin\whisper\ggml-base.bin"

# Interface XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Automatic Subtitles" Height="600" Width="750"
        WindowStartupLocation="CenterScreen" WindowState="Maximized" Background="#1e1e1e">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0078d4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Padding" Value="15,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="Margin" Value="0,5"/>
        </Style>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="White"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Padding" Value="5"/>
        </Style>
    </Window.Resources>

    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="150"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Titre -->
        <TextBlock Grid.Row="0" Text="Automatic Subtitles" FontSize="24" FontWeight="Bold"
                   Foreground="White" Margin="0,0,0,15"/>

        <!-- Liste des fichiers -->
        <GroupBox Grid.Row="1" Header="Fichiers" Foreground="White" Margin="0,0,0,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <ListBox x:Name="FilesList" Grid.Column="0" Background="#2d2d2d" Foreground="White"
                         BorderThickness="0" SelectionMode="Extended"/>
                <StackPanel Grid.Column="1" Margin="10,0,0,0" Width="120">
                    <Button x:Name="BtnAddFiles" Content="+ Fichiers" Margin="0,0,0,5"/>
                    <Button x:Name="BtnAddFolder" Content="+ Dossier" Margin="0,0,0,5"/>
                    <Button x:Name="BtnRemove" Content="- Retirer" Margin="0,0,0,5" Background="#d41a1a"/>
                    <Button x:Name="BtnClear" Content="Vider" Background="#555"/>
                </StackPanel>
            </Grid>
        </GroupBox>

        <!-- Options -->
        <GroupBox Grid.Row="2" Header="Options" Foreground="White" Margin="0,0,0,10">
            <StackPanel Margin="5">
                <CheckBox x:Name="ChkReview" Content="Reviser les sous-titres avant integration" IsChecked="True"/>
                <CheckBox x:Name="ChkKeepSrt" Content="Conserver les fichiers .srt"/>
                <CheckBox x:Name="ChkTerminal" Content="Ouvrir Whisper dans le terminal (voir en direct)" IsChecked="True"/>

                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                    <Label Content="Modele Whisper:" VerticalAlignment="Center"/>
                    <ComboBox x:Name="CmbModel" Width="120" Margin="10,0,20,0">
                        <ComboBoxItem Content="tiny" Tag="ggml-tiny.bin"/>
                        <ComboBoxItem Content="base" Tag="ggml-base.bin" IsSelected="True"/>
                        <ComboBoxItem Content="small" Tag="ggml-small.bin"/>
                        <ComboBoxItem Content="medium" Tag="ggml-medium.bin"/>
                        <ComboBoxItem Content="large" Tag="ggml-large-v3.bin"/>
                    </ComboBox>

                    <Label Content="Langue:" VerticalAlignment="Center"/>
                    <ComboBox x:Name="CmbLanguage" Width="120" Margin="10,0,0,0">
                        <ComboBoxItem Content="Francais" Tag="fr" IsSelected="True"/>
                        <ComboBoxItem Content="Anglais" Tag="en"/>
                        <ComboBoxItem Content="Espagnol" Tag="es"/>
                        <ComboBoxItem Content="Allemand" Tag="de"/>
                        <ComboBoxItem Content="Italien" Tag="it"/>
                        <ComboBoxItem Content="Portugais" Tag="pt"/>
                        <ComboBoxItem Content="Auto-detect" Tag="auto"/>
                    </ComboBox>
                </StackPanel>

                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                    <Label Content="Resolution video:" VerticalAlignment="Center"/>
                    <ComboBox x:Name="CmbResolution" Width="150" Margin="10,0,0,0">
                        <ComboBoxItem Content="480p (854x480)" IsSelected="True"/>
                        <ComboBoxItem Content="720p (1280x720)"/>
                        <ComboBoxItem Content="1080p (1920x1080)"/>
                        <ComboBoxItem Content="360p (640x360)"/>
                    </ComboBox>
                    <Label Content="(si pas de video source)" Foreground="Gray" VerticalAlignment="Center"/>
                </StackPanel>
            </StackPanel>
        </GroupBox>

        <!-- Barre de progression -->
        <StackPanel Grid.Row="3" Margin="0,0,0,10">
            <ProgressBar x:Name="Progress" Height="20" Minimum="0" Maximum="100" Value="0"/>
            <TextBlock x:Name="Status" Text="Pret" Foreground="White" Margin="0,5,0,0"/>
        </StackPanel>

        <!-- Journal -->
        <GroupBox Grid.Row="4" Header="Journal" Foreground="White" Margin="0,0,0,10">
            <TextBox x:Name="Log" Background="#2d2d2d" Foreground="#00ff00"
                     BorderThickness="0" IsReadOnly="True"
                     VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                     FontFamily="Consolas"/>
        </GroupBox>

        <!-- Boutons -->
        <StackPanel Grid.Row="5" Orientation="Horizontal">
            <Button x:Name="BtnDownloadModels" Content="Telecharger ce modele"
                    Padding="15,15" Background="#6b4c9a" Margin="0,0,10,0"/>
            <Button x:Name="BtnStart" Content="DEMARRER LE TRAITEMENT"
                    FontSize="16" FontWeight="Bold" Padding="20,15" Background="#107c10" HorizontalAlignment="Stretch"/>
        </StackPanel>
    </Grid>
</Window>
"@

# Creer la fenetre
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Recuperer les controles
$filesList = $window.FindName("FilesList")
$btnAddFiles = $window.FindName("BtnAddFiles")
$btnAddFolder = $window.FindName("BtnAddFolder")
$btnRemove = $window.FindName("BtnRemove")
$btnClear = $window.FindName("BtnClear")
$chkReview = $window.FindName("ChkReview")
$chkKeepSrt = $window.FindName("ChkKeepSrt")
$chkTerminal = $window.FindName("ChkTerminal")
$cmbModel = $window.FindName("CmbModel")
$cmbLanguage = $window.FindName("CmbLanguage")
$cmbResolution = $window.FindName("CmbResolution")
$btnDownloadModels = $window.FindName("BtnDownloadModels")
$progress = $window.FindName("Progress")
$status = $window.FindName("Status")
$log = $window.FindName("Log")
$btnStart = $window.FindName("BtnStart")

# Liste des fichiers (chemins complets)
$script:files = @()

# Variable de synchronisation pour la revision (hashtable synchronisee)
$script:syncState = [hashtable]::Synchronized(@{
    ContinueProcessing = $false
    WaitingForContinue = $false
})

# Fonction log
function Write-Log {
    param($message)
    $log.Dispatcher.Invoke([action]{
        $log.AppendText("$message`r`n")
        $log.ScrollToEnd()
    })
}

# Fonction pour mettre a jour le statut
function Set-Status {
    param($text)
    $status.Dispatcher.Invoke([action]{ $status.Text = $text })
}

# Fonction pour mettre a jour la progression
function Set-Progress {
    param($value)
    $progress.Dispatcher.Invoke([action]{ $progress.Value = $value })
}

# Detecter si le fichier contient une video
function Test-HasVideo {
    param($filepath)
    try {
        $result = & $ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of json $filepath 2>$null
        $json = $result | ConvertFrom-Json
        return ($json.streams.Count -gt 0)
    } catch {
        return $false
    }
}

# Obtenir la resolution selectionnee
function Get-Resolution {
    $selected = $cmbResolution.Dispatcher.Invoke([Func[object]]{ $cmbResolution.SelectedItem.Content })
    switch -Regex ($selected) {
        "480p" { return @(854, 480) }
        "720p" { return @(1280, 720) }
        "1080p" { return @(1920, 1080) }
        "360p" { return @(640, 360) }
        default { return @(854, 480) }
    }
}

# Traiter un fichier
function Process-File {
    param($filepath, $index, $total)

    $basename = [System.IO.Path]::GetFileNameWithoutExtension($filepath)
    $directory = [System.IO.Path]::GetDirectoryName($filepath)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

    $wavFile = Join-Path $directory "$basename`_temp.wav"
    $srtFile = Join-Path $directory "$basename.srt"
    $outputFile = Join-Path $directory "$basename`_$timestamp.mp4"

    Write-Log "`n============================================"
    Write-Log "[$index/$total] $basename"

    # Detecter video
    $hasVideo = Test-HasVideo $filepath
    Write-Log "  Video source: $(if($hasVideo){'Oui'}else{'Non'})"

    # Etape 1: Extraire audio
    Write-Log "  [1/3] Extraction audio..."
    Set-Status "[$index/$total] Extraction audio..."
    & $ffmpeg -y -i $filepath -ar 16000 -ac 1 -c:a pcm_s16le $wavFile -hide_banner -loglevel error 2>$null

    if (-not (Test-Path $wavFile)) {
        Write-Log "  [ERREUR] Extraction audio echouee"
        return $false
    }

    # Etape 2: Transcription
    Write-Log "  [2/3] Transcription Whisper..."
    Set-Status "[$index/$total] Transcription..."
    & $whisper -m $model -l fr -osrt -of (Join-Path $directory $basename) -f $wavFile 2>$null

    # Supprimer WAV temporaire
    Remove-Item $wavFile -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path $srtFile)) {
        Write-Log "  [ERREUR] Fichier SRT non cree"
        return $false
    }
    Write-Log "  [OK] Sous-titres generes"

    # Revision si demandee
    $reviewEnabled = $chkReview.Dispatcher.Invoke([Func[bool]]{ $chkReview.IsChecked })
    if ($reviewEnabled) {
        Write-Log "  [PAUSE] Revision des sous-titres..."
        Start-Process $srtFile -Wait

        $result = [System.Windows.MessageBox]::Show(
            "Avez-vous termine la revision des sous-titres?`n`nCliquez 'Oui' pour continuer l'integration.",
            "Revision",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Question
        )

        if ($result -eq [System.Windows.MessageBoxResult]::No) {
            Write-Log "  [ANNULE] Integration annulee"
            return $false
        }
    }

    # Etape 3: Creation video
    Write-Log "  [3/3] Creation video..."
    Set-Status "[$index/$total] Creation video..."

    $srtEscaped = $srtFile.Replace("\", "/").Replace(":", "\:")
    $res = Get-Resolution
    $width = $res[0]
    $height = $res[1]

    if ($hasVideo) {
        # Utiliser la video source
        & $ffmpeg -y -i $filepath `
            -vf "subtitles='$srtEscaped':force_style='FontName=Arial,FontSize=20,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=3'" `
            -c:v libx264 -crf 23 -preset fast `
            -c:a aac -b:a 128k `
            -pix_fmt yuv420p `
            $outputFile -hide_banner -loglevel error 2>$null
    } else {
        # Generer visualisation
        & $ffmpeg -y -i $filepath `
            -filter_complex "[0:a]showwaves=s=${width}x${height}:mode=p2p:colors=blue:draw=full,subtitles='$srtEscaped':force_style='FontName=Arial,FontSize=20,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=3'[v]" `
            -map "[v]" -map "0:a" `
            -c:v libx264 -crf 30 -preset fast `
            -c:a aac -b:a 96k `
            -pix_fmt yuv420p `
            $outputFile -hide_banner -loglevel error 2>$null
    }

    if (Test-Path $outputFile) {
        Write-Log "  [OK] Video creee: $([System.IO.Path]::GetFileName($outputFile))"

        # Gestion SRT
        $keepSrt = $chkKeepSrt.Dispatcher.Invoke([Func[bool]]{ $chkKeepSrt.IsChecked })
        if (-not $keepSrt) {
            Remove-Item $srtFile -Force -ErrorAction SilentlyContinue
            Write-Log "  [OK] SRT supprime"
        } else {
            Write-Log "  [OK] SRT conserve"
        }
        return $true
    } else {
        Write-Log "  [ERREUR] Creation video echouee"
        return $false
    }
}

# Bouton Ajouter fichiers
$btnAddFiles.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Filter = "Fichiers audio/video|*.mp3;*.m4a;*.wav;*.flac;*.aac;*.ogg;*.wma;*.mp4;*.mkv;*.avi;*.mov;*.webm|Tous|*.*"

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        foreach ($file in $dialog.FileNames) {
            if ($script:files -notcontains $file) {
                $script:files += $file
                $filesList.Items.Add([System.IO.Path]::GetFileName($file))
            }
        }
    }
})

# Bouton Ajouter dossier
$btnAddFolder.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $extensions = @("*.mp3","*.m4a","*.wav","*.flac","*.aac","*.ogg","*.wma","*.mp4","*.mkv","*.avi","*.mov","*.webm")
        foreach ($ext in $extensions) {
            Get-ChildItem -Path $dialog.SelectedPath -Filter $ext -ErrorAction SilentlyContinue | ForEach-Object {
                if ($script:files -notcontains $_.FullName) {
                    $script:files += $_.FullName
                    $filesList.Items.Add($_.Name)
                }
            }
        }
    }
})

# Bouton Retirer
$btnRemove.Add_Click({
    # Recuperer les indices selectionnes et les trier en ordre decroissant
    $selectedIndices = @()
    foreach ($item in $filesList.SelectedItems) {
        $selectedIndices += $filesList.Items.IndexOf($item)
    }
    $selectedIndices = $selectedIndices | Sort-Object -Descending

    # Supprimer en ordre decroissant pour eviter les problemes d'index
    foreach ($index in $selectedIndices) {
        if ($index -ge 0 -and $index -lt $script:files.Count) {
            $script:files = @($script:files[0..($index-1)]) + @($script:files[($index+1)..($script:files.Count-1)])
            $filesList.Items.RemoveAt($index)
        }
    }

    # Cas special: si on supprime le premier element
    if ($script:files.Count -eq 1 -and $selectedIndices -contains 0) {
        $script:files = @()
    }
})

# Bouton Vider
$btnClear.Add_Click({
    $script:files = @()
    $filesList.Items.Clear()
})

# Touche Suppr pour retirer les fichiers selectionnes
$filesList.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Delete) {
        $selectedIndices = @()
        foreach ($item in $filesList.SelectedItems) {
            $selectedIndices += $filesList.Items.IndexOf($item)
        }
        $selectedIndices = $selectedIndices | Sort-Object -Descending

        foreach ($index in $selectedIndices) {
            if ($index -ge 0 -and $index -lt $script:files.Count) {
                $script:files = @($script:files[0..($index-1)]) + @($script:files[($index+1)..($script:files.Count-1)])
                $filesList.Items.RemoveAt($index)
            }
        }
    }
})

# Bouton Telecharger modeles (telecharge UNIQUEMENT le modele selectionne)
$btnDownloadModels.Add_Click({
    $modelUrls = @{
        "ggml-tiny.bin" = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
        "ggml-base.bin" = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
        "ggml-small.bin" = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"
        "ggml-medium.bin" = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
        "ggml-large-v3.bin" = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"
    }

    $modelSizes = @{
        "ggml-tiny.bin" = "~75 Mo"
        "ggml-base.bin" = "~148 Mo"
        "ggml-small.bin" = "~466 Mo"
        "ggml-medium.bin" = "~1.5 Go"
        "ggml-large-v3.bin" = "~3 Go"
    }

    # Recuperer le modele selectionne
    $selectedModelFile = $cmbModel.SelectedItem.Tag
    $selectedModelName = $cmbModel.SelectedItem.Content
    $whisperDir = Join-Path $scriptDir "bin\whisper"
    $modelPath = Join-Path $whisperDir $selectedModelFile

    # Verifier si le modele selectionne existe deja
    if (Test-Path $modelPath) {
        [System.Windows.MessageBox]::Show(
            "Le modele '$selectedModelName' ($selectedModelFile) est deja installe!",
            "Information", "OK", "Information")
        return
    }

    # Demander confirmation
    $size = $modelSizes[$selectedModelFile]
    $result = [System.Windows.MessageBox]::Show(
        "Telecharger le modele '$selectedModelName'?`n`nTaille: $size`n`nCela peut prendre plusieurs minutes.",
        "Telecharger modele", "YesNo", "Question")

    if ($result -eq "Yes") {
        Write-Log "`n=== TELECHARGEMENT DU MODELE ==="
        Write-Log "[...] Telechargement de $selectedModelFile ($size)..."
        $status.Text = "Telechargement de $selectedModelFile..."
        $btnDownloadModels.IsEnabled = $false
        $btnStart.IsEnabled = $false

        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $modelUrls[$selectedModelFile] -OutFile $modelPath -UseBasicParsing
            Write-Log "[OK] $selectedModelFile telecharge avec succes!"
            [System.Windows.MessageBox]::Show(
                "Modele '$selectedModelName' telecharge avec succes!",
                "Termine", "OK", "Information")
        } catch {
            Write-Log "[ERREUR] Echec du telechargement: $_"
            [System.Windows.MessageBox]::Show(
                "Erreur lors du telechargement:`n$_",
                "Erreur", "OK", "Error")
        }

        $btnDownloadModels.IsEnabled = $true
        $btnStart.IsEnabled = $true
        $status.Text = "Pret"
    }
})

# Bouton Demarrer / Continuer
$btnStart.Add_Click({
    # Si on attend pour continuer apres revision
    if ($script:syncState.WaitingForContinue) {
        $script:syncState.ContinueProcessing = $true
        $script:syncState.WaitingForContinue = $false
        $btnStart.Content = "TRAITEMENT EN COURS..."
        $btnStart.IsEnabled = $false
        return
    }

    if ($script:files.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Aucun fichier selectionne!", "Attention", "OK", "Warning")
        return
    }

    # Reinitialiser l'etat de synchronisation
    $script:syncState.ContinueProcessing = $false
    $script:syncState.WaitingForContinue = $false

    # Desactiver le bouton
    $btnStart.IsEnabled = $false
    $btnStart.Content = "TRAITEMENT EN COURS..."

    # Lancer dans un thread
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("files", $script:files)
    $runspace.SessionStateProxy.SetVariable("ffmpeg", $ffmpeg)
    $runspace.SessionStateProxy.SetVariable("ffprobe", $ffprobe)
    $runspace.SessionStateProxy.SetVariable("whisper", $whisper)
    $runspace.SessionStateProxy.SetVariable("model", $model)
    $runspace.SessionStateProxy.SetVariable("window", $window)
    $runspace.SessionStateProxy.SetVariable("log", $log)
    $runspace.SessionStateProxy.SetVariable("status", $status)
    $runspace.SessionStateProxy.SetVariable("progress", $progress)
    $runspace.SessionStateProxy.SetVariable("btnStart", $btnStart)
    $runspace.SessionStateProxy.SetVariable("chkReview", $chkReview)
    $runspace.SessionStateProxy.SetVariable("chkKeepSrt", $chkKeepSrt)
    $runspace.SessionStateProxy.SetVariable("chkTerminal", $chkTerminal)
    $runspace.SessionStateProxy.SetVariable("cmbModel", $cmbModel)
    $runspace.SessionStateProxy.SetVariable("cmbLanguage", $cmbLanguage)
    $runspace.SessionStateProxy.SetVariable("cmbResolution", $cmbResolution)
    $runspace.SessionStateProxy.SetVariable("scriptDir", $scriptDir)
    $runspace.SessionStateProxy.SetVariable("syncState", $script:syncState)

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace

    [void]$powershell.AddScript({
        function Write-Log { param($msg); $log.Dispatcher.Invoke([action]{ $log.AppendText("$msg`r`n"); $log.ScrollToEnd() }) }
        function Set-Status { param($txt); $status.Dispatcher.Invoke([action]{ $status.Text = $txt }) }
        function Set-Progress { param($val); $progress.Dispatcher.Invoke([action]{ $progress.Value = $val }) }
        function Get-Resolution {
            $sel = $cmbResolution.Dispatcher.Invoke([Func[object]]{ $cmbResolution.SelectedItem.Content })
            switch -Regex ($sel) { "480p"{@(854,480)} "720p"{@(1280,720)} "1080p"{@(1920,1080)} "360p"{@(640,360)} default{@(854,480)} }
        }
        function Get-ModelFile {
            $tag = $cmbModel.Dispatcher.Invoke([Func[object]]{ $cmbModel.SelectedItem.Tag })
            return Join-Path $scriptDir "bin\whisper\$tag"
        }
        function Get-Language {
            $tag = $cmbLanguage.Dispatcher.Invoke([Func[object]]{ $cmbLanguage.SelectedItem.Tag })
            return $tag
        }
        function Test-HasVideo { param($fp); try { $r = & $ffprobe -v error -select_streams v:0 -show_entries stream=codec_type -of json $fp 2>$null; ($r|ConvertFrom-Json).streams.Count -gt 0 } catch { $false } }

        # Recuperer le modele et la langue selectionnes
        $selectedModel = Get-ModelFile
        $selectedLang = Get-Language

        # Verifier si le modele existe
        if (-not (Test-Path $selectedModel)) {
            Write-Log "[ERREUR] Modele non trouve: $([IO.Path]::GetFileName($selectedModel))"
            Write-Log "Telechargez-le avec le bouton 'Telecharger modeles' ou utilisez 'base'"
            $window.Dispatcher.Invoke([action]{
                $btnStart.Content = "DEMARRER LE TRAITEMENT"
                $btnStart.IsEnabled = $true
            })
            return
        }

        Write-Log "[CONFIG] Modele: $([IO.Path]::GetFileName($selectedModel))"
        Write-Log "[CONFIG] Langue: $selectedLang"

        $total = $files.Count
        $success = 0
        $errors = 0

        for ($i = 0; $i -lt $total; $i++) {
            $filepath = $files[$i]
            $basename = [IO.Path]::GetFileNameWithoutExtension($filepath)
            $dir = [IO.Path]::GetDirectoryName($filepath)
            $ts = Get-Date -Format "yyyyMMdd_HHmmss"
            $wav = Join-Path $dir "$basename`_temp.wav"
            $srt = Join-Path $dir "$basename.srt"
            $out = Join-Path $dir "$basename`_$ts.mp4"

            Write-Log "`n============================================"
            Write-Log "[$(($i+1))/$total] $basename"

            $hasVideo = Test-HasVideo $filepath
            Write-Log "  Video source: $(if($hasVideo){'Oui'}else{'Non'})"

            # Audio
            Write-Log "  [1/3] Extraction audio..."
            Set-Status "[$(($i+1))/$total] Extraction audio..."
            & $ffmpeg -y -i $filepath -ar 16000 -ac 1 -c:a pcm_s16le $wav -hide_banner -loglevel error 2>$null
            if (-not (Test-Path $wav)) { Write-Log "  [ERREUR] Extraction echouee"; $errors++; continue }

            # Whisper - transcription
            Write-Log "  [2/3] Transcription..."
            Set-Status "[$(($i+1))/$total] Transcription..."

            # Construire les arguments (avec guillemets pour les espaces)
            $outPath = Join-Path $dir $basename
            if ($selectedLang -eq "auto") {
                $whisperArgs = "-m `"$selectedModel`" -osrt -of `"$outPath`" -f `"$wav`""
            } else {
                $whisperArgs = "-m `"$selectedModel`" -l $selectedLang -osrt -of `"$outPath`" -f `"$wav`""
            }

            # Verifier si on ouvre dans le terminal
            $useTerminal = $chkTerminal.Dispatcher.Invoke([Func[bool]]{ $chkTerminal.IsChecked })

            if ($useTerminal) {
                # Ouvrir Whisper dans une fenetre CMD visible
                Write-Log "  [Terminal] Ouverture de Whisper dans le terminal..."
                $cmdArgs = "/c `"`"$whisper`" $whisperArgs`""
                $proc = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -PassThru -Wait
            } else {
                # Mode silencieux avec capture
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $whisper
                $psi.Arguments = $whisperArgs
                $psi.UseShellExecute = $false
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.CreateNoWindow = $true

                $proc = [System.Diagnostics.Process]::Start($psi)

                # Lire stderr en temps reel (whisper ecrit sur stderr)
                while (-not $proc.HasExited) {
                    $line = $proc.StandardError.ReadLine()
                    if ($line) {
                        Write-Log "  $line"
                    }
                    Start-Sleep -Milliseconds 50
                }
                # Lire les lignes restantes
                while ($null -ne ($line = $proc.StandardError.ReadLine())) {
                    Write-Log "  $line"
                }
            }

            Remove-Item $wav -Force -EA SilentlyContinue
            if (-not (Test-Path $srt)) { Write-Log "  [ERREUR] SRT non cree"; $errors++; continue }
            Write-Log "  [OK] Sous-titres generes"

            # Review
            $review = $chkReview.Dispatcher.Invoke([Func[bool]]{ $chkReview.IsChecked })
            if ($review) {
                Write-Log "  [PAUSE] Revision des sous-titres..."
                Write-Log "         Modifiez le fichier, sauvegardez, puis cliquez CONTINUER"
                Start-Process $srt

                # Changer le bouton en "CONTINUER"
                $syncState.WaitingForContinue = $true
                $syncState.ContinueProcessing = $false
                $window.Dispatcher.Invoke([action]{
                    $btnStart.Content = "CONTINUER LE TRAITEMENT"
                    $btnStart.IsEnabled = $true
                    $btnStart.Background = [System.Windows.Media.Brushes]::Orange
                })

                # Attendre que l'utilisateur clique sur Continuer
                while (-not $syncState.ContinueProcessing) {
                    Start-Sleep -Milliseconds 200
                }

                # Remettre le bouton en mode normal
                $window.Dispatcher.Invoke([action]{
                    $btnStart.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#107c10")
                })
                Write-Log "  [OK] Revision terminee, continuation..."
            }

            # Video - avec sortie en temps reel
            Write-Log "  [3/3] Creation video..."
            Set-Status "[$(($i+1))/$total] Creation video..."

            # Echappement du chemin SRT pour ffmpeg
            $srtE = $srt.Replace('\', '/').Replace(':', '\:')
            $res = Get-Resolution; $w=$res[0]; $h=$res[1]

            # Construire les arguments FFmpeg
            Write-Log "  --- ENCODAGE VIDEO ---"
            if ($hasVideo) {
                Write-Log "  Mode: Video source + sous-titres"
                $ffmpegArgs = "-y -i `"$filepath`" -vf `"subtitles='$srtE':force_style='FontName=Arial,FontSize=20,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=3'`" -c:v libx264 -crf 23 -preset fast -c:a aac -b:a 128k -pix_fmt yuv420p `"$out`" -hide_banner -stats"
            } else {
                Write-Log "  Mode: Visualisation audio (${w}x${h})"
                $ffmpegArgs = "-y -i `"$filepath`" -filter_complex `"[0:a]showwaves=s=${w}x${h}:mode=p2p:colors=blue:draw=full,subtitles='$srtE':force_style='FontName=Arial,FontSize=20,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=3'[v]`" -map `"[v]`" -map 0:a -c:v libx264 -crf 30 -preset fast -c:a aac -b:a 96k -pix_fmt yuv420p `"$out`" -hide_banner -stats"
            }

            # Lancer FFmpeg et capturer la sortie
            $psiFF = New-Object System.Diagnostics.ProcessStartInfo
            $psiFF.FileName = $ffmpeg
            $psiFF.Arguments = $ffmpegArgs
            $psiFF.UseShellExecute = $false
            $psiFF.RedirectStandardOutput = $true
            $psiFF.RedirectStandardError = $true
            $psiFF.CreateNoWindow = $true

            $procFF = [System.Diagnostics.Process]::Start($psiFF)

            # Lire stderr en temps reel (ffmpeg ecrit sur stderr)
            $lastTime = ""
            while (-not $procFF.HasExited) {
                $line = $procFF.StandardError.ReadLine()
                if ($line -and $line -match "time=(\d{2}:\d{2}:\d{2})") {
                    if ($matches[1] -ne $lastTime) {
                        $lastTime = $matches[1]
                        Write-Log "  Encodage: $lastTime"
                    }
                } elseif ($line -and $line -match "error|Error") {
                    Write-Log "  [FFmpeg] $line"
                }
                Start-Sleep -Milliseconds 50
            }

            Write-Log "  --- FIN ENCODAGE ---"

            if (Test-Path $out) {
                $fileSize = [math]::Round((Get-Item $out).Length / 1MB, 2)
                Write-Log "  [OK] $([IO.Path]::GetFileName($out)) ($fileSize Mo)"
                $keep = $chkKeepSrt.Dispatcher.Invoke([Func[bool]]{ $chkKeepSrt.IsChecked })
                if (-not $keep) { Remove-Item $srt -Force -EA SilentlyContinue }
                $success++
            } else {
                Write-Log "  [ERREUR] Creation echouee"
                $errors++
            }

            Set-Progress ([int](($i + 1) / $total * 100))
        }

        Write-Log "`n============================================"
        Write-Log "TERMINE: $success/$total reussi(s), $errors erreur(s)"
        Set-Status "Termine!"

        $window.Dispatcher.Invoke([action]{
            $btnStart.Content = "DEMARRER LE TRAITEMENT"
            $btnStart.IsEnabled = $true
            [System.Windows.MessageBox]::Show("Traitement termine!`n$success/$total fichier(s) traite(s).", "Termine", "OK", "Information")
        })
    })

    [void]$powershell.BeginInvoke()
})

# Verifier les dependances
if (-not (Test-Path $ffmpeg)) { Write-Log "[ERREUR] FFmpeg non trouve - Executez INSTALLER.bat" }
elseif (-not (Test-Path $whisper)) { Write-Log "[ERREUR] Whisper non trouve - Executez INSTALLER.bat" }
elseif (-not (Test-Path $model)) { Write-Log "[ERREUR] Modele non trouve - Executez INSTALLER.bat" }
else { Write-Log "[OK] Tous les composants sont installes" }

# Afficher la fenetre
[void]$window.ShowDialog()
