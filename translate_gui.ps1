# Video Translator - Interface Graphique
# Traduction automatique de vidéos avec doublage

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ffmpeg = Join-Path $scriptDir "bin\ffmpeg\ffmpeg.exe"
$ffprobe = Join-Path $scriptDir "bin\ffmpeg\ffprobe.exe"
$whisper = Join-Path $scriptDir "bin\whisper\Release\whisper-cli.exe"
$model = Join-Path $scriptDir "bin\whisper\ggml-base.bin"
$python = Join-Path $scriptDir "bin\python\python.exe"
$scriptsDir = Join-Path $scriptDir "scripts"

# Interface XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Video Translator - Traduction avec Doublage" Height="700" Width="850"
        WindowStartupLocation="CenterScreen" Background="#1e1e1e">
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
            <RowDefinition Height="180"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Titre -->
        <StackPanel Grid.Row="0" Margin="0,0,0,15">
            <TextBlock Text="Video Translator" FontSize="24" FontWeight="Bold" Foreground="White"/>
            <TextBlock Text="Traduction automatique avec doublage vocal" FontSize="12" Foreground="Gray"/>
        </StackPanel>

        <!-- Liste des fichiers -->
        <GroupBox Grid.Row="1" Header="Fichiers vidéo" Foreground="White" Margin="0,0,0,10">
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
        <GroupBox Grid.Row="2" Header="Options de traduction" Foreground="White" Margin="0,0,0,10">
            <StackPanel Margin="5">
                <StackPanel Orientation="Horizontal" Margin="0,5,0,10">
                    <Label Content="Langue source (audio):" VerticalAlignment="Center" Width="150"/>
                    <ComboBox x:Name="CmbSourceLang" Width="150" Margin="10,0,20,0">
                        <ComboBoxItem Content="Français" Tag="fr" IsSelected="True"/>
                        <ComboBoxItem Content="Anglais" Tag="en"/>
                        <ComboBoxItem Content="Espagnol" Tag="es"/>
                        <ComboBoxItem Content="Allemand" Tag="de"/>
                        <ComboBoxItem Content="Italien" Tag="it"/>
                        <ComboBoxItem Content="Portugais" Tag="pt"/>
                        <ComboBoxItem Content="Auto-detect" Tag="auto"/>
                    </ComboBox>

                    <Label Content="Langue cible (TTS):" VerticalAlignment="Center"/>
                    <ComboBox x:Name="CmbTargetLang" Width="150" Margin="10,0,0,0">
                        <ComboBoxItem Content="Français Québec" Tag="fr-CA" IsSelected="True"/>
                        <ComboBoxItem Content="Français France" Tag="fr-FR"/>
                        <ComboBoxItem Content="Anglais US" Tag="en-US"/>
                        <ComboBoxItem Content="Anglais UK" Tag="en-GB"/>
                        <ComboBoxItem Content="Espagnol" Tag="es"/>
                        <ComboBoxItem Content="Allemand" Tag="de"/>
                        <ComboBoxItem Content="Italien" Tag="it"/>
                        <ComboBoxItem Content="Portugais" Tag="pt"/>
                    </ComboBox>
                </StackPanel>

                <StackPanel Orientation="Horizontal" Margin="0,5,0,5">
                    <Label Content="Modèle Whisper:" VerticalAlignment="Center" Width="150"/>
                    <ComboBox x:Name="CmbModel" Width="150" Margin="10,0,20,0">
                        <ComboBoxItem Content="tiny (rapide)" Tag="ggml-tiny.bin"/>
                        <ComboBoxItem Content="base" Tag="ggml-base.bin" IsSelected="True"/>
                        <ComboBoxItem Content="small" Tag="ggml-small.bin"/>
                        <ComboBoxItem Content="medium (précis)" Tag="ggml-medium.bin"/>
                        <ComboBoxItem Content="large (très précis)" Tag="ggml-large-v3.bin"/>
                    </ComboBox>

                    <Label Content="Voix:" VerticalAlignment="Center"/>
                    <ComboBox x:Name="CmbVoiceGender" Width="120" Margin="10,0,0,0">
                        <ComboBoxItem Content="Femme" Tag="female" IsSelected="True"/>
                        <ComboBoxItem Content="Homme" Tag="male"/>
                    </ComboBox>
                </StackPanel>

                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                    <CheckBox x:Name="ChkAddSubtitles" Content="Ajouter les sous-titres traduits sur la vidéo" IsChecked="True" Width="350"/>
                    <CheckBox x:Name="ChkKeepFiles" Content="Conserver les fichiers intermédiaires"/>
                </StackPanel>
            </StackPanel>
        </GroupBox>

        <!-- Barre de progression -->
        <StackPanel Grid.Row="3" Margin="0,0,0,10">
            <ProgressBar x:Name="Progress" Height="20" Minimum="0" Maximum="100" Value="0"/>
            <TextBlock x:Name="Status" Text="Prêt - Sélectionnez une vidéo" Foreground="White" Margin="0,5,0,0"/>
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
            <Button x:Name="BtnInstall" Content="Installer les dépendances"
                    Padding="15,15" Background="#6b4c9a" Margin="0,0,10,0"/>
            <Button x:Name="BtnStart" Content="DÉMARRER LA TRADUCTION"
                    FontSize="16" FontWeight="Bold" Padding="20,15" Background="#107c10"/>
        </StackPanel>
    </Grid>
