# Automatic Subtitles

Outil portable Windows pour générer automatiquement des sous-titres et les incruster dans des vidéos.

## Fonctionnalités

- **Transcription automatique** avec [Whisper](https://github.com/ggerganov/whisper.cpp) (fonctionne hors-ligne)
- **Incrustation des sous-titres** dans la vidéo avec FFmpeg
- **Détection automatique** : utilise la vidéo source si présente, sinon génère une visualisation audio
- **Interface graphique** simple et intuitive
- **100% portable** : aucune installation requise, fonctionne sur clé USB

## Capture d'écran

L'interface permet de :
- Sélectionner plusieurs fichiers audio/vidéo
- Choisir le modèle Whisper (tiny, base, small, medium, large)
- Choisir la langue source
- Réviser les sous-titres avant intégration
- Voir Whisper travailler en direct dans le terminal

## Installation

### Option 1 : Télécharger le package complet
1. Téléchargez la dernière release
2. Extrayez le ZIP
3. Double-cliquez sur `Automatic Subtitles.bat`

### Option 2 : Installation manuelle
1. Clonez ce dépôt
2. Exécutez `INSTALLER.bat` pour télécharger les dépendances :
   - FFmpeg
   - whisper.cpp
   - Modèle Whisper (base)

## Utilisation

### Interface graphique
1. Double-cliquez sur `Automatic Subtitles.bat`
2. Ajoutez vos fichiers audio/vidéo
3. Configurez les options selon vos besoins
4. Cliquez sur "Démarrer le traitement"

### Ligne de commande (glisser-déposer)
Glissez-déposez vos fichiers sur `run.bat` pour un traitement rapide avec les paramètres par défaut.

## Modèles Whisper

| Modèle | Taille | RAM requise | Qualité |
|--------|--------|-------------|---------|
| tiny | ~75 Mo | ~1 Go | Basique |
| base | ~150 Mo | ~1 Go | Correcte |
| small | ~500 Mo | ~2 Go | Bonne |
| medium | ~1.5 Go | ~5 Go | Très bonne |
| large | ~3 Go | ~10 Go | Excellente |

Téléchargez des modèles supplémentaires via le bouton "Télécharger ce modèle" dans l'interface.

## Langues supportées

- Français
- Anglais
- Espagnol
- Allemand
- Italien
- Portugais
- Auto-détection

## Structure du projet

```
Automatic_Subtitles/
├── bin/
│   ├── ffmpeg/          # FFmpeg portable
│   ├── whisper/         # whisper.cpp + modèles
│   └── python/          # Python embedded (pour extensions futures)
├── Automatic Subtitles.bat   # Lanceur principal
├── gui.ps1                   # Interface graphique
├── run.bat                   # Mode glisser-déposer
├── INSTALLER.bat             # Installation des dépendances
└── setup.ps1                 # Script d'installation
```

## Prérequis

- Windows 10/11
- Aucune installation requise (tout est inclus)

## Formats supportés

**Entrée :** MP3, M4A, WAV, FLAC, AAC, OGG, WMA, MP4, MKV, AVI, MOV, WEBM

**Sortie :** MP4 (H.264 + AAC)

## Crédits

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - Implémentation C++ de Whisper
- [FFmpeg](https://ffmpeg.org/) - Traitement audio/vidéo
- [OpenAI Whisper](https://github.com/openai/whisper) - Modèle de reconnaissance vocale

## Licence

MIT License
