# Automatic Subtitles

Outils portables Windows pour générer, traduire et incruster des sous-titres dans des vidéos.

## Outils inclus

| Lanceur | Description |
|---------|-------------|
| `Automatic Subtitles.bat` | Transcription automatique + incrustation de sous-titres (Whisper) |
| `Video Translator.bat` | Traduction vidéo complète avec doublage vocal (Whisper + Demucs + TTS) |
| `Burn 360 Subtitles.bat` | Incrustation de sous-titres dans des vidéos 360° (projection sphérique) |

---

## Outil 1 : Automatic Subtitles (transcription)

### Fonctionnalités
- Transcription automatique avec [whisper.cpp](https://github.com/ggerganov/whisper.cpp) (hors-ligne)
- Incrustation des sous-titres dans la vidéo avec FFmpeg
- Détection automatique : utilise la vidéo source si présente, sinon génère une visualisation audio
- Interface graphique simple et intuitive
- 100 % portable : aucune installation requise

### Utilisation
1. Double-cliquez sur `Automatic Subtitles.bat`
2. Ajoutez vos fichiers audio/vidéo
3. Choisissez le modèle Whisper et la langue source
4. Révisez les sous-titres, puis cliquez sur "Intégrer"

---

## Outil 2 : Video Translator (traduction avec doublage)

Pipeline en 7 étapes : extraction audio → transcription → séparation vocale → TTS → mixage → assemblage.

### Installation des dépendances supplémentaires
Exécutez `INSTALL_TRANSLATOR.bat` (installe torch/torchaudio CPU, Demucs, edge-tts, numpy, scipy).

### Utilisation interactive
Double-cliquez sur `Video Translator.bat` et suivez les invites.

### Utilisation CLI (débogage / reprise)
```
python translate_cli.py video.mp4 --lang-tts fr-CA --gender narrator
python translate_cli.py video.mp4 --lang-src en --lang-tts fr-FR --model small
python translate_cli.py --work-dir TEMP\translate_xxx --from-step 4
python translate_cli.py video.mp4 --only-step 4 --work-dir TEMP\translate_xxx
python translate_cli.py video.mp4 --only-step 6 --bg-vol 0.5 --tts-vol 1.8 --work-dir TEMP\xxx
```

### Pipeline détaillé

| Étape | Description | Fichier produit |
|-------|-------------|-----------------|
| 1 | Extraction audio (16 kHz pour Whisper + 44,1 kHz pour Demucs) | `step1_audio_16k.wav`, `step1_audio_44k.wav` |
| 2 | Transcription Whisper → SRT **[pause : vous éditez/traduisez le SRT]** | `step2_subtitles.srt` |
| 3 | Séparation vocale Demucs (suppression de la voix originale) | `step3_background.wav` |
| 4 | Génération des clips TTS (un par ligne de sous-titre) | `step4_tts_clips/clip_NNNN.mp3` |
| 5 | Fusion des clips TTS sur la timeline exacte des SRT | `step5_tts_merged.wav` |
| 6 | Mixage audio (fond + TTS) | `step6_mixed.wav` |
| 7 | Assemblage final (vidéo + audio mixé) | `output/<nom>_translated.mp4` |

Tous les fichiers intermédiaires sont conservés dans `TEMP/translate_YYYYMMDD_HHMMSS/`.

### Voix TTS disponibles

La voix par défaut s'applique aux lignes sans directive. On peut forcer la voix ligne par ligne :

| Directive dans le SRT | Voix utilisée |
|-----------------------|---------------|
| *(aucune)* | voix par défaut (choix au démarrage) |
| `[NARRATEUR]` ou `[NARRATOR]` | voix narrateur |
| `[HOMME]` ou `[MAN]` | voix masculine |
| `[FEMME]` ou `[WOMAN]` | voix féminine |
| `[autre texte entre crochets]` | ligne silencieuse (tag supprimé) |

Voix Neural disponibles par langue :

| Langue | Féminine | Masculine | Narrateur |
|--------|----------|-----------|-----------|
| fr-CA | SylvieNeural | ThierryNeural | **AntoineNeural** |
| fr-FR | DeniseNeural | HenriNeural | YvesNeural |
| en-US | JennyNeural | GuyNeural | ChristopherNeural |
| en-GB | SoniaNeural | RyanNeural | EthanNeural |
| es | ElviraNeural | AlvaroNeural | EstrellaNeural |
| de | KatjaNeural | ConradNeural | KillianNeural |
| it | ElsaNeural | DiegoNeural | IsabellaNeural |
| pt | FranciscaNeural | AntonioNeural | ThalitaNeural |

---

## Outil 3 : Burn 360 Subtitles

Incruste des sous-titres (fichier SRT) dans une vidéo 360° en tenant compte de la projection sphérique (360 3D Top-Bottom supporté).

### Utilisation
Double-cliquez sur `Burn 360 Subtitles.bat` et suivez les invites.

---

## Modèles Whisper

| Modèle | Taille | RAM requise | Qualité |
|--------|--------|-------------|---------|
| tiny | ~75 Mo | ~1 Go | Basique |
| base | ~150 Mo | ~1 Go | Correcte |
| small | ~500 Mo | ~2 Go | Bonne |
| medium | ~1,5 Go | ~5 Go | Très bonne |
| large | ~3 Go | ~10 Go | Excellente |

---

## Installation

### Outils de base (transcription + Burn 360)
1. Téléchargez la dernière release et extrayez le ZIP, **ou** clonez ce dépôt puis exécutez `INSTALLER.bat`
2. Double-cliquez sur `Automatic Subtitles.bat`

### Traducteur vidéo (dépendances supplémentaires)
1. Exécutez d'abord `INSTALLER.bat`
2. Exécutez ensuite `INSTALL_TRANSLATOR.bat` (télécharge PyTorch CPU, Demucs, edge-tts…)

---

## Structure du projet

```
Automatic_Subtitles/
├── bin/
│   ├── ffmpeg/           # FFmpeg portable
│   ├── whisper/          # whisper.cpp + modèles ggml-*.bin
│   └── python/           # Python 3.12 embarqué
├── Automatic Subtitles.bat   # Transcription + incrustation
├── Video Translator.bat      # Traduction avec doublage vocal
├── Burn 360 Subtitles.bat    # Incrustation sous-titres 360°
├── translate_cli.py          # Moteur du traducteur (CLI)
├── gui.ps1                   # Interface graphique (transcription)
├── burn_360_subs.ps1         # Script incrustation 360°
├── INSTALLER.bat             # Dépendances de base (FFmpeg, Whisper)
├── INSTALL_TRANSLATOR.bat    # Dépendances traducteur (Demucs, TTS…)
└── TEMP/                     # Fichiers de travail (un dossier par traduction)
```

---

## Prérequis

- Windows 10 / 11
- Connexion Internet pour le premier téléchargement des modèles et des voix TTS (edge-tts)

## Formats supportés

**Entrée :** MP3, M4A, WAV, FLAC, AAC, OGG, WMA, MP4, MKV, AVI, MOV, WEBM

**Sortie :** MP4 (H.264 + AAC)

## Crédits

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — Transcription hors-ligne
- [Demucs](https://github.com/facebookresearch/demucs) — Séparation source audio (Meta AI)
- [edge-tts](https://github.com/rany2/edge-tts) — Synthèse vocale Microsoft Neural (gratuit, sans clé API)
- [FFmpeg](https://ffmpeg.org/) — Traitement audio/vidéo

## Licence

MIT License