</Window>
"@

# Créer la fenêtre
$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Récupérer les contrôles
$filesList = $window.FindName("FilesList")
$btnAddFiles = $window.FindName("BtnAddFiles")
$btnAddFolder = $window.FindName("BtnAddFolder")
$btnRemove = $window.FindName("BtnRemove")
$btnClear = $window.FindName("BtnClear")
$cmbSourceLang = $window.FindName("CmbSourceLang")
$cmbTargetLang = $window.FindName("CmbTargetLang")
$cmbModel = $window.FindName("CmbModel")
$cmbVoiceGender = $window.FindName("CmbVoiceGender")
$chkAddSubtitles = $window.FindName("ChkAddSubtitles")
$chkKeepFiles = $window.FindName("ChkKeepFiles")
$progress = $window.FindName("Progress")
$status = $window.FindName("Status")
$log = $window.FindName("Log")
$btnInstall = $window.FindName("BtnInstall")
$btnStart = $window.FindName("BtnStart")

# Liste des fichiers
$script:files = @()

# Variable de synchronisation
$script:syncState = [hashtable]::Synchronized(@{
    ContinueProcessing = $false
    WaitingForContinue = $false
})

# Fonctions utilitaires
function Write-Log {
    param($message)
    $log.Dispatcher.Invoke([action]{
        $log.AppendText("$message`r`n")
        $log.ScrollToEnd()
    })
}

function Set-Status {
    param($text)
    $status.Dispatcher.Invoke([action]{ $status.Text = $text })
}

function Set-Progress {
    param($value)
    $progress.Dispatcher.Invoke([action]{ $progress.Value = $value })
}

# Bouton Ajouter fichiers
$btnAddFiles.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Filter = "Fichiers vidéo|*.mp4;*.mkv;*.avi;*.mov;*.webm;*.wmv|Tous|*.*"

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
        $extensions = @("*.mp4","*.mkv","*.avi","*.mov","*.webm","*.wmv")
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
})

# Bouton Vider
$btnClear.Add_Click({
    $script:files = @()
    $filesList.Items.Clear()
})

# Bouton Installer dépendances
$btnInstall.Add_Click({
    $setupScript = Join-Path $scriptDir "setup_translator.ps1"
    if (Test-Path $setupScript) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$setupScript`"" -Wait
    } else {
        [System.Windows.MessageBox]::Show(
            "Script d'installation non trouvé: setup_translator.ps1",
            "Erreur", "OK", "Error")
    }
})

# Bouton Démarrer
$btnStart.Add_Click({
    # Si on attend pour continuer après traduction
    if ($script:syncState.WaitingForContinue) {
        $script:syncState.ContinueProcessing = $true
        $script:syncState.WaitingForContinue = $false
        $btnStart.Content = "TRAITEMENT EN COURS..."
        $btnStart.IsEnabled = $false
        return
    }

    if ($script:files.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Aucun fichier sélectionné!", "Attention", "OK", "Warning")
        return
    }

    # Vérifier les dépendances
    if (-not (Test-Path $python)) {
        [System.Windows.MessageBox]::Show(
            "Python non trouvé. Exécutez INSTALLER.bat d'abord.",
            "Erreur", "OK", "Error")
        return
    }

    # Réinitialiser
    $script:syncState.ContinueProcessing = $false
    $script:syncState.WaitingForContinue = $false
    $btnStart.IsEnabled = $false
    $btnStart.Content = "TRAITEMENT EN COURS..."

    # Lancer dans un thread
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.Open()

    # Passer les variables
    $runspace.SessionStateProxy.SetVariable("files", $script:files)
    $runspace.SessionStateProxy.SetVariable("ffmpeg", $ffmpeg)
    $runspace.SessionStateProxy.SetVariable("ffprobe", $ffprobe)
    $runspace.SessionStateProxy.SetVariable("whisper", $whisper)
    $runspace.SessionStateProxy.SetVariable("python", $python)
    $runspace.SessionStateProxy.SetVariable("scriptsDir", $scriptsDir)
    $runspace.SessionStateProxy.SetVariable("scriptDir", $scriptDir)
    $runspace.SessionStateProxy.SetVariable("window", $window)
    $runspace.SessionStateProxy.SetVariable("log", $log)
    $runspace.SessionStateProxy.SetVariable("status", $status)
    $runspace.SessionStateProxy.SetVariable("progress", $progress)
    $runspace.SessionStateProxy.SetVariable("btnStart", $btnStart)
    $runspace.SessionStateProxy.SetVariable("cmbSourceLang", $cmbSourceLang)
    $runspace.SessionStateProxy.SetVariable("cmbTargetLang", $cmbTargetLang)
    $runspace.SessionStateProxy.SetVariable("cmbModel", $cmbModel)
    $runspace.SessionStateProxy.SetVariable("cmbVoiceGender", $cmbVoiceGender)
    $runspace.SessionStateProxy.SetVariable("chkAddSubtitles", $chkAddSubtitles)
    $runspace.SessionStateProxy.SetVariable("chkKeepFiles", $chkKeepFiles)
    $runspace.SessionStateProxy.SetVariable("syncState", $script:syncState)

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace

    [void]$powershell.AddScript({
        function Write-Log { param($msg); $log.Dispatcher.Invoke([action]{ $log.AppendText("$msg`r`n"); $log.ScrollToEnd() }) }
        function Set-Status { param($txt); $status.Dispatcher.Invoke([action]{ $status.Text = $txt }) }
        function Set-Progress { param($val); $progress.Dispatcher.Invoke([action]{ $progress.Value = $val }) }

        function Get-ModelFile {
            $tag = $cmbModel.Dispatcher.Invoke([Func[object]]{ $cmbModel.SelectedItem.Tag })
            return Join-Path $scriptDir "bin\whisper\$tag"
        }
        function Get-SourceLang {
            return $cmbSourceLang.Dispatcher.Invoke([Func[object]]{ $cmbSourceLang.SelectedItem.Tag })
        }
        function Get-TargetLang {
            return $cmbTargetLang.Dispatcher.Invoke([Func[object]]{ $cmbTargetLang.SelectedItem.Tag })
        }
        function Get-VoiceGender {
            return $cmbVoiceGender.Dispatcher.Invoke([Func[object]]{ $cmbVoiceGender.SelectedItem.Tag })
        }

        $selectedModel = Get-ModelFile
        $sourceLang = Get-SourceLang
        $targetLang = Get-TargetLang
        $voiceGender = Get-VoiceGender
        $addSubtitles = $chkAddSubtitles.Dispatcher.Invoke([Func[bool]]{ $chkAddSubtitles.IsChecked })
        $keepFiles = $chkKeepFiles.Dispatcher.Invoke([Func[bool]]{ $chkKeepFiles.IsChecked })

        # Vérifier modèle
        if (-not (Test-Path $selectedModel)) {
            Write-Log "[ERREUR] Modèle Whisper non trouvé: $([IO.Path]::GetFileName($selectedModel))"
            $window.Dispatcher.Invoke([action]{
                $btnStart.Content = "DÉMARRER LA TRADUCTION"
                $btnStart.IsEnabled = $true
            })
            return
        }

        Write-Log "======================================"
        Write-Log "  VIDEO TRANSLATOR"
        Write-Log "======================================"
        Write-Log "[CONFIG] Modèle: $([IO.Path]::GetFileName($selectedModel))"
        Write-Log "[CONFIG] Langue source: $sourceLang"
        Write-Log "[CONFIG] Langue cible: $targetLang"
        Write-Log "[CONFIG] Voix: $voiceGender"
        Write-Log "[CONFIG] Sous-titres: $(if($addSubtitles){'Oui'}else{'Non'})"
        Write-Log ""

        $total = $files.Count
        $success = 0
        $errors = 0

        for ($i = 0; $i -lt $total; $i++) {
            $filepath = $files[$i]
            $originalBasename = [IO.Path]::GetFileNameWithoutExtension($filepath)
            $originalExt = [IO.Path]::GetExtension($filepath)
            $dir = [IO.Path]::GetDirectoryName($filepath)
            $ts = Get-Date -Format "yyyyMMdd_HHmmss"

            # Créer un dossier de travail temporaire avec nom simple (évite les problèmes unicode)
            # Dossier TEMP dans le répertoire du script
            $tempBase = Join-Path $scriptDir "TEMP"
            if (-not (Test-Path $tempBase)) { New-Item -ItemType Directory -Path $tempBase -Force | Out-Null }
            $workDir = Join-Path $tempBase "VideoTranslator_$ts"
            New-Item -ItemType Directory -Path $workDir -Force | Out-Null

            # Nom simplifié pour les fichiers de travail
            $safeBasename = "video_$ts"

            # Copier le fichier source vers le dossier de travail
            $workFile = Join-Path $workDir "$safeBasename$originalExt"
            Write-Log "============================================"
            Write-Log "[$(($i+1))/$total] $originalBasename"
            Write-Log "============================================"
            Write-Log "  Copie vers dossier de travail..."
            Copy-Item -LiteralPath $filepath -Destination $workFile -Force

            # Fichiers temporaires (dans le dossier de travail)
            $wavFile = Join-Path $workDir "$safeBasename.wav"
            $srtOriginal = Join-Path $workDir "$safeBasename.srt"
            $srtTranslated = Join-Path $workDir "$safeBasename`_translated.srt"
            $backgroundWav = Join-Path $workDir "$safeBasename`_background.wav"
            $ttsWav = Join-Path $workDir "$safeBasename`_tts.wav"
            $mixedWav = Join-Path $workDir "$safeBasename`_mixed.wav"
            $tempOutput = Join-Path $workDir "$safeBasename`_output.mp4"
            $outputFile = Join-Path $dir "$originalBasename`_translated_$ts.mp4"
            $finalSrtFile = Join-Path $dir "$originalBasename`_translated.srt"

            # =====================
            # ÉTAPE 1: Extraction audio + Transcription
            # =====================
            Write-Log ""
            Write-Log "[ÉTAPE 1/6] Extraction audio pour Whisper..."
            Set-Status "[$(($i+1))/$total] Extraction audio..."

            # Extraction audio robuste
            $tempMp3 = Join-Path $workDir "$safeBasename.mp3"
            Write-Log "  [VERBOSE] Source: $workFile"
            Write-Log "  [VERBOSE] MP3 temp: $tempMp3"
            Write-Log "  >>> OUVERTURE FENÊTRE FFMPEG EXTRACTION <<<"
            $extractArgs = "/k `"echo ========================================== & echo FFMPEG - EXTRACTION AUDIO WHISPER & echo ========================================== & `"$ffmpeg`" -y -i `"$workFile`" -vn -acodec libmp3lame -ar 16000 -ac 1 `"$tempMp3`" & echo. & echo Conversion MP3 vers WAV... & `"$ffmpeg`" -y -i `"$tempMp3`" -ar 16000 -ac 1 -c:a pcm_s16le `"$wavFile`" & echo. & echo ========================================== & echo EXTRACTION TERMINEE - Appuyez sur une touche & echo ========================================== & pause`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $extractArgs -Wait
            Write-Log "  <<< FENÊTRE FFMPEG EXTRACTION FERMÉE >>>"

            # Nettoyer MP3 temp
            if (Test-Path $tempMp3) {
                Write-Log "  [VERBOSE] Suppression MP3 temp: $tempMp3"
                Remove-Item $tempMp3 -Force -EA SilentlyContinue
            }

            Write-Log "  [VERBOSE] Vérification WAV: $wavFile"
            if (-not (Test-Path $wavFile)) {
                Write-Log "  [ERREUR] Extraction audio échouée - WAV non créé!"
                Write-Log "  [VERBOSE] Suppression workDir: $workDir"
                Remove-Item $workDir -Recurse -Force -EA SilentlyContinue
                $errors++
                continue
            }
            $wavSize = [math]::Round((Get-Item $wavFile).Length/1MB,2)
            Write-Log "  [OK] Audio extrait ($wavSize MB)"

            Write-Log ""
            Write-Log "[ÉTAPE 2/6] Transcription Whisper..."
            Set-Status "[$(($i+1))/$total] Transcription..."

            # Sortie SRT dans le dossier de travail (sans extension, Whisper ajoute .srt)
            $outPath = Join-Path $workDir $safeBasename
            if ($sourceLang -eq "auto") {
                $whisperArgs = "-m `"$selectedModel`" -osrt -of `"$outPath`" -f `"$wavFile`""
            } else {
                $whisperArgs = "-m `"$selectedModel`" -l $sourceLang -osrt -of `"$outPath`" -f `"$wavFile`""
            }

            Write-Log "  [VERBOSE] Whisper: $whisper"
            Write-Log "  [VERBOSE] Modèle: $selectedModel"
            Write-Log "  [VERBOSE] Args: $whisperArgs"
            $cmdArgs = "/c `"`"$whisper`" $whisperArgs`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -Wait -WindowStyle Normal

            Write-Log "  [VERBOSE] Suppression WAV: $wavFile"
            Remove-Item $wavFile -Force -EA SilentlyContinue

            Write-Log "  [VERBOSE] Vérification SRT: $srtOriginal"
            if (-not (Test-Path $srtOriginal)) {
                Write-Log "  [ERREUR] Fichier SRT non créé!"
                Write-Log "  [VERBOSE] Attendu: $srtOriginal"
                Write-Log "  [VERBOSE] Contenu workDir:"
                Get-ChildItem $workDir -EA SilentlyContinue | ForEach-Object { Write-Log "    - $($_.Name)" }
                Remove-Item $workDir -Recurse -Force -EA SilentlyContinue
                $errors++
                continue
            }
            Write-Log "  [OK] Sous-titres générés"

            # =====================
            # Extraction audio pour Demucs
            # =====================
            Write-Log ""
            # Extraire l'audio complet pour Demucs (via MP3 pour éviter erreurs Opus)
            $fullAudio = Join-Path $workDir "$safeBasename`_full.wav"
            $tempMp3Full = Join-Path $workDir "$safeBasename`_temp_full.mp3"
            Write-Log "  [VERBOSE] MP3 temp: $tempMp3Full"
            Write-Log "  [VERBOSE] WAV final: $fullAudio"

            Write-Log "  >>> OUVERTURE FENÊTRE FFMPEG DEMUCS <<<"
            $demucsExtractArgs = "/k `"echo ========================================== & echo FFMPEG - EXTRACTION AUDIO POUR DEMUCS & echo ========================================== & `"$ffmpeg`" -y -i `"$workFile`" -vn -acodec libmp3lame -ar 44100 -ac 2 `"$tempMp3Full`" & echo. & echo Conversion MP3 vers WAV... & `"$ffmpeg`" -y -i `"$tempMp3Full`" -acodec pcm_s16le `"$fullAudio`" & echo. & echo ========================================== & echo EXTRACTION DEMUCS TERMINEE - Appuyez sur une touche & echo ========================================== & pause`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $demucsExtractArgs -Wait
            Write-Log "  <<< FENÊTRE FFMPEG DEMUCS FERMÉE >>>"

            # Nettoyer MP3 temp
            if (Test-Path $tempMp3Full) {
                Write-Log "  [VERBOSE] Suppression MP3 temp: $tempMp3Full"
                Remove-Item $tempMp3Full -Force -EA SilentlyContinue
            }

            Write-Log "  [VERBOSE] Vérification: $fullAudio"
            if (-not (Test-Path $fullAudio)) {
                Write-Log "  [ERREUR] Extraction audio Demucs échouée - WAV non créé!"
                Remove-Item $workDir -Recurse -Force -EA SilentlyContinue
                $errors++
                continue
            }
            $fullAudioSize = [math]::Round((Get-Item $fullAudio).Length/1MB,2)
            Write-Log "  [OK] Audio extrait pour Demucs ($fullAudioSize MB)"

            # =====================
            # ÉTAPE 3: Traduction manuelle
            # =====================
            Write-Log ""
            Write-Log "[ÉTAPE 3/6] Traduction des sous-titres..."
            Write-Log "  --> Ouvrez le fichier SRT, traduisez-le, et sauvegardez."
            Write-Log "  --> Cliquez CONTINUER quand vous avez terminé."

            # Copier le SRT original pour la traduction
            Copy-Item $srtOriginal $srtTranslated -Force

            # Ouvrir le fichier pour traduction
            Start-Process $srtTranslated

            # Changer le bouton en "CONTINUER"
            $syncState.WaitingForContinue = $true
            $syncState.ContinueProcessing = $false
            $window.Dispatcher.Invoke([action]{
                $btnStart.Content = "CONTINUER (après traduction)"
                $btnStart.IsEnabled = $true
                $btnStart.Background = [System.Windows.Media.Brushes]::Orange
            })

            # Attendre que l'utilisateur clique CONTINUER
            while (-not $syncState.ContinueProcessing) {
                Start-Sleep -Milliseconds 200
            }

            $window.Dispatcher.Invoke([action]{
                $btnStart.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#107c10")
                $btnStart.IsEnabled = $false
                $btnStart.Content = "TRAITEMENT EN COURS..."
            })
            Write-Log "  [OK] Traduction confirmée"

            # =====================
            # ÉTAPE 4: Séparation vocale (Demucs) - EN DIRECT
            # =====================
            Write-Log ""
            Write-Log "[ÉTAPE 4/6] Séparation vocale (Demucs)..."
            Write-Log "  >>> OUVERTURE FENÊTRE DEMUCS - REGARDEZ LE TERMINAL <<<"
            Set-Status "[$(($i+1))/$total] Séparation vocale..."

            $demucsScript = Join-Path $scriptsDir "separate_vocals.py"
            $demucsOutput = Join-Path $workDir "demucs_output"

            # Lancer Demucs dans une VRAIE fenêtre CMD visible
            $cmdArgs = "/k `"echo ========================================== & echo DEMUCS - SEPARATION VOCALE & echo ========================================== & `"$python`" `"$demucsScript`" `"$fullAudio`" `"$demucsOutput`" & echo. & echo ========================================== & echo DEMUCS TERMINE - Appuyez sur une touche & echo ========================================== & pause`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -Wait

            Write-Log "  <<< FENÊTRE DEMUCS FERMÉE >>>"

            # Trouver le fichier no_vocals
            $demucsNoVocals = Join-Path $demucsOutput "htdemucs\$safeBasename`_full\no_vocals.wav"
            Write-Log "  [VERBOSE] Recherche: $demucsNoVocals"
            Write-Log "  [VERBOSE] Existe? $(Test-Path $demucsNoVocals)"

            # Lister le contenu du dossier Demucs
            Write-Log "  [VERBOSE] Contenu de $demucsOutput :"
            if (Test-Path $demucsOutput) {
                Get-ChildItem $demucsOutput -Recurse -EA SilentlyContinue | ForEach-Object {
                    Write-Log "    - $($_.FullName) ($($_.Length) bytes)"
                }
            } else {
                Write-Log "    [VERBOSE] Dossier n'existe pas!"
            }

            if (Test-Path $demucsNoVocals) {
                Write-Log "  [VERBOSE] Copie $demucsNoVocals -> $backgroundWav"
                Copy-Item $demucsNoVocals $backgroundWav -Force
                Write-Log "  [OK] Fond sonore extrait ($(([math]::Round((Get-Item $backgroundWav).Length/1MB,2))) MB)"
            } else {
                Write-Log "  [WARN] Demucs a échoué - fichier no_vocals.wav introuvable!"
                Write-Log "  [VERBOSE] Utilisation de l'audio original: $fullAudio"
                if (Test-Path $fullAudio) {
                    Copy-Item $fullAudio $backgroundWav -Force
                    Write-Log "  [VERBOSE] Copié vers: $backgroundWav"
                } else {
                    Write-Log "  [ERREUR] Audio original introuvable: $fullAudio"
                }
            }

            # Nettoyer
            Write-Log "  [VERBOSE] Nettoyage..."
            if (Test-Path $fullAudio) {
                Write-Log "  [VERBOSE] Suppression: $fullAudio"
                Remove-Item $fullAudio -Force -EA SilentlyContinue
            }
            if (-not $keepFiles) {
                if (Test-Path $demucsOutput) {
                    Write-Log "  [VERBOSE] Suppression dossier: $demucsOutput"
                    Remove-Item $demucsOutput -Recurse -Force -EA SilentlyContinue
                }
            }

            # =====================
            # ÉTAPE 5: Génération TTS
            # =====================
            Write-Log ""
            Write-Log "[ÉTAPE 5/6] Génération TTS (edge-tts)..."
            Set-Status "[$(($i+1))/$total] Génération vocale..."

            $ttsScript = Join-Path $scriptsDir "generate_tts.py"
            Write-Log "  [VERBOSE] Script: $ttsScript"
            Write-Log "  [VERBOSE] SRT: $srtTranslated"
            Write-Log "  [VERBOSE] Output: $ttsWav"
            Write-Log "  [VERBOSE] Langue: $targetLang, Voix: $voiceGender"

            # Lancer TTS dans une fenêtre visible
            Write-Log "  >>> OUVERTURE FENÊTRE TTS <<<"
            $ttsArgs = "/k `"echo ========================================== & echo TTS - GENERATION VOCALE & echo ========================================== & `"$python`" `"$ttsScript`" `"$srtTranslated`" `"$ttsWav`" $targetLang $voiceGender & echo. & echo ========================================== & echo TTS TERMINE - Appuyez sur une touche & echo ========================================== & pause`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $ttsArgs -Wait
            Write-Log "  <<< FENÊTRE TTS FERMÉE >>>"

            Write-Log "  [VERBOSE] Vérification $ttsWav"
            if (-not (Test-Path $ttsWav)) {
                Write-Log "  [ERREUR] TTS a échoué - fichier non créé!"
                $errors++
                continue
            }
            $ttsSize = [math]::Round((Get-Item $ttsWav).Length/1MB,2)
            Write-Log "  [OK] Audio TTS généré ($ttsSize MB)"

            # =====================
            # ÉTAPE 6: Mixage audio et assemblage
            # =====================
            Write-Log ""
            Write-Log "[ÉTAPE 6/6] Mixage et assemblage final..."
            Set-Status "[$(($i+1))/$total] Mixage audio..."

            # Vérifier les fichiers d'entrée
            Write-Log "  [VERBOSE] Background: $backgroundWav (existe: $(Test-Path $backgroundWav))"
            Write-Log "  [VERBOSE] TTS: $ttsWav (existe: $(Test-Path $ttsWav))"

            if (-not (Test-Path $backgroundWav)) {
                Write-Log "  [ERREUR] Fichier background manquant!"
                $errors++
                continue
            }
            if (-not (Test-Path $ttsWav)) {
                Write-Log "  [ERREUR] Fichier TTS manquant!"
                $errors++
                continue
            }

            # Mixer background + TTS - AVEC VERBOSE
            Write-Log "  [VERBOSE] Mixage audio..."
            Write-Log "  >>> OUVERTURE FENÊTRE FFMPEG MIXAGE <<<"
            $mixArgs = "/k `"echo ========================================== & echo FFMPEG - MIXAGE AUDIO & echo ========================================== & `"$ffmpeg`" -y -i `"$backgroundWav`" -i `"$ttsWav`" -filter_complex `"[0:a]volume=0.7[bg];[1:a]volume=1.3[tts];[bg][tts]amix=inputs=2:duration=first[out]`" -map `"[out]`" -c:a pcm_s16le `"$mixedWav`" & echo. & echo ========================================== & echo MIXAGE TERMINE - Appuyez sur une touche & echo ========================================== & pause`""
            Start-Process -FilePath "cmd.exe" -ArgumentList $mixArgs -Wait
            Write-Log "  <<< FENÊTRE FFMPEG MIXAGE FERMÉE >>>"

            Write-Log "  [VERBOSE] Vérification $mixedWav"
            if (-not (Test-Path $mixedWav)) {
                Write-Log "  [ERREUR] Mixage audio échoué - fichier non créé!"
                $errors++
                continue
            }
            $mixSize = [math]::Round((Get-Item $mixedWav).Length/1MB,2)
            Write-Log "  [OK] Audio mixé ($mixSize MB)"

            # Assemblage vidéo finale
            Write-Log "  [VERBOSE] Assemblage vidéo..."
            Set-Status "[$(($i+1))/$total] Création vidéo finale..."

            if ($addSubtitles) {
                # Avec sous-titres - copier le SRT dans le workDir pour éviter problèmes de chemin
                $srtWork = Join-Path $workDir "subtitles.srt"
                Write-Log "  [VERBOSE] Copie SRT: $srtTranslated -> $srtWork"
                Copy-Item -LiteralPath $srtTranslated -Destination $srtWork -Force
                $srtE = $srtWork.Replace('\', '/').Replace(':', '\:')
                Write-Log "  [VERBOSE] SRT échappé: $srtE"
                Write-Log "  >>> OUVERTURE FENÊTRE FFMPEG VIDÉO <<<"
                $videoArgs = "/k `"echo ========================================== & echo FFMPEG - ASSEMBLAGE VIDEO AVEC SOUS-TITRES & echo ========================================== & `"$ffmpeg`" -y -i `"$workFile`" -i `"$mixedWav`" -vf `"subtitles='$srtE':force_style='FontName=Arial,FontSize=22,PrimaryColour=&HFFFFFF,OutlineColour=&H000000,BorderStyle=3'`" -c:v libx264 -crf 23 -preset fast -map 0:v -map 1:a -c:a aac -b:a 192k -pix_fmt yuv420p `"$tempOutput`" & echo. & echo ========================================== & echo ASSEMBLAGE TERMINE - Appuyez sur une touche & echo ========================================== & pause`""
                Start-Process -FilePath "cmd.exe" -ArgumentList $videoArgs -Wait
            } else {
                # Sans sous-titres
                Write-Log "  >>> OUVERTURE FENÊTRE FFMPEG VIDÉO <<<"
                $videoArgs = "/k `"echo ========================================== & echo FFMPEG - ASSEMBLAGE VIDEO & echo ========================================== & `"$ffmpeg`" -y -i `"$workFile`" -i `"$mixedWav`" -c:v copy -map 0:v -map 1:a -c:a aac -b:a 192k `"$tempOutput`" & echo. & echo ========================================== & echo ASSEMBLAGE TERMINE - Appuyez sur une touche & echo ========================================== & pause`""
                Start-Process -FilePath "cmd.exe" -ArgumentList $videoArgs -Wait
            }
            Write-Log "  <<< FENÊTRE FFMPEG VIDÉO FERMÉE >>>"

            # Copier le résultat vers le dossier original
            Write-Log "  [VERBOSE] Vérification $tempOutput"
            if (Test-Path $tempOutput) {
                $tempSize = [math]::Round((Get-Item $tempOutput).Length/1MB,2)
                Write-Log "  [VERBOSE] Vidéo temp créée ($tempSize MB)"
                Write-Log "  [VERBOSE] Copie vers: $outputFile"

                try {
                    Copy-Item -LiteralPath $tempOutput -Destination $outputFile -Force -ErrorAction Stop
                    Write-Log "  [VERBOSE] Copie réussie!"
                } catch {
                    Write-Log "  [WARN] Copie échouée: $_"
                    Write-Log "  [VERBOSE] Tentative de copie vers dossier script..."

                    # Fallback: sauvegarder dans le dossier du script
                    $fallbackOutput = Join-Path $scriptDir "$originalBasename`_translated_$ts.mp4"
                    try {
                        Copy-Item -LiteralPath $tempOutput -Destination $fallbackOutput -Force -ErrorAction Stop
                        $outputFile = $fallbackOutput
                        Write-Log "  [OK] Vidéo sauvegardée dans: $fallbackOutput"
                    } catch {
                        Write-Log "  [ERREUR] Copie fallback échouée: $_"
                        # Dernier recours: laisser dans TEMP
                        $tempKeep = Join-Path $scriptDir "TEMP\$originalBasename`_translated_$ts.mp4"
                        Copy-Item -LiteralPath $tempOutput -Destination $tempKeep -Force -EA SilentlyContinue
                        $outputFile = $tempKeep
                        Write-Log "  [WARN] Vidéo laissée dans: $tempKeep"
                    }
                }
            } else {
                Write-Log "  [ERREUR] Vidéo temp non créée!"
            }

            # Copier le SRT traduit si l'utilisateur veut le garder
            if ($keepFiles -and (Test-Path $srtTranslated)) {
                Copy-Item -LiteralPath $srtTranslated -Destination $finalSrtFile -Force
                Write-Log "  [VERBOSE] SRT sauvegardé: $finalSrtFile"
            }

            # Vérifier et nettoyer
            Write-Log "  [VERBOSE] Vérification finale: $outputFile"
            if (Test-Path -LiteralPath $outputFile) {
                $fileSize = [math]::Round((Get-Item $outputFile).Length / 1MB, 2)
                Write-Log ""
                Write-Log "[SUCCESS] Vidéo créée: $([IO.Path]::GetFileName($outputFile))"
                Write-Log "  Taille: $fileSize Mo"
                Write-Log "  Chemin: $outputFile"
                $success++
            } else {
                Write-Log "[ERREUR] Création vidéo échouée - fichier final non trouvé!"
                Write-Log "  [VERBOSE] Attendu: $outputFile"
                $errors++
            }

            # Nettoyer le dossier de travail temporaire (sauf si la vidéo finale y est)
            Write-Log ""
            Write-Log "  [VERBOSE] === NETTOYAGE FINAL ==="
            if ($outputFile -like "$workDir*") {
                Write-Log "  [VERBOSE] Vidéo finale dans workDir - pas de suppression"
                Write-Log "  [VERBOSE] Fichier: $outputFile"
            } elseif (Test-Path $workDir) {
                Write-Log "  [VERBOSE] Contenu workDir avant suppression:"
                Get-ChildItem $workDir -Recurse -EA SilentlyContinue | ForEach-Object {
                    Write-Log "    - $($_.FullName)"
                }
                Write-Log "  [VERBOSE] Suppression: $workDir"
                Remove-Item $workDir -Recurse -Force -EA SilentlyContinue
                Write-Log "  [VERBOSE] Supprimé!"
            } else {
                Write-Log "  [VERBOSE] workDir n'existe plus: $workDir"
            }

            Set-Progress ([int](($i + 1) / $total * 100))
        }

        Write-Log ""
        Write-Log "============================================"
        Write-Log "TERMINÉ: $success/$total réussi(s), $errors erreur(s)"
        Write-Log "============================================"
        Set-Status "Terminé!"

        $window.Dispatcher.Invoke([action]{
            $btnStart.Content = "DÉMARRER LA TRADUCTION"
            $btnStart.IsEnabled = $true
            [System.Windows.MessageBox]::Show(
                "Traitement terminé!`n$success/$total fichier(s) traduit(s).",
                "Terminé", "OK", "Information")
        })
    })

    [void]$powershell.BeginInvoke()
})

# Vérifier les dépendances au démarrage
if (-not (Test-Path $ffmpeg)) {
    Write-Log "[ERREUR] FFmpeg non trouvé - Exécutez INSTALLER.bat"
} elseif (-not (Test-Path $whisper)) {
    Write-Log "[ERREUR] Whisper non trouvé - Exécutez INSTALLER.bat"
} elseif (-not (Test-Path $python)) {
    Write-Log "[ERREUR] Python non trouvé - Exécutez INSTALLER.bat"
} else {
    Write-Log "[OK] Composants de base installés"

    # Vérifier les dépendances Python
    $testResult = & $python -c "import demucs; import edge_tts" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "[WARN] Dépendances Python manquantes"
        Write-Log "       Cliquez 'Installer les dépendances' pour les installer"
    } else {
        Write-Log "[OK] Dépendances Python installées (Demucs, edge-tts)"
    }
}

# Afficher la fenêtre
[void]$window.ShowDialog()
