#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Séparation vocale avec Demucs (Meta AI)
Sépare la voix du fond sonore d'un fichier audio/vidéo.
"""

import sys
import os
import subprocess
import shutil
import re
import time


def separate_vocals(input_file, output_dir, progress_file=None):
    """
    Sépare les vocals du fond sonore.

    Args:
        input_file: Chemin du fichier audio/vidéo d'entrée
        output_dir: Dossier de sortie pour les fichiers séparés
        progress_file: Fichier optionnel pour écrire la progression

    Returns:
        Tuple (vocals_path, no_vocals_path) ou None en cas d'erreur
    """
    if not os.path.exists(input_file):
        print(f"[ERREUR] Fichier non trouvé: {input_file}")
        return None

    os.makedirs(output_dir, exist_ok=True)

    print(f"[Demucs] Séparation vocale en cours...")
    print(f"  Entrée: {input_file}")
    print(f"  Sortie: {output_dir}")

    # Écrire progression initiale
    if progress_file:
        with open(progress_file, 'w', encoding='utf-8') as f:
            f.write("0|Démarrage...")

    try:
        # Utiliser demucs en ligne de commande pour plus de contrôle
        # --two-stems vocals: sépare uniquement vocals vs le reste
        # -n htdemucs: utilise le modèle htdemucs (meilleure qualité)
        cmd = [
            sys.executable, "-m", "demucs",
            "-n", "htdemucs",
            "--two-stems", "vocals",
            "-o", output_dir,
            input_file
        ]

        # Lancer Demucs et afficher TOUTE la sortie
        print("=" * 60, flush=True)
        print("DEMUCS - SORTIE COMPLÈTE", flush=True)
        print("=" * 60, flush=True)

        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Combiner stderr dans stdout
            text=True,
            encoding='utf-8',
            errors='replace',
            bufsize=1
        )

        last_percent = 0

        # Lire et afficher TOUT ligne par ligne
        for line in process.stdout:
            line = line.rstrip()
            if line:
                print(f"[DEMUCS] {line}", flush=True)

                # Extraire le pourcentage pour le fichier de progression
                match = re.search(r'(\d+)%\|', line)
                if match:
                    percent = int(match.group(1))
                    if percent > last_percent:
                        last_percent = percent
                        if progress_file:
                            with open(progress_file, 'w', encoding='utf-8') as f:
                                f.write(f"{percent}|Séparation en cours...")

        returncode = process.wait()

        print("=" * 60, flush=True)
        print(f"DEMUCS TERMINÉ - Code retour: {returncode}", flush=True)
        print("=" * 60, flush=True)

        if returncode != 0:
            print(f"[ERREUR] Demucs a échoué (code {returncode})")
            if progress_file:
                with open(progress_file, 'w', encoding='utf-8') as f:
                    f.write(f"-1|Code erreur {returncode}")
            return None

        # Trouver les fichiers de sortie
        basename = os.path.splitext(os.path.basename(input_file))[0]
        demucs_output = os.path.join(output_dir, "htdemucs", basename)

        vocals_path = os.path.join(demucs_output, "vocals.wav")
        no_vocals_path = os.path.join(demucs_output, "no_vocals.wav")

        if not os.path.exists(no_vocals_path):
            print(f"[ERREUR] Fichier no_vocals.wav non créé")
            if progress_file:
                with open(progress_file, 'w', encoding='utf-8') as f:
                    f.write("-1|Fichier non créé")
            return None

        print(f"[OK] Séparation terminée!")
        print(f"  Vocals: {vocals_path}")
        print(f"  Background: {no_vocals_path}")

        # Écrire progression finale
        if progress_file:
            with open(progress_file, 'w', encoding='utf-8') as f:
                f.write("100|Terminé")

        return (vocals_path, no_vocals_path)

    except Exception as e:
        print(f"[ERREUR] Exception: {str(e)}")
        if progress_file:
            with open(progress_file, 'w', encoding='utf-8') as f:
                f.write(f"-1|Erreur: {str(e)}")
        return None


def main():
    if len(sys.argv) < 3:
        print("Usage: python separate_vocals.py <input_file> <output_dir> [progress_file]")
        print("Exemple: python separate_vocals.py video.mp4 ./output ./progress.txt")
        sys.exit(1)

    input_file = sys.argv[1]
    output_dir = sys.argv[2]
    progress_file = sys.argv[3] if len(sys.argv) > 3 else None

    result = separate_vocals(input_file, output_dir, progress_file)

    if result:
        print(f"\nFichiers créés:")
        print(f"  Vocals: {result[0]}")
        print(f"  Background: {result[1]}")
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
