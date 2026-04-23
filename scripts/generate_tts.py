#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Génération TTS avec Microsoft Edge TTS
Génère un fichier audio à partir d'un fichier SRT traduit.
"""

import sys
import os
import asyncio
import pysrt
import edge_tts
import tempfile
import wave
import struct


# Voix disponibles par langue
VOICES = {
    # Français Québécois
    "fr-CA": {
        "female": "fr-CA-SylvieNeural",
        "male": "fr-CA-JeanNeural",
        "default": "fr-CA-SylvieNeural"
    },
    # Français France
    "fr-FR": {
        "female": "fr-FR-DeniseNeural",
        "male": "fr-FR-HenriNeural",
        "default": "fr-FR-DeniseNeural"
    },
    # Alias
    "fr": {
        "female": "fr-CA-SylvieNeural",
        "male": "fr-CA-JeanNeural",
        "default": "fr-CA-SylvieNeural"
    },
    # Anglais US
    "en": {
        "female": "en-US-JennyNeural",
        "male": "en-US-GuyNeural",
        "default": "en-US-JennyNeural"
    },
    "en-US": {
        "female": "en-US-JennyNeural",
        "male": "en-US-GuyNeural",
        "default": "en-US-JennyNeural"
    },
    # Anglais UK
    "en-GB": {
        "female": "en-GB-SoniaNeural",
        "male": "en-GB-RyanNeural",
        "default": "en-GB-SoniaNeural"
    },
    # Espagnol
    "es": {
        "female": "es-ES-ElviraNeural",
        "male": "es-ES-AlvaroNeural",
        "default": "es-ES-ElviraNeural"
    },
    # Allemand
    "de": {
        "female": "de-DE-KatjaNeural",
        "male": "de-DE-ConradNeural",
        "default": "de-DE-KatjaNeural"
    },
    # Italien
    "it": {
        "female": "it-IT-ElsaNeural",
        "male": "it-IT-DiegoNeural",
        "default": "it-IT-ElsaNeural"
    },
    # Portugais
    "pt": {
        "female": "pt-BR-FranciscaNeural",
        "male": "pt-BR-AntonioNeural",
        "default": "pt-BR-FranciscaNeural"
    }
}


def get_voice(language, gender="default"):
    """Retourne la voix appropriée pour la langue et le genre."""
    lang_voices = VOICES.get(language, VOICES.get("en"))
    return lang_voices.get(gender, lang_voices["default"])


def parse_srt_time_to_ms(srt_time):
    """Convertit un timestamp SRT en millisecondes."""
    return srt_time.ordinal


async def generate_segment_audio(text, voice, output_file):
    """Génère l'audio pour un segment de texte."""
    communicate = edge_tts.Communicate(text, voice)
    await communicate.save(output_file)


def get_audio_duration_ms(wav_file):
    """Retourne la durée d'un fichier WAV en millisecondes."""
    try:
        with wave.open(wav_file, 'rb') as wf:
            frames = wf.getnframes()
            rate = wf.getframerate()
            duration = frames / float(rate)
            return int(duration * 1000)
    except:
        return 0


def convert_mp3_to_wav(mp3_file, wav_file):
    """Convertit un MP3 en WAV en utilisant ffmpeg."""
    import subprocess
    try:
        subprocess.run([
            "ffmpeg", "-y", "-i", mp3_file,
            "-ar", "24000", "-ac", "1", "-acodec", "pcm_s16le",
            wav_file
        ], capture_output=True, check=True)
        return True
    except:
        return False


async def generate_dubbed_audio(srt_file, output_wav, language="fr-CA", gender="default"):
    """
    Génère un fichier audio doublé à partir d'un fichier SRT.

    Args:
        srt_file: Chemin du fichier SRT traduit
        output_wav: Chemin de sortie pour le fichier WAV
        language: Code langue (fr-CA, fr-FR, en, es, de, it, pt)
        gender: Genre de la voix (male, female, default)

    Returns:
        True si succès, False sinon
    """
    if not os.path.exists(srt_file):
        print(f"[ERREUR] Fichier SRT non trouvé: {srt_file}")
        return False

    voice = get_voice(language, gender)
    print(f"[TTS] Génération audio avec edge-tts...")
    print(f"  SRT: {srt_file}")
    print(f"  Voix: {voice}")
    print(f"  Sortie: {output_wav}")

    # Parser le fichier SRT
    try:
        subs = pysrt.open(srt_file, encoding='utf-8')
    except:
        try:
            subs = pysrt.open(srt_file, encoding='latin-1')
        except Exception as e:
            print(f"[ERREUR] Impossible de lire le SRT: {e}")
            return False

    if len(subs) == 0:
        print("[ERREUR] Fichier SRT vide")
        return False

    print(f"  Segments: {len(subs)}")

    # Créer un dossier temporaire pour les segments
    temp_dir = tempfile.mkdtemp(prefix="tts_")
    segment_files = []

    try:
        # Générer chaque segment
        for i, sub in enumerate(subs):
            text = sub.text.replace('\n', ' ').strip()
            if not text:
                continue

            start_ms = parse_srt_time_to_ms(sub.start)
            end_ms = parse_srt_time_to_ms(sub.end)

            print(f"  [{i+1}/{len(subs)}] {start_ms/1000:.1f}s: {text[:50]}...")

            # Générer l'audio du segment
            segment_mp3 = os.path.join(temp_dir, f"segment_{i:04d}.mp3")
            segment_wav = os.path.join(temp_dir, f"segment_{i:04d}.wav")

            try:
                await generate_segment_audio(text, voice, segment_mp3)

                # Convertir en WAV
                if os.path.exists(segment_mp3):
                    convert_mp3_to_wav(segment_mp3, segment_wav)

                    if os.path.exists(segment_wav):
                        segment_files.append({
                            'file': segment_wav,
                            'start_ms': start_ms,
                            'end_ms': end_ms
                        })
            except Exception as e:
                print(f"    [WARN] Erreur segment {i}: {e}")

        if not segment_files:
            print("[ERREUR] Aucun segment audio généré")
            return False

        # Assembler tous les segments avec FFmpeg
        print(f"[TTS] Assemblage de {len(segment_files)} segments...")

        # Calculer la durée totale
        last_sub = subs[-1]
        total_duration_ms = parse_srt_time_to_ms(last_sub.end) + 2000

        # Créer un fichier de silence de la durée totale
        silence_file = os.path.join(temp_dir, "silence.wav")
        import subprocess
        subprocess.run([
            "ffmpeg", "-y", "-f", "lavfi",
            "-i", f"anullsrc=r=24000:cl=mono",
            "-t", str(total_duration_ms / 1000),
            "-acodec", "pcm_s16le",
            silence_file
        ], capture_output=True)

        # Créer le fichier filter_complex pour FFmpeg
        filter_parts = []
        inputs = ["-i", silence_file]

        for i, seg in enumerate(segment_files):
            inputs.extend(["-i", seg['file']])
            delay_ms = seg['start_ms']
            filter_parts.append(f"[{i+1}]adelay={delay_ms}|{delay_ms}[d{i}]")

        # Mixer tous les segments
        mix_inputs = "[0]" + "".join([f"[d{i}]" for i in range(len(segment_files))])
        filter_parts.append(f"{mix_inputs}amix=inputs={len(segment_files)+1}:duration=first:dropout_transition=0[out]")

        filter_complex = ";".join(filter_parts)

        # Exécuter FFmpeg
        cmd = ["ffmpeg", "-y"] + inputs + [
            "-filter_complex", filter_complex,
            "-map", "[out]",
            "-ar", "24000", "-ac", "1",
            output_wav
        ]

        result = subprocess.run(cmd, capture_output=True)

        if result.returncode != 0 or not os.path.exists(output_wav):
            print(f"[ERREUR] FFmpeg assemblage échoué")
            # Fallback: concaténer simplement les fichiers
            print("[TTS] Tentative de fallback...")
            concat_file = os.path.join(temp_dir, "concat.txt")
            with open(concat_file, 'w') as f:
                for seg in segment_files:
                    f.write(f"file '{seg['file']}'\n")

            subprocess.run([
                "ffmpeg", "-y", "-f", "concat", "-safe", "0",
                "-i", concat_file, "-ar", "24000", "-ac", "1", output_wav
            ], capture_output=True)

        if os.path.exists(output_wav):
            file_size = os.path.getsize(output_wav) / (1024 * 1024)
            print(f"[OK] Audio généré: {output_wav} ({file_size:.1f} MB)")
            return True
        else:
            print("[ERREUR] Fichier de sortie non créé")
            return False

    finally:
        # Nettoyer les fichiers temporaires
        import shutil
        try:
            shutil.rmtree(temp_dir)
        except:
            pass


def list_available_voices():
    """Affiche les voix disponibles."""
    print("Voix disponibles:")
    for lang, voices in VOICES.items():
        print(f"  {lang}:")
        for gender, voice in voices.items():
            print(f"    {gender}: {voice}")


def main():
    if len(sys.argv) < 3:
        print("Usage: python generate_tts.py <srt_file> <output_wav> [language] [gender]")
        print("")
        print("Exemples:")
        print("  python generate_tts.py subtitles.srt output.wav fr-CA")
        print("  python generate_tts.py subtitles.srt output.wav fr-CA female")
        print("  python generate_tts.py subtitles.srt output.wav en male")
        print("")
        list_available_voices()
        sys.exit(1)

    srt_file = sys.argv[1]
    output_wav = sys.argv[2]
    language = sys.argv[3] if len(sys.argv) > 3 else "fr-CA"
    gender = sys.argv[4] if len(sys.argv) > 4 else "default"

    success = asyncio.run(generate_dubbed_audio(srt_file, output_wav, language, gender))
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
