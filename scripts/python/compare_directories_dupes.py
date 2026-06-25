#!/usr/bin/env python3
"""
compare_directories_dupes.py

Compare POSSIBLE dupes against SOURCE (keepers) using tags + filename fallback.
Quarantine likely dupes into POSSIBLE/_LikelyDupes/... while preserving potential upgrades.

Install:
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install -U pip mutagen

Dry run (recommended first):
  python compare_directories_dupes.py "/path/to/SOURCE" "/path/to/POSSIBLE"

Apply (copy likely dupes into quarantine):
  python compare_directories_dupes.py "/path/to/SOURCE" "/path/to/POSSIBLE" --apply

Move instead of copy:
  python compare_directories_dupes.py "/path/to/SOURCE" "/path/to/POSSIBLE" --apply --move

Tuning:
  --threshold 90     (default 90) cutoff for LIKELY match
  --min-report 60    (default 60) include matches >= this in report even if not moved
  --dur-tol 2.0      duration tolerance seconds (default 2.0)
  --ignore-mix-notes ignore trailing (...) or [...] notes in titles for matching

Quality decision:
- If match is LIKELY, we compare SOURCE vs POSSIBLE:
    * Lossless > lossy
    * Higher bitrate > lower bitrate (if known)
    * Higher sample rate > lower sample rate (if known)
    * Longer duration > shorter duration (if close-ish; see --dur-prefer-within)
    * Larger file size > smaller size (tie-break)
- If POSSIBLE is better -> UPGRADE_CANDIDATE (not moved)
- If POSSIBLE is worse/equal -> QUARANTINE (moved/copied)

Outputs:
- CSV report (default: compare_dirs_report.csv in CWD)
- Quarantine folder: <POSSIBLE>/_LikelyDupes/<Artist>/<Title>/
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

from mutagen import File as MutagenFile
from mutagen.flac import FLAC
from mutagen.mp4 import MP4
from mutagen.easyid3 import EasyID3


AUDIO_EXTS = {".flac", ".mp3", ".m4a", ".mp4"}

WS = re.compile(r"\s+")
BAD_FS_CHARS = re.compile(r'[\/:*?"<>|]+')
BRACKET_TAIL = re.compile(r"\s*[\[\(].*?[\]\)]\s*$")

YEAR_ARTIST_PAT = re.compile(r"^\s*(\d{4})\s*-\s*(.+?)\s*-\s*(.+)\s*$")
ARTIST_DASH_PAT = re.compile(r"^\s*(.+?)\s*-\s*(.+)\s*$")
LEADING_TRACKNUM_PAT = re.compile(r"^\s*(?:[A-D]\s*\.)?\s*\d{1,3}\s*([.\-)\]]|\s+)\s*")


@dataclass
class Meta:
    path: str
    ext: str
    artist: str
    title: str
    album: str
    tracknumber: str
    duration: Optional[float]
    bitrate: Optional[int]       # bits/sec
    sample_rate: Optional[int]   # Hz
    size: int                    # bytes


def norm(s: str) -> str:
    s = (s or "").strip().replace("\u00A0", " ")
    return WS.sub(" ", s)


def norm_key(s: str) -> str:
    s = norm(s).casefold()
    s = s.replace("&", "and")
    s = re.sub(r"[’']", "", s)
    s = re.sub(r"[^a-z0-9]+", "", s)
    return s


def safe_name(s: str, fallback: str) -> str:
    s = norm(s)
    s = BAD_FS_CHARS.sub("-", s)
    s = s.strip(" .")
    return s if s else fallback


def title_for_match(title: str, ignore_mix_notes: bool) -> str:
    t = norm(title)
    if ignore_mix_notes:
        t = BRACKET_TAIL.sub("", t).strip()
    return t


def infer_artist_title_from_filename(filename: str) -> Tuple[str, str]:
    base = os.path.splitext(os.path.basename(filename))[0]
    base = base.replace("–", "-").replace("—", "-")
    base = LEADING_TRACKNUM_PAT.sub("", base).strip()

    m = YEAR_ARTIST_PAT.match(base)
    if m:
        return norm(m.group(2)), norm(m.group(3))

    m = ARTIST_DASH_PAT.match(base)
    if m:
        left = m.group(1).strip()
        if re.fullmatch(r"\d{4}", left):
            return "", ""
        return norm(left), norm(m.group(2))

    return "", ""


def read_meta(path: str, ignore_mix_notes: bool) -> Optional[Meta]:
    ext = os.path.splitext(path)[1].lower()
    if ext not in AUDIO_EXTS:
        return None

    audio = MutagenFile(path)
    if audio is None:
        return None

    artist = ""
    title = ""
    album = ""
    tracknumber = ""
    duration = None
    bitrate = None
    sample_rate = None

    try:
        if audio.info:
            duration = getattr(audio.info, "length", None)
            bitrate = getattr(audio.info, "bitrate", None)
            sample_rate = getattr(audio.info, "sample_rate", None)
    except Exception:
        pass

    try:
        if isinstance(audio, FLAC):
            tags = audio.tags or {}
            artist = (tags.get("artist") or tags.get("ARTIST") or tags.get("albumartist") or tags.get("ALBUMARTIST") or [""])[0]
            title = (tags.get("title") or tags.get("TITLE") or [""])[0]
            album = (tags.get("album") or tags.get("ALBUM") or [""])[0]
            tracknumber = (tags.get("tracknumber") or tags.get("TRACKNUMBER") or [""])[0]
        elif isinstance(audio, MP4):
            tags = audio.tags or {}
            artist = (tags.get("\xa9ART") or tags.get("aART") or [""])[0]
            title = (tags.get("\xa9nam") or [""])[0]
            album = (tags.get("\xa9alb") or [""])[0]
            if "trkn" in tags and tags["trkn"]:
                t0 = tags["trkn"][0]
                if isinstance(t0, (tuple, list)) and len(t0) >= 1 and t0[0]:
                    tracknumber = str(int(t0[0]))
        else:
            if ext == ".mp3":
                try:
                    eid3 = EasyID3(path)
                    artist = (eid3.get("artist") or eid3.get("albumartist") or [""])[0]
                    title = (eid3.get("title") or [""])[0]
                    album = (eid3.get("album") or [""])[0]
                    tracknumber = (eid3.get("tracknumber") or [""])[0]
                except Exception:
                    pass
    except Exception:
        pass

    artist = norm(str(artist))
    title = norm(str(title))
    album = norm(str(album))
    tracknumber = norm(str(tracknumber))

    # Filename fallback if tags are missing
    if not artist or not title:
        fa, ft = infer_artist_title_from_filename(path)
        artist = artist or fa
        title = title or ft

    if not title:
        return None

    title = title_for_match(title, ignore_mix_notes)

    return Meta(
        path=path,
        ext=ext,
        artist=artist or "_Unknown",
        title=title,
        album=album,
        tracknumber=tracknumber,
        duration=float(duration) if duration is not None else None,
        bitrate=int(bitrate) if bitrate is not None else None,
        sample_rate=int(sample_rate) if sample_rate is not None else None,
        size=os.path.getsize(path),
    )


def iter_audio_files(root: str, skip_root: Optional[str] = None) -> List[str]:
    out: List[str] = []
    root = os.path.abspath(root)
    skip_root_abs = os.path.abspath(skip_root) if skip_root else None

    for base, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]

        if skip_root_abs and os.path.commonpath([os.path.abspath(base), skip_root_abs]) == skip_root_abs:
            dirnames[:] = []
            continue

        for fn in filenames:
            if os.path.splitext(fn)[1].lower() in AUDIO_EXTS:
                out.append(os.path.join(base, fn))
    return sorted(out)


def durations_close(a: Optional[float], b: Optional[float], tol: float) -> bool:
    if a is None or b is None:
        return True
    return abs(a - b) <= tol


def score_match(src: Meta, d: Meta, dur_tol: float) -> Tuple[int, List[str]]:
    reasons: List[str] = []
    score = 0

    if norm_key(src.title) and norm_key(src.title) == norm_key(d.title):
        score += 45; reasons.append("title")
    if norm_key(src.artist) and norm_key(src.artist) == norm_key(d.artist):
        score += 30; reasons.append("artist")

    if src.album and d.album and norm_key(src.album) == norm_key(d.album):
        score += 10; reasons.append("album")

    if src.duration is not None and d.duration is not None:
        if durations_close(src.duration, d.duration, dur_tol):
            score += 10; reasons.append("duration")
        elif durations_close(src.duration, d.duration, dur_tol * 2):
            score += 5; reasons.append("duration_loose")

    return min(score, 100), reasons


def is_lossless(ext: str) -> bool:
    return ext == ".flac"


def quality_key(m: Meta) -> Tuple[int, int, int, int, int]:
    """
    Higher is better.
    lossless, bitrate, sample_rate, duration_ms, size
    """
    loss = 1 if is_lossless(m.ext) else 0
    br = m.bitrate or 0
    sr = m.sample_rate or 0
    dur = int((m.duration or 0.0) * 1000)
    sz = m.size
    return (loss, br, sr, dur, sz)


def decide_quarantine_or_upgrade(src: Meta, dm: Meta, dur_prefer_within: float) -> str:
    """
    Decide:
      - QUARANTINE: possible is worse/equal than source
      - UPGRADE_CANDIDATE: possible is better than source
    Duration preference only applies when durations are within dur_prefer_within seconds;
    beyond that, treat as different 'version' and use quality without duration bias (but still compare).
    """
    # Build comparable keys
    s_key = list(quality_key(src))
    d_key = list(quality_key(dm))

    # If durations differ wildly, ignore duration dimension when comparing
    if src.duration is not None and dm.duration is not None:
        if abs(src.duration - dm.duration) > dur_prefer_within:
            s_key[3] = 0
            d_key[3] = 0

    if tuple(d_key) > tuple(s_key):
        return "UPGRADE_CANDIDATE"
    return "QUARANTINE"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source_dir")
    ap.add_argument("possible_dir")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--move", action="store_true")
    ap.add_argument("--threshold", type=int, default=90)
    ap.add_argument("--min-report", type=int, default=60)
    ap.add_argument("--dur-tol", type=float, default=2.0)
    ap.add_argument("--dur-prefer-within", type=float, default=4.0,
                    help="Prefer longer duration only when within this many seconds (default 4.0).")
    ap.add_argument("--ignore-mix-notes", action="store_true")
    ap.add_argument("--report", default="compare_dirs_report.csv")
    ap.add_argument("--quarantine-name", default="_LikelyDupes")
    args = ap.parse_args()

    src_dir = os.path.abspath(args.source_dir)
    poss_dir = os.path.abspath(args.possible_dir)
    quarantine_root = os.path.join(poss_dir, args.quarantine_name)

    if not os.path.isdir(src_dir):
        raise SystemExit(f"Not a directory: {src_dir}")
    if not os.path.isdir(poss_dir):
        raise SystemExit(f"Not a directory: {poss_dir}")

    os.makedirs(quarantine_root, exist_ok=True)

    print("Indexing source…")
    src_files = iter_audio_files(src_dir)
    src_index: Dict[Tuple[str, str], List[Meta]] = {}
    src_count = 0

    for p in src_files:
        m = read_meta(p, args.ignore_mix_notes)
        if not m or not m.title:
            continue
        src_count += 1
        k = (norm_key(m.artist), norm_key(m.title))
        src_index.setdefault(k, []).append(m)

    print(f"Source indexed: {src_count} tracks")

    print("Scanning possible dupes…")
    poss_files = iter_audio_files(poss_dir, skip_root=quarantine_root)
    poss_metas: List[Meta] = []
    for p in poss_files:
        m = read_meta(p, args.ignore_mix_notes)
        if m and m.title:
            poss_metas.append(m)

    print(f"Possible scanned: {len(poss_metas)} tracks\n")

    rows = []
    would_quarantine = 0
    would_upgrade = 0
    maybe_count = 0
    reported = 0
    actions = 0  # actual moved/copied (only with --apply)

    for dm in poss_metas:
        # candidates by exact key (artist+title)
        candidates = src_index.get((norm_key(dm.artist), norm_key(dm.title)), [])

        # fallback to title-only across source
        if not candidates:
            title_k = norm_key(dm.title)
            for (_ak, tk), lst in src_index.items():
                if tk == title_k:
                    candidates.extend(lst)

        if not candidates:
            continue

        best = None
        best_score = -1
        best_reasons: List[str] = []

        for sm in candidates:
            sc, reasons = score_match(sm, dm, args.dur_tol)
            if sc > best_score:
                best_score = sc
                best = sm
                best_reasons = reasons

        if best is None:
            continue

        if best_score < args.min_report:
            continue

        reported += 1

        classification = "MAYBE"
        decision = ""
        quarantine_dest = ""

        if best_score >= args.threshold:
            decision = decide_quarantine_or_upgrade(best, dm, args.dur_prefer_within)
            classification = decision
            if decision == "QUARANTINE":
                would_quarantine += 1
            else:
                would_upgrade += 1
        else:
            maybe_count += 1

        if classification == "QUARANTINE":
            artist_dir = safe_name(dm.artist, "_UnknownArtist")
            title_dir = safe_name(dm.title, "_UnknownTitle")
            dest_dir = os.path.join(quarantine_root, artist_dir, title_dir)
            os.makedirs(dest_dir, exist_ok=True)
            quarantine_dest = os.path.join(dest_dir, os.path.basename(dm.path))

        rows.append([
            dm.path, dm.artist, dm.title, dm.ext, dm.bitrate or "", dm.sample_rate or "", f"{dm.duration:.2f}" if dm.duration else "", dm.size,
            best.path, best.artist, best.title, best.ext, best.bitrate or "", best.sample_rate or "", f"{best.duration:.2f}" if best.duration else "", best.size,
            best_score, ",".join(best_reasons),
            classification,
            quarantine_dest
        ])

        if classification == "QUARANTINE" and args.apply:
            final_dest = quarantine_dest
            if os.path.exists(final_dest):
                base, ext = os.path.splitext(final_dest)
                n = 2
                while os.path.exists(f"{base} ({n}){ext}"):
                    n += 1
                final_dest = f"{base} ({n}){ext}"
            if args.move:
                shutil.move(dm.path, final_dest)
            else:
                shutil.copy2(dm.path, final_dest)
            actions += 1

    with open(args.report, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "possible_path","possible_artist","possible_title","possible_ext","possible_bitrate","possible_samplerate","possible_duration","possible_size",
            "source_path","source_artist","source_title","source_ext","source_bitrate","source_samplerate","source_duration","source_size",
            "match_score","match_reasons",
            "decision",
            "quarantine_dest"
        ])
        w.writerows(rows)

    print(f"Report: {os.path.abspath(args.report)}")
    print(f"Matches reported (score >= min-report): {reported}")
    print(f"LIKELY matches (score >= threshold): {would_quarantine + would_upgrade}")
    print(f"  QUARANTINE (possible worse/equal): {would_quarantine}")
    print(f"  UPGRADE_CANDIDATE (possible better): {would_upgrade}")
    print(f"MAYBE (below threshold): {maybe_count}")
    print(f"Quarantine folder: {quarantine_root}")
    if args.apply:
        print(f"Actually {'moved' if args.move else 'copied'} to quarantine: {actions}")
    else:
        print(f"Would {'move' if args.move else 'copy'} to quarantine (QUARANTINE only): {would_quarantine}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())