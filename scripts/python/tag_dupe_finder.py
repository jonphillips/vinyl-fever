#!/usr/bin/env python3
"""
tag_dupe_finder.py

Compare music files by metadata tags + duration, and quarantine likely duplicates.

Usage (recommended with venv):
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install -U pip mutagen

Dry run (no file changes):
  python tag_dupe_finder.py "/path/to/source" "/path/to/possible_dupes"

Apply: copy likely dupes into quarantine folder:
  python tag_dupe_finder.py "/path/to/source" "/path/to/possible_dupes" --apply

Apply: move likely dupes into quarantine folder:
  python tag_dupe_finder.py "/path/to/source" "/path/to/possible_dupes" --apply --move

Tune sensitivity:
  --threshold 85   (default 90)
  --dur-tol 2.5    seconds tolerance on duration match (default 2.0)

Outputs:
  - Quarantine folder under possible_dupes: _LikelyDupes/
  - CSV report: dupe_report.csv (by default in current working dir)
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

BAD_FS_CHARS = re.compile(r'[\/:*?"<>|]+')
WS = re.compile(r"\s+")


@dataclass
class TrackMeta:
    path: str
    ext: str
    artist: str
    title: str
    album: str
    tracknumber: str
    duration: Optional[float]  # seconds


def norm(s: str) -> str:
    s = (s or "").strip()
    s = s.replace("\u00A0", " ")  # non-breaking space
    s = WS.sub(" ", s)
    return s


def norm_key(s: str) -> str:
    # Normalize aggressively for matching:
    s = norm(s).casefold()
    s = s.replace("&", "and")
    s = re.sub(r"[’']", "", s)
    s = re.sub(r"[^a-z0-9]+", "", s)
    return s


def safe_dirname(s: str, fallback: str = "_Unknown") -> str:
    s = norm(s)
    s = BAD_FS_CHARS.sub("-", s)
    s = s.strip(" .")
    return s if s else fallback


def parse_tracknum(s: str) -> Optional[int]:
    """
    Parse common tracknumber formats:
      "6", "06", "6/12", "6 of 12"
    """
    s = norm(s)
    if not s:
        return None
    m = re.match(r"^(\d{1,4})", s)
    if m:
        try:
            return int(m.group(1))
        except Exception:
            return None
    return None


def read_tags(path: str) -> Optional[TrackMeta]:
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

    try:
        if audio.info and getattr(audio.info, "length", None):
            duration = float(audio.info.length)
    except Exception:
        duration = None

    try:
        if isinstance(audio, FLAC):
            artist = (audio.get("artist") or audio.get("ARTIST") or audio.get("albumartist") or audio.get("ALBUMARTIST") or [""])[0]
            title = (audio.get("title") or audio.get("TITLE") or [""])[0]
            album = (audio.get("album") or audio.get("ALBUM") or [""])[0]
            tracknumber = (audio.get("tracknumber") or audio.get("TRACKNUMBER") or [""])[0]

        elif isinstance(audio, MP4):
            # MP4 atoms
            tags = audio.tags or {}
            artist = (tags.get("\xa9ART") or tags.get("aART") or [""])[0]
            title = (tags.get("\xa9nam") or [""])[0]
            album = (tags.get("\xa9alb") or [""])[0]
            # trkn is [(track, total)]
            if "trkn" in tags and tags["trkn"]:
                t0 = tags["trkn"][0]
                if isinstance(t0, (tuple, list)) and len(t0) >= 1 and t0[0]:
                    tracknumber = str(int(t0[0]))

        else:
            # MP3 or other formats
            # Try EasyID3 for mp3
            if ext == ".mp3":
                try:
                    eid3 = EasyID3(path)
                    artist = (eid3.get("artist") or eid3.get("albumartist") or [""])[0]
                    title = (eid3.get("title") or [""])[0]
                    album = (eid3.get("album") or [""])[0]
                    tracknumber = (eid3.get("tracknumber") or [""])[0]
                except Exception:
                    pass

            # Fallback: mutagen easy tags
            if not title:
                tags = getattr(audio, "tags", None) or {}
                artist = (tags.get("artist") or tags.get("albumartist") or [""])[0] if isinstance(tags.get("artist") or tags.get("albumartist"), list) else (tags.get("artist") or tags.get("albumartist") or "")
                title = (tags.get("title") or [""])[0] if isinstance(tags.get("title"), list) else (tags.get("title") or "")
                album = (tags.get("album") or [""])[0] if isinstance(tags.get("album"), list) else (tags.get("album") or "")
                tracknumber = (tags.get("tracknumber") or [""])[0] if isinstance(tags.get("tracknumber"), list) else (tags.get("tracknumber") or "")

    except Exception:
        return None

    artist = norm(str(artist))
    title = norm(str(title))
    album = norm(str(album))
    tracknumber = norm(str(tracknumber))

    if not title and not artist:
        return None

    return TrackMeta(
        path=path,
        ext=ext,
        artist=artist,
        title=title,
        album=album,
        tracknumber=tracknumber,
        duration=duration,
    )


def iter_audio_files(root: str) -> List[str]:
    out: List[str] = []
    for base, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in files:
            if os.path.splitext(fn)[1].lower() in AUDIO_EXTS:
                out.append(os.path.join(base, fn))
    return sorted(out)


def score_match(a: TrackMeta, b: TrackMeta, dur_tol: float) -> Tuple[int, List[str]]:
    """
    Score how likely b is a duplicate of a.
    Returns (score 0..100, reasons).
    """
    reasons: List[str] = []
    score = 0

    # Title is king
    if norm_key(a.title) and norm_key(a.title) == norm_key(b.title):
        score += 45
        reasons.append("title")
    # Artist
    if norm_key(a.artist) and norm_key(a.artist) == norm_key(b.artist):
        score += 30
        reasons.append("artist")
    # Album
    if a.album and b.album and norm_key(a.album) == norm_key(b.album):
        score += 10
        reasons.append("album")
    # Track number (if present and matches)
    ta = parse_tracknum(a.tracknumber)
    tb = parse_tracknum(b.tracknumber)
    if ta is not None and tb is not None and ta == tb:
        score += 5
        reasons.append("tracknum")

    # Duration tolerance
    if a.duration is not None and b.duration is not None:
        if abs(a.duration - b.duration) <= dur_tol:
            score += 10
            reasons.append("duration")
        elif abs(a.duration - b.duration) <= dur_tol * 2:
            score += 5
            reasons.append("duration_loose")

    return min(score, 100), reasons


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source_dir", help="Directory containing your canonical library (keepers).")
    ap.add_argument("possible_dupes_dir", help="Directory containing possible duplicates.")
    ap.add_argument("--apply", action="store_true", help="Actually move/copy files (default: dry run).")
    ap.add_argument("--move", action="store_true", help="Move files instead of copying (requires --apply).")
    ap.add_argument("--threshold", type=int, default=90, help="Score threshold for 'likely dupe' (default: 90).")
    ap.add_argument("--dur-tol", type=float, default=2.0, help="Duration tolerance in seconds (default: 2.0).")
    ap.add_argument("--report", default="dupe_report.csv", help="CSV report filename (default: dupe_report.csv).")
    ap.add_argument("--quarantine-name", default="_LikelyDupes", help="Subfolder name under possible_dupes_dir.")
    args = ap.parse_args()

    src = os.path.abspath(args.source_dir)
    dup = os.path.abspath(args.possible_dupes_dir)

    if not os.path.isdir(src):
        print(f"Not a directory: {src}")
        return 2
    if not os.path.isdir(dup):
        print(f"Not a directory: {dup}")
        return 2

    quarantine_root = os.path.join(dup, args.quarantine_name)

    # Index source tracks by (artist_key, title_key) for fast lookup
    print("Scanning source...")
    source_files = iter_audio_files(src)
    src_metas: List[TrackMeta] = []
    index: Dict[Tuple[str, str], List[TrackMeta]] = {}

    for p in source_files:
        m = read_tags(p)
        if not m or not m.title:
            continue
        src_metas.append(m)
        k = (norm_key(m.artist), norm_key(m.title))
        index.setdefault(k, []).append(m)

    print(f"Source indexed: {len(src_metas)} tracks")

    print("Scanning possible dupes...")
    dupe_files = iter_audio_files(dup)
    dupe_metas: List[TrackMeta] = []
    for p in dupe_files:
        # Don't recurse into quarantine folder if it already exists
        if os.path.commonpath([p, quarantine_root]) == quarantine_root:
            continue
        m = read_tags(p)
        if m and m.title:
            dupe_metas.append(m)

    print(f"Possible-dupes scanned: {len(dupe_metas)} tracks")
    print(f"Mode: {'APPLY' if args.apply else 'DRY RUN'} ({'MOVE' if args.move else 'COPY'})")
    print(f"Threshold: {args.threshold}  |  Duration tolerance: {args.dur_tol}s")
    print()

    rows = []
    actions = 0

    for dm in dupe_metas:
        # First pass: exact key match
        candidates = index.get((norm_key(dm.artist), norm_key(dm.title)), [])

        best: Optional[TrackMeta] = None
        best_score = -1
        best_reasons: List[str] = []

        # If no candidates by key, you can optionally broaden (title-only).
        # We'll do title-only to catch differing artist tags, but score will be lower unless album/duration match.
        if not candidates:
            candidates = []
            title_key = norm_key(dm.title)
            if title_key:
                for (ak, tk), lst in index.items():
                    if tk == title_key:
                        candidates.extend(lst)

        for sm in candidates:
            s, reasons = score_match(sm, dm, args.dur_tol)
            if s > best_score:
                best_score = s
                best = sm
                best_reasons = reasons

        if best is None:
            continue

        is_likely = best_score >= args.threshold

        rows.append([
            dm.path,
            dm.artist,
            dm.title,
            dm.album,
            dm.tracknumber,
            f"{dm.duration:.2f}" if dm.duration is not None else "",
            best.path,
            best.artist,
            best.title,
            best.album,
            best.tracknumber,
            f"{best.duration:.2f}" if best.duration is not None else "",
            best_score,
            ",".join(best_reasons),
            "LIKELY_DUPE" if is_likely else "maybe",
        ])

        if not is_likely:
            continue

        # Build quarantine destination folder
        artist_dir = safe_dirname(dm.artist) if dm.artist else "_UnknownArtist"
        title_dir = safe_dirname(dm.title) if dm.title else "_UnknownTitle"
        dest_dir = os.path.join(quarantine_root, artist_dir, title_dir)
        os.makedirs(dest_dir, exist_ok=True)

        dest_path = os.path.join(dest_dir, os.path.basename(dm.path))

        # Avoid overwriting
        final_dest = dest_path
        if os.path.exists(final_dest):
            base, ext = os.path.splitext(final_dest)
            n = 2
            while os.path.exists(f"{base} ({n}){ext}"):
                n += 1
            final_dest = f"{base} ({n}){ext}"

        if args.apply:
            if args.move:
                shutil.move(dm.path, final_dest)
            else:
                shutil.copy2(dm.path, final_dest)
            actions += 1

    # Write CSV report
    with open(args.report, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "dupe_path","dupe_artist","dupe_title","dupe_album","dupe_tracknumber","dupe_duration",
            "source_match_path","source_artist","source_title","source_album","source_tracknumber","source_duration",
            "score","reasons","classification"
        ])
        w.writerows(rows)

    print(f"Report written: {os.path.abspath(args.report)}")
    print(f"Likely dupes {'moved/copied' if args.apply else 'would be moved/copied'}: {actions}")
    print(f"Quarantine folder: {quarantine_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())