#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
translate_cli.py — Video Translator CLI

When launched with no arguments (double-click): interactive prompts.
When launched with arguments: argparse CLI (for debugging).

Pipeline:
  1  Extract audio  (16kHz WAV for Whisper + 44.1kHz WAV for Demucs)
  2  Transcribe     (Whisper → SRT)  [PAUSE: you edit/translate the SRT]
  3  Separate       (Demucs → step3_background.wav)
  4  TTS clips      (edge-tts → step4_tts_clips/clip_NNNN.wav, one per subtitle)
  5  Merge TTS      (numpy timeline → step5_tts_merged.wav)
  6  Mix audio      (FFmpeg: background + TTS → step6_mixed.wav)
  7  Assemble       (FFmpeg: video + mixed audio → output/<name>_translated.mp4)

All intermediate files are kept in the work directory (TEMP/translate_YYYYMMDD_HHMMSS/).

Debug usage (no interactive prompts):
  python translate_cli.py video.mp4 --lang-tts fr-CA --gender female
  python translate_cli.py video.mp4 --lang-src en --lang-tts fr-FR --model small
  python translate_cli.py --work-dir TEMP\\translate_xxx --from-step 4
  python translate_cli.py video.mp4 --only-step 4 --work-dir TEMP\\translate_xxx
  python translate_cli.py video.mp4 --only-step 6 --bg-vol 0.5 --tts-vol 1.8 --work-dir TEMP\\xxx
"""

import argparse
import asyncio
import json
import re
import shutil
import subprocess
import sys
import wave
from datetime import datetime
from pathlib import Path

# ─── Binary paths ─────────────────────────────────────────────────────────────

SCRIPT_DIR  = Path(__file__).parent.resolve()
FFMPEG      = SCRIPT_DIR / "bin" / "ffmpeg" / "ffmpeg.exe"
WHISPER     = SCRIPT_DIR / "bin" / "whisper" / "Release" / "whisper-cli.exe"
WHISPER_DIR = SCRIPT_DIR / "bin" / "whisper"
PYTHON      = SCRIPT_DIR / "bin" / "python" / "python.exe"

# ─── TTS voice map ────────────────────────────────────────────────────────────

VOICES = {
    "fr-CA": {"female": "fr-CA-SylvieNeural",     "male": "fr-CA-JeanNeural"},
    "fr-FR": {"female": "fr-FR-DeniseNeural",     "male": "fr-FR-HenriNeural"},
    "fr":    {"female": "fr-CA-SylvieNeural",     "male": "fr-CA-JeanNeural"},
    "en-US": {"female": "en-US-JennyNeural",      "male": "en-US-GuyNeural"},
    "en-GB": {"female": "en-GB-SoniaNeural",      "male": "en-GB-RyanNeural"},
    "en":    {"female": "en-US-JennyNeural",      "male": "en-US-GuyNeural"},
    "es":    {"female": "es-ES-ElviraNeural",     "male": "es-ES-AlvaroNeural"},
    "de":    {"female": "de-DE-KatjaNeural",      "male": "de-DE-ConradNeural"},
    "it":    {"female": "it-IT-ElsaNeural",       "male": "it-IT-DiegoNeural"},
    "pt":    {"female": "pt-BR-FranciscaNeural",  "male": "pt-BR-AntonioNeural"},
}


# ─── Subtitle text helpers ───────────────────────────────────────────────────

# [MAN] / [HOMME] → force male voice for that line
# [WOMAN] / [FEMME] → force female voice for that line
# Any other [bracketed content] is stripped and NOT voiced
VOICE_DIRECTIVES = {
    "[man]":    "male",
    "[homme]":  "male",
    "[woman]":  "female",
    "[femme]":  "female",
}


def ms_to_timecode(ms: int) -> str:
    """Convert milliseconds to a safe filename fragment: 00h01m23s456"""
    h    = ms // 3_600_000; ms -= h * 3_600_000
    m    = ms //    60_000; ms -= m *    60_000
    s    = ms //     1_000; ms -= s *     1_000
    return f"{h:02d}h{m:02d}m{s:02d}s{ms:03d}"


def parse_subtitle(text: str, voice_map: dict) -> tuple:
    """
    Returns (clean_text, voice) or (None, None) to skip this subtitle.

    Rules:
    - [MAN] / [HOMME]  → use male voice, strip the tag
    - [WOMAN] / [FEMME] → use female voice, strip the tag
    - Any other [bracketed content] → stripped silently
    - If nothing is left after stripping, return (None, None)
    """
    voice_override = None
    lower = text.lower()

    for tag, gender in VOICE_DIRECTIVES.items():
        if tag in lower:
            voice_override = voice_map[gender]
            text = re.sub(re.escape(tag), "", text, flags=re.IGNORECASE)

    # Strip ALL remaining [bracketed content] (e.g. [MUSIQUE], [inaudible])
    text = re.sub(r'\[.*?\]', '', text)
    # Collapse extra whitespace left by stripping
    text = re.sub(r'\s+', ' ', text).strip()

    if not text:
        return None, None

    return text, voice_override   # None voice_override → caller uses its default


# ─── Timecode ↔ ms (used by overlap checker and step 5) ──────────────────────

def timecode_to_ms(tc: str) -> int:
    """Reverse of ms_to_timecode: '00h01m23s456' → milliseconds"""
    m = re.match(r'(\d+)h(\d+)m(\d+)s(\d+)', tc)
    if not m:
        raise ValueError(f"Cannot parse timecode: {tc!r}")
    return (int(m.group(1)) * 3_600_000 + int(m.group(2)) * 60_000
            + int(m.group(3)) * 1_000   + int(m.group(4)))


def wav_duration_ms(path: Path) -> int:
    with wave.open(str(path), "rb") as wf:
        return int(wf.getnframes() / wf.getframerate() * 1000)


def ms_to_human(ms: int) -> str:
    """1234 → '1.234s'  |  65234 → '1m05.234s'"""
    s_total, ms_part = divmod(ms, 1000)
    m, s = divmod(s_total, 60)
    return f"{m}m{s:02d}.{ms_part:03d}s" if m else f"{s}.{ms_part:03d}s"


def scan_clips(clips_dir: Path) -> list:
    """Read all clip_*.wav files, parse start time from name, return sorted list."""
    clips = []
    for wav in sorted(clips_dir.glob("clip_*.wav")):
        m = re.search(r'clip_(\d+h\d+m\d+s\d+)', wav.stem)
        if not m:
            print(f"  WARN: skipping {wav.name} — cannot parse timecode from name")
            continue
        start_ms = timecode_to_ms(m.group(1))
        try:
            dur_ms = wav_duration_ms(wav)
        except Exception as e:
            print(f"  WARN: cannot read {wav.name}: {e}")
            continue
        clips.append({"file": wav, "start_ms": start_ms,
                      "end_ms": start_ms + dur_ms, "dur_ms": dur_ms})
    clips.sort(key=lambda c: c["start_ms"])
    return clips


def find_clusters(clips: list) -> list:
    """
    Group clips into overlap clusters.
    A cluster is a list of consecutive indices into `clips` that form a chain
    of overlaps (A→B, B→C, ...).  Only groups with 2+ clips are returned.
    """
    clusters = []
    i = 0
    while i < len(clips) - 1:
        if clips[i]["end_ms"] > clips[i + 1]["start_ms"]:
            cluster = [i]
            j = i
            while j + 1 < len(clips) and clips[j]["end_ms"] > clips[j + 1]["start_ms"]:
                cluster.append(j + 1)
                j += 1
            clusters.append(cluster)
            i = j + 1
        else:
            i += 1
    return clusters


def propose_resolution(cluster_indices: list, all_clips: list):
    """
    Try to build an automatic rename plan for one conflict cluster.

    2-clip cluster:
      1. Push B later by overlap  — if B's new end doesn't hit C
      2. Pull A earlier by overlap — if A's new start doesn't hit Z (or go < 0)
    3-clip cluster:
      Pull A earlier by overlap_AB  AND  push C later by overlap_BC
      (both must be feasible simultaneously)
    4+ clips: return None (manual)

    Returns list of (old_path, new_path, label) or None.
    """
    n   = len(cluster_indices)
    dir = all_clips[0]["file"].parent

    def new_path(ms):
        return dir / f"clip_{ms_to_timecode(ms)}.wav"

    if n == 2:
        i, j   = cluster_indices
        A, B   = all_clips[i], all_clips[j]
        ov     = A["end_ms"] - B["start_ms"]

        # Option 1 — push B later
        B_new_start = B["start_ms"] + ov
        B_new_end   = B["end_ms"]   + ov
        can_push_B  = (j + 1 >= len(all_clips)) or (B_new_end <= all_clips[j + 1]["start_ms"])

        if can_push_B:
            return [(B["file"], new_path(B_new_start),
                     f"Push  {B['file'].name}  +{ms_to_human(ov)}\n"
                     f"   →  clip_{ms_to_timecode(B_new_start)}.wav")]

        # Option 2 — pull A earlier
        A_new_start = A["start_ms"] - ov
        can_pull_A  = (A_new_start >= 0 and
                       (i == 0 or all_clips[i - 1]["end_ms"] <= A_new_start))

        if can_pull_A:
            return [(A["file"], new_path(A_new_start),
                     f"Pull  {A['file'].name}  -{ms_to_human(ov)}\n"
                     f"   →  clip_{ms_to_timecode(A_new_start)}.wav")]

        return None

    elif n == 3:
        i, j, k    = cluster_indices
        A, B, C    = all_clips[i], all_clips[j], all_clips[k]
        ov_AB      = A["end_ms"] - B["start_ms"]
        ov_BC      = B["end_ms"] - C["start_ms"]

        A_new_start = A["start_ms"] - ov_AB
        C_new_start = C["start_ms"] + ov_BC
        C_new_end   = C["end_ms"]   + ov_BC

        can_pull_A = (A_new_start >= 0 and
                      (i == 0 or all_clips[i - 1]["end_ms"] <= A_new_start))
        can_push_C = ((k + 1 >= len(all_clips)) or
                      C_new_end <= all_clips[k + 1]["start_ms"])

        if can_pull_A and can_push_C:
            return [
                (A["file"], new_path(A_new_start),
                 f"Pull  {A['file'].name}  -{ms_to_human(ov_AB)}\n"
                 f"   →  clip_{ms_to_timecode(A_new_start)}.wav"),
                (C["file"], new_path(C_new_start),
                 f"Push  {C['file'].name}  +{ms_to_human(ov_BC)}\n"
                 f"   →  clip_{ms_to_timecode(C_new_start)}.wav"),
            ]

        return None

    else:
        return None   # 4+ clips: always manual


# ─── Pipeline helpers ─────────────────────────────────────────────────────────

def run(cmd: list, label: str = "") -> subprocess.CompletedProcess:
    tag = label or Path(str(cmd[0])).name
    preview = " ".join(str(a) for a in cmd[1:6])
    print(f"    [{tag}] {preview} ...")
    result = subprocess.run([str(c) for c in cmd])
    if result.returncode != 0:
        raise RuntimeError(
            f"Command failed (exit {result.returncode}):\n  {' '.join(str(c) for c in cmd)}"
        )
    return result


def srt_time_to_ms(t: str) -> int:
    h, m, rest = t.strip().split(":")
    s, ms = rest.split(",")
    return int(h) * 3_600_000 + int(m) * 60_000 + int(s) * 1_000 + int(ms)


def parse_srt(path: Path) -> list:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        text = path.read_text(encoding="latin-1")
    pattern = re.compile(
        r"(\d+)\s*\r?\n"
        r"(\d{2}:\d{2}:\d{2},\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2},\d{3})\s*\r?\n"
        r"([\s\S]*?)(?=\r?\n\s*\r?\n|\Z)"
    )
    subs = []
    for m in pattern.finditer(text):
        raw = m.group(4).strip().replace("\r\n", " ").replace("\n", " ")
        if raw:
            subs.append({
                "index":    int(m.group(1)),
                "start_ms": srt_time_to_ms(m.group(2)),
                "end_ms":   srt_time_to_ms(m.group(3)),
                "text":     raw,
            })
    return subs


def load_work_meta(work: Path) -> dict:
    f = work / "work_meta.json"
    return json.loads(f.read_text(encoding="utf-8")) if f.exists() else {}


def save_work_meta(work: Path, data: dict):
    f = work / "work_meta.json"
    existing = load_work_meta(work)
    existing.update(data)
    f.write_text(json.dumps(existing, indent=2, ensure_ascii=False), encoding="utf-8")


# ─── Pipeline steps ───────────────────────────────────────────────────────────

def step1_extract(video: Path, work: Path):
    print("\n[STEP 1/7] Extracting audio...")
    wav_16k = work / "step1_audio_16k.wav"
    wav_44k = work / "step1_audio_44k.wav"

    run([FFMPEG, "-y", "-i", video,
         "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav_16k],
        label="ffmpeg 16kHz")
    print(f"  OK  {wav_16k.name}  ({wav_16k.stat().st_size // 1024} KB)")

    run([FFMPEG, "-y", "-i", video,
         "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", wav_44k],
        label="ffmpeg 44kHz")
    print(f"  OK  {wav_44k.name}  ({wav_44k.stat().st_size // 1024} KB)")

    save_work_meta(work, {"video": str(video)})


def step2_transcribe(work: Path, model: str, lang_src: str):
    print("\n[STEP 2/7] Transcribing with Whisper...")
    wav      = work / "step1_audio_16k.wav"
    prefix   = work / "step2_transcript"
    srt_orig = work / "step2_transcript.srt"
    srt_edit = work / "step2_translated.srt"

    if not WHISPER.exists():
        raise FileNotFoundError(f"Whisper binary not found: {WHISPER}")

    model_file = WHISPER_DIR / f"ggml-{model}.bin"
    if not model_file.exists():
        available = [f.name for f in WHISPER_DIR.glob("ggml-*.bin")]
        raise FileNotFoundError(f"Model not found: {model_file}\nAvailable: {available}")

    cmd = [WHISPER, "-m", model_file, "-osrt", "-of", prefix, "-f", wav]
    if lang_src and lang_src != "auto":
        cmd += ["-l", lang_src]
    run(cmd, label=f"whisper [{model}]")

    if not srt_orig.exists():
        raise FileNotFoundError(f"Whisper did not produce: {srt_orig}")
    print(f"  OK  {srt_orig.name}")

    if not srt_edit.exists():
        shutil.copy(srt_orig, srt_edit)

    print(f"\n{'='*60}")
    print("  TRANSLATE THE SRT FILE NOW")
    print(f"  {srt_edit}")
    print("  Edit the text, save the file, then come back here.")
    print(f"{'='*60}")
    input("\n  Press ENTER when done translating...\n")


def step3_separate(work: Path):
    print("\n[STEP 3/7] Separating vocals with Demucs (several minutes)...")
    wav        = work / "step1_audio_44k.wav"
    demucs_out = work / "step3_demucs"
    bg_dst     = work / "step3_background.wav"

    demucs_out.mkdir(exist_ok=True)
    run([PYTHON, "-m", "demucs", "-n", "htdemucs", "--two-stems", "vocals",
         "-o", demucs_out, wav],
        label="demucs")

    bg_src = demucs_out / "htdemucs" / wav.stem / "no_vocals.wav"
    if not bg_src.exists():
        found = list(demucs_out.rglob("no_vocals.wav"))
        if not found:
            raise FileNotFoundError(f"no_vocals.wav not found under {demucs_out}")
        bg_src = found[0]

    shutil.copy(bg_src, bg_dst)
    print(f"  OK  {bg_dst.name}  ({bg_dst.stat().st_size // (1024*1024)} MB)")


async def _generate_tts_clips(plans: list, clips_dir: Path):
    """plans: list of dicts with keys: index, text, voice, mp3_name"""
    import edge_tts
    total = len(plans)
    for i, plan in enumerate(plans):
        mp3 = clips_dir / plan["mp3_name"]
        voice_short = plan["voice"].split("-")[2] if plan["voice"].count("-") >= 2 else plan["voice"]
        print(f"  [{i+1:3d}/{total}] [{voice_short}] {plan['text'][:55]}")
        communicate = edge_tts.Communicate(plan["text"], plan["voice"])
        await communicate.save(str(mp3))
        size = mp3.stat().st_size // 1024 if mp3.exists() else 0
        print(f"    → {mp3.name}  ({size} KB)")


def step4_tts(work: Path, lang_tts: str, gender: str):
    print("\n[STEP 4/7] Generating TTS clips (one WAV per subtitle)...")

    srt_file = work / "step2_translated.srt"
    if not srt_file.exists():
        raise FileNotFoundError(f"Translated SRT not found: {srt_file}")

    subs = parse_srt(srt_file)
    if not subs:
        raise ValueError(f"No subtitles parsed from {srt_file}")

    lang_key = lang_tts if lang_tts in VOICES else lang_tts.split("-")[0]
    if lang_key not in VOICES:
        raise ValueError(f"Unknown TTS language: {lang_tts}. Available: {list(VOICES)}")
    voice_map     = VOICES[lang_key]
    default_voice = voice_map[gender]
    print(f"  Default voice : {default_voice}")
    print(f"  Subtitles     : {len(subs)}")

    clips_dir = work / "step4_tts_clips"
    clips_dir.mkdir(exist_ok=True)

    # ── Plan all clips (filter + resolve per-line voice) ──────────────────
    plans   = []
    skipped = []
    for sub in subs:
        clean_text, voice_override = parse_subtitle(sub["text"], voice_map)

        if clean_text is None:
            print(f"  SKIP [{sub['index']:3d}] (bracketed/empty): {sub['text']}")
            skipped.append(sub["index"])
            continue

        tc   = ms_to_timecode(sub["start_ms"])
        name = f"clip_{tc}"            # e.g. clip_00h01m23s456
        voice = voice_override or default_voice

        plans.append({
            "index":    sub["index"],
            "start_ms": sub["start_ms"],
            "end_ms":   sub["end_ms"],
            "text":     clean_text,
            "voice":    voice,
            "mp3_name": f"{name}.mp3",
            "wav_name": f"{name}.wav",
        })

    print(f"\n  {len(plans)} clips to generate, {len(skipped)} skipped")
    if not plans:
        raise RuntimeError("No clips to generate after filtering.")

    # ── Generate MP3s ──────────────────────────────────────────────────────
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

    print("\n  Generating MP3 clips via edge-tts...")
    asyncio.run(_generate_tts_clips(plans, clips_dir))

    # ── Convert MP3 → WAV ─────────────────────────────────────────────────
    print("\n  Converting MP3 → WAV (24kHz mono)...")
    metadata = []
    for plan in plans:
        mp3 = clips_dir / plan["mp3_name"]
        wav = clips_dir / plan["wav_name"]

        if not mp3.exists():
            print(f"  WARN: MP3 missing for clip {plan['index']}")
            continue

        run([FFMPEG, "-y", "-i", mp3,
             "-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", wav],
            label=f"convert {wav.stem}")

        if not wav.exists():
            print(f"  WARN: WAV conversion failed for clip {plan['index']}")
            continue

        metadata.append({
            "index":    plan["index"],
            "start_ms": plan["start_ms"],
            "end_ms":   plan["end_ms"],
            "text":     plan["text"],
            "voice":    plan["voice"],
            "mp3":      str(mp3),
            "wav":      str(wav),
        })
        print(f"    {wav.name}  ({plan['start_ms']/1000:.2f}s → {plan['end_ms']/1000:.2f}s)  [{plan['voice'].split('-')[2] if plan['voice'].count('-') >= 2 else plan['voice']}]")

    if not metadata:
        raise RuntimeError("No TTS clips generated. Check edge-tts and internet connection.")

    meta_file = work / "step4_tts_metadata.json"
    meta_file.write_text(json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\n  {len(metadata)}/{len(subs)} clips ready in {clips_dir.name}/")
    if skipped:
        print(f"  Skipped subtitle indices: {skipped}")


def step5_merge_tts(work: Path):
    """Place each TTS clip at its filename-encoded timestamp using numpy.
    Reads timing from filenames (not metadata) so manual renames are respected."""
    import numpy as np

    print("\n[STEP 5/7] Merging TTS clips with timing from filenames (numpy)...")

    clips_dir = work / "step4_tts_clips"
    if not clips_dir.exists():
        raise FileNotFoundError(f"Clips directory not found: {clips_dir} — run step 4 first.")

    clips = scan_clips(clips_dir)
    if not clips:
        raise ValueError(f"No clip_*.wav files found in {clips_dir}")

    with wave.open(str(clips[0]["file"]), "rb") as wf:
        sample_rate = wf.getframerate()
        n_channels  = wf.getnchannels()
        sampwidth   = wf.getsampwidth()

    total_ms     = max(c["end_ms"] for c in clips) + 2000
    total_frames = int(total_ms / 1000 * sample_rate)

    print(f"  Sample rate : {sample_rate} Hz")
    print(f"  Channels    : {n_channels}")
    print(f"  Duration    : {total_ms/1000:.1f}s  ({len(clips)} clips)")

    buf = np.zeros((total_frames, n_channels), dtype=np.float32)

    for clip in clips:
        wav_path = clip["file"]

        with wave.open(str(wav_path), "rb") as wf:
            raw     = wf.readframes(wf.getnframes())
            clip_ch = wf.getnchannels()
            clip_sw = wf.getsampwidth()
            clip_sr = wf.getframerate()

        dtype   = {1: np.int8, 2: np.int16, 4: np.int32}[clip_sw]
        samples = np.frombuffer(raw, dtype=dtype).astype(np.float32)
        samples = samples.reshape(-1, clip_ch)

        if clip_ch == 1 and n_channels == 2:
            samples = np.hstack([samples, samples])

        if clip_sr != sample_rate:
            try:
                from scipy.signal import resample as scipy_resample
                samples = scipy_resample(samples, int(len(samples) * sample_rate / clip_sr))
            except ImportError:
                print(f"  WARN: scipy missing, skipping resample for {wav_path.name}")

        start_f = int(clip["start_ms"] / 1000 * sample_rate)
        end_f   = start_f + len(samples)

        if end_f > len(buf):
            buf = np.vstack([buf, np.zeros((end_f - len(buf), n_channels), dtype=np.float32)])

        buf[start_f:end_f] += samples
        print(f"  Placed {wav_path.name}: {clip['start_ms']/1000:.2f}s → {end_f/sample_rate:.2f}s")

    peak = float(np.max(np.abs(buf)))
    if peak > 32767:
        print(f"  Normalizing (peak={peak:.0f})")
        buf *= 32767.0 / peak

    out_wav  = work / "step5_tts_merged.wav"
    out_data = buf.clip(-32768, 32767).astype(np.int16)
    with wave.open(str(out_wav), "wb") as wf:
        wf.setnchannels(n_channels)
        wf.setsampwidth(sampwidth)
        wf.setframerate(sample_rate)
        wf.writeframes(out_data.tobytes())

    print(f"  OK  {out_wav.name}  ({out_wav.stat().st_size // (1024*1024)} MB)")


def step6_mix(work: Path, bg_vol: float = 0.7, tts_vol: float = 1.3):
    print("\n[STEP 6/7] Mixing background + TTS...")
    bg    = work / "step3_background.wav"
    tts   = work / "step5_tts_merged.wav"
    mixed = work / "step6_mixed.wav"

    for f in (bg, tts):
        if not f.exists():
            raise FileNotFoundError(f"Required file missing: {f}")

    print(f"  Background : {bg.name}   vol={bg_vol}")
    print(f"  TTS        : {tts.name}  vol={tts_vol}")

    # normalize=0 keeps full amplitude — no per-input division
    run([FFMPEG, "-y",
         "-i", bg, "-i", tts,
         "-filter_complex",
         f"[0:a]volume={bg_vol}[bg];[1:a]volume={tts_vol}[tts];"
         "[bg][tts]amix=inputs=2:duration=first:normalize=0[out]",
         "-map", "[out]",
         "-c:a", "pcm_s16le",
         mixed],
        label="ffmpeg mix")
    print(f"  OK  {mixed.name}  ({mixed.stat().st_size // (1024*1024)} MB)")


def step7_assemble(video: Path, work: Path, output_dir: Path) -> Path:
    print("\n[STEP 7/7] Assembling final video (no subtitle burn)...")
    mixed = work / "step6_mixed.wav"
    out   = output_dir / f"{video.stem}_translated.mp4"

    if not mixed.exists():
        raise FileNotFoundError(f"Mixed audio not found: {mixed}")

    run([FFMPEG, "-y",
         "-i", video, "-i", mixed,
         "-c:v", "copy",
         "-map", "0:v",
         "-map", "1:a",
         "-c:a", "aac", "-b:a", "192k",
         out],
        label="ffmpeg assemble")
    print(f"  OK  {out}")
    return out


def run_steps(video, work, start_step, end_step, output_dir,
              model, lang_src, lang_tts, gender, bg_vol, tts_vol):
    for step in range(start_step, end_step + 1):
        if   step == 1: step1_extract(video, work)
        elif step == 2: step2_transcribe(work, model, lang_src)
        elif step == 3: step3_separate(work)
        elif step == 4: step4_tts(work, lang_tts, gender)
        elif step == 5: step5_merge_tts(work)
        elif step == 6: step6_mix(work, bg_vol, tts_vol)
        elif step == 7:
            if video is None:
                meta = load_work_meta(work)
                if "video" in meta:
                    video = Path(meta["video"])
                else:
                    vids = [f for ext in ("*.mp4","*.mkv","*.avi","*.mov","*.webm")
                            for f in work.glob(ext)]
                    if not vids:
                        raise FileNotFoundError(
                            "No video found. Pass the original video path.")
                    video = vids[0]
            out = step7_assemble(video, work, output_dir)
            print(f"\n{'='*60}")
            print("  DONE!")
            print(f"  Output : {out}")
            print(f"  Work   : {work}")
            print(f"{'='*60}\n")


# ─── Interactive mode ─────────────────────────────────────────────────────────

def pick(prompt: str, options: list, default: int = 0) -> int:
    """Show a numbered menu, return 0-based index of chosen item."""
    print(f"\n{prompt}")
    for i, label in enumerate(options):
        star = "  ← default" if i == default else ""
        print(f"    [{i+1}] {label}{star}")
    while True:
        raw = input(f"  Your choice [{default+1}]: ").strip()
        if not raw:
            return default
        try:
            n = int(raw) - 1
            if 0 <= n < len(options):
                return n
        except ValueError:
            pass
        print(f"  Please enter a number between 1 and {len(options)}.")


def ask_path(prompt: str) -> Path:
    """Ask for a file/folder path, stripping surrounding quotes (drag-and-drop)."""
    while True:
        raw = input(f"\n{prompt}\n  > ").strip().strip('"\'')
        if raw:
            return Path(raw)
        print("  Please enter a path.")


def interactive_overlap_check(clips_dir: Path):
    """Detect overlap clusters, propose auto-fixes, loop until clean or user continues."""
    print(f"\n  Clips folder: {clips_dir}")

    while True:
        clips    = scan_clips(clips_dir)
        clusters = find_clusters(clips)

        if not clusters:
            print(f"  OK  No overlaps — {len(clips)} clips, all clear.")
            break

        n_conflicts = len(clusters)
        print(f"\n  {n_conflicts} conflict(s) found:\n")

        applied_any = False

        for cluster_indices in clusters:
            n      = len(cluster_indices)
            cclips = [clips[idx] for idx in cluster_indices]

            # ── Display the cluster ──────────────────────────────────────
            print(f"  {'─'*52}")
            print(f"  CONFLICT  {n} clips:")
            prev_end = None
            for pos, c in enumerate(cclips):
                ov_str = ""
                if prev_end is not None and prev_end > c["start_ms"]:
                    ov_str = f"  ← {ms_to_human(prev_end - c['start_ms'])} overlap"
                label = "ABCDE"[pos] if pos < 5 else str(pos)
                print(f"    [{label}]  {c['file'].name}")
                print(f"          {ms_to_human(c['start_ms'])} → {ms_to_human(c['end_ms'])}"
                      f"  (dur {ms_to_human(c['dur_ms'])}){ov_str}")
                prev_end = c["end_ms"]

            # ── Try auto-resolution ──────────────────────────────────────
            resolution = propose_resolution(cluster_indices, clips)

            if resolution:
                print(f"\n  Auto-fix:")
                for _, new, label in resolution:
                    for line in label.split("\n"):
                        print(f"    {line}")
                print()
                choice = input("  [A] Apply   [S] Skip (fix manually): ").strip().lower()
                if choice == "a":
                    for old, new, _ in resolution:
                        old.rename(new)
                        print(f"    {old.name}  →  {new.name}")
                    applied_any = True
                    break   # re-scan immediately after any rename
            else:
                if n > 3:
                    reason = f"{n} clips — only 2 and 3-clip conflicts can be auto-fixed"
                else:
                    reason = "auto-fix would create a new conflict with a neighbouring clip"
                print(f"\n  No automatic solution ({reason}).")
                print( "  Fix manually: rename files to shift start times.")
                print(f"  Format: clip_HHhMMmSSsmmm.wav")

            print()

        if applied_any:
            print("  Re-scanning...")
            continue

        # All clusters shown, no pending auto-apply
        print(f"  Folder: {clips_dir}")
        choice = input("  [R] Re-scan   [Enter] Continue anyway: ").strip().lower()
        if choice != "r":
            if clusters:
                print("  Continuing with remaining overlaps — they will mix together.")
            break


def prompt_tts_options() -> tuple:
    """Ask TTS language and gender. Called right before step 4."""
    tts_langs = [
        ("French Canada  — fr-CA", "fr-CA"),
        ("French France  — fr-FR", "fr-FR"),
        ("English US     — en-US", "en-US"),
        ("English UK     — en-GB", "en-GB"),
        ("Spanish        — es",    "es"),
        ("German         — de",    "de"),
        ("Italian        — it",    "it"),
        ("Portuguese     — pt",    "pt"),
    ]
    idx      = pick("TTS language (dubbed voice):",
                    [l for l, _ in tts_langs], default=0)
    lang_tts = tts_langs[idx][1]

    genders = [("Female", "female"), ("Male", "male")]
    idx     = pick("Default voice gender:", [l for l, _ in genders], default=0)
    gender  = genders[idx][1]

    lang_key = lang_tts if lang_tts in VOICES else lang_tts.split("-")[0]
    voice    = VOICES[lang_key][gender]
    print(f"\n  Default voice: {voice}")
    print("  (You can override per-line in the SRT with [HOMME]/[FEMME] or [MAN]/[WOMAN])")

    return lang_tts, gender


def prompt_volumes(work: Path) -> tuple:
    """Ask background and TTS volumes. Called right before step 6."""
    meta        = load_work_meta(work)
    bg_default  = meta.get("bg_vol",  0.7)
    tts_default = meta.get("tts_vol", 1.3)
    print("\n  Audio volumes — press Enter to keep the value shown in brackets:")
    raw    = input(f"    Background volume [{bg_default}]: ").strip()
    bg_vol = float(raw) if raw else bg_default
    raw    = input(f"    TTS voice volume  [{tts_default}]: ").strip()
    tts_vol = float(raw) if raw else tts_default
    return bg_vol, tts_vol


def interactive_mode():
    print()
    print("=" * 60)
    print("  Video Translator")
    print("=" * 60)

    if not FFMPEG.exists():
        print(f"\n  ERROR: FFmpeg not found at {FFMPEG}")
        print("  Run INSTALLER.bat first.")
        return

    output_dir = SCRIPT_DIR / "output"
    output_dir.mkdir(exist_ok=True)

    # ── New session or resume? ─────────────────────────────────────────────
    mode_choice = pick(
        "What do you want to do?",
        [
            "Translate a new video  (full pipeline, steps 1-7)",
            "Resume / re-run a step from a previous session",
        ],
        default=0,
    )

    # ── RESUME ────────────────────────────────────────────────────────────
    if mode_choice == 1:
        temp_base = SCRIPT_DIR / "TEMP"
        sessions  = sorted(temp_base.glob("translate_*"), reverse=True)[:15] if temp_base.exists() else []

        if sessions:
            labels = [s.name for s in sessions] + ["Type the path manually"]
            idx = pick("Which session?", labels, default=0)
            work = sessions[idx] if idx < len(sessions) else ask_path("Path to work directory:")
        else:
            work = ask_path("Path to work directory (no sessions found in TEMP/):")

        if not work.exists():
            print(f"\n  ERROR: Directory not found: {work}")
            return

        step_labels = [
            "1 — Extract audio",
            "2 — Transcribe with Whisper",
            "3 — Separate vocals (Demucs)",
            "4 — Generate TTS clips",
            "5 — Merge TTS clips",
            "6 — Mix background + TTS",
            "7 — Assemble final video",
        ]
        from_idx   = pick("Start from which step?", step_labels, default=3)
        start_step = from_idx + 1

        only_idx = pick(
            "Run up to which step?",
            step_labels[from_idx:] + ["Run ALL remaining steps"],
            default=len(step_labels) - from_idx,
        )
        end_step = (start_step + only_idx) if only_idx < len(step_labels) - from_idx else 7

        meta     = load_work_meta(work)
        video    = Path(meta["video"]) if "video" in meta else None
        lang_src = meta.get("lang_src", "auto")
        model    = meta.get("model", "base")

    # ── NEW SESSION ───────────────────────────────────────────────────────
    else:
        print("\n  Drag your video file onto this window, or type the path:")
        raw_path = input("  > ").strip().strip('"\'')
        video = Path(raw_path)
        if not video.exists():
            print(f"\n  ERROR: File not found: {video}")
            return

        src_langs = [
            ("Auto-detect",  "auto"),
            ("French",       "fr"),
            ("English",      "en"),
            ("Spanish",      "es"),
            ("German",       "de"),
            ("Italian",      "it"),
            ("Portuguese",   "pt"),
        ]
        idx      = pick("Source language (audio in the video):",
                        [l for l, _ in src_langs], default=0)
        lang_src = src_langs[idx][1]

        models = [
            ("tiny      — fastest, less accurate",       "tiny"),
            ("base      — good balance  (recommended)",  "base"),
            ("small     — better accuracy",              "small"),
            ("medium    — very accurate, slower",        "medium"),
            ("large-v3  — best accuracy, slow",          "large-v3"),
        ]
        idx   = pick("Whisper model:", [l for l, _ in models], default=1)
        model = models[idx][1]

        start_step = 1
        end_step   = 7

        ts   = datetime.now().strftime("%Y%m%d_%H%M%S")
        work = SCRIPT_DIR / "TEMP" / f"translate_{ts}"
        work.mkdir(parents=True, exist_ok=True)
        save_work_meta(work, {"video": str(video), "lang_src": lang_src, "model": model})

    # ── Summary & confirm ─────────────────────────────────────────────────
    print()
    print("=" * 60)
    if mode_choice == 0:
        print(f"  Video    : {video}")
    print(f"  Work dir : {work}")
    print(f"  Steps    : {start_step} → {end_step}")
    if mode_choice == 0:
        print(f"  Model    : {model}  |  lang-src: {lang_src}")
    if start_step <= 4 <= end_step:
        print("  Voice    : will be asked before step 4")
    if start_step <= 6 <= end_step:
        print("  Volumes  : will be asked before step 6")
    print("=" * 60)
    go = input("\n  Start? [Y/n]: ").strip().lower()
    if go in ("n", "no"):
        print("  Cancelled.")
        return

    # ── Run steps, prompting for settings right before they are needed ────
    print()
    lang_tts = bg_vol = tts_vol = gender = None   # resolved just-in-time below

    for step in range(start_step, end_step + 1):

        if step == 4:
            print(f"\n{'─'*60}")
            print("  Step 4 needs a voice — choose now:")
            lang_tts, gender = prompt_tts_options()
            save_work_meta(work, {"lang_tts": lang_tts, "gender": gender})
            print(f"{'─'*60}")

        if step == 5:
            print(f"\n{'─'*60}")
            print("  Checking for overlapping clips before merge...")
            interactive_overlap_check(work / "step4_tts_clips")
            print(f"{'─'*60}")

        if step == 6:
            print(f"\n{'─'*60}")
            print("  Step 6 needs audio volumes — choose now:")
            bg_vol, tts_vol = prompt_volumes(work)
            save_work_meta(work, {"bg_vol": bg_vol, "tts_vol": tts_vol})
            print(f"{'─'*60}")

        if   step == 1: step1_extract(video, work)
        elif step == 2: step2_transcribe(work, model, lang_src)
        elif step == 3: step3_separate(work)
        elif step == 4: step4_tts(work, lang_tts, gender)
        elif step == 5: step5_merge_tts(work)
        elif step == 6: step6_mix(work, bg_vol, tts_vol)
        elif step == 7:
            if video is None:
                meta = load_work_meta(work)
                if "video" in meta:
                    video = Path(meta["video"])
                else:
                    vids = [f for ext in ("*.mp4","*.mkv","*.avi","*.mov","*.webm")
                            for f in work.glob(ext)]
                    if not vids:
                        raise FileNotFoundError("No video found. Pass the original video path.")
                    video = vids[0]
            out = step7_assemble(video, work, output_dir)
            print(f"\n{'='*60}")
            print("  DONE!")
            print(f"  Output : {out}")
            print(f"  Work   : {work}")
            print(f"{'='*60}\n")


# ─── CLI (debug) mode via argparse ────────────────────────────────────────────

def cli_mode():
    parser = argparse.ArgumentParser(
        description="Video Translator CLI (debug/scripted mode)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="\n".join([
            "",
            "TTS languages: " + ", ".join(VOICES.keys()),
            "",
            "Examples:",
            "  python translate_cli.py video.mp4 --lang-tts fr-CA",
            "  python translate_cli.py video.mp4 --lang-src en --lang-tts fr-FR --model small",
            "  python translate_cli.py --work-dir TEMP\\translate_xxx --from-step 4",
            "  python translate_cli.py video.mp4 --only-step 4 --work-dir TEMP\\translate_xxx",
            "  python translate_cli.py video.mp4 --only-step 6 --bg-vol 0.5 --tts-vol 1.8 --work-dir TEMP\\xxx",
        ]),
    )
    parser.add_argument("video",       nargs="?",   help="Input video file")
    parser.add_argument("--lang-src",  default="auto",   help="Source language (default: auto)")
    parser.add_argument("--lang-tts",  default="fr-CA",  help="TTS language (default: fr-CA)")
    parser.add_argument("--gender",    choices=["female","male"], default="female")
    parser.add_argument("--model",     default="base",   help="Whisper model: tiny/base/small/medium/large-v3")
    parser.add_argument("--work-dir",  help="Reuse existing work directory")
    parser.add_argument("--from-step", type=int, default=1,  help="Start from step N")
    parser.add_argument("--only-step", type=int,             help="Run only step N")
    parser.add_argument("--bg-vol",    type=float, default=0.7)
    parser.add_argument("--tts-vol",   type=float, default=1.3)
    args = parser.parse_args()

    start_step = args.only_step or args.from_step
    end_step   = args.only_step or 7

    if start_step == 1 and not args.video:
        parser.error("Provide a video file when starting from step 1.")
    if args.video and not Path(args.video).exists():
        parser.error(f"Video not found: {args.video}")
    if not FFMPEG.exists():
        parser.error(f"FFmpeg not found: {FFMPEG}\nRun INSTALLER.bat first.")

    if args.work_dir:
        work = Path(args.work_dir).resolve()
        if not work.exists():
            parser.error(f"Work directory not found: {work}")
    else:
        ts   = datetime.now().strftime("%Y%m%d_%H%M%S")
        work = SCRIPT_DIR / "TEMP" / f"translate_{ts}"
        work.mkdir(parents=True, exist_ok=True)

    video = Path(args.video).resolve() if args.video else None

    output_dir = SCRIPT_DIR / "output"
    output_dir.mkdir(exist_ok=True)

    print(f"\n{'='*60}")
    print("  Video Translator CLI  [debug mode]")
    print(f"{'='*60}")
    if video:
        print(f"  Video    : {video}")
    print(f"  Work dir : {work}")
    print(f"  TTS      : {args.lang_tts} / {args.gender}")
    print(f"  Model    : {args.model}  |  lang-src: {args.lang_src}")
    print(f"  Volumes  : bg={args.bg_vol}  tts={args.tts_vol}")
    print(f"  Steps    : {start_step} → {end_step}")
    print()

    run_steps(
        video=video, work=work,
        start_step=start_step, end_step=end_step,
        output_dir=output_dir,
        model=args.model, lang_src=args.lang_src,
        lang_tts=args.lang_tts, gender=args.gender,
        bg_vol=args.bg_vol, tts_vol=args.tts_vol,
    )


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    has_flags = any(a.startswith("-") for a in sys.argv[1:])
    if has_flags:
        cli_mode()
    else:
        interactive_mode()


if __name__ == "__main__":
    main()
