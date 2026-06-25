#!/usr/bin/env python3
"""
triage_sort_by_artist.py

Sort audio files into Triage/<Artist>/ folders.

Heuristic:
1) Read tags (ARTIST, then ALBUMARTIST) via mutagen.
2) If missing, infer from filename:
   - "YYYY - Artist - ..."  (common in your remix folders)
   - "Artist - ..."         (common)
3) If still missing, infer from parent folder name using the same patterns.
4) If still ambiguous, send to Triage/_Unknown/

Default is DRY RUN (no moves). Use --apply to actually move files.

Install:
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install -U pip mutagen

Usage:
  # Dry run
  python triage_sort_by_artist.py "/path/to/Remix Inbox"

  # Actually move
  python triage_sort_by_artist.py "/path/to/Remix Inbox" --apply

  # Choose triage root explicitly
  python triage_sort_by_artist.py "/path/to/Remix Inbox" --apply --triage-root "/path/to/Triage"

Notes:
- Moves files, not folders. (Safer.)
- If you want "move whole release folders", say so and I’ll give that variant.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
from dataclasses import dataclass
from typing import Optional

from mutagen import File as MutagenFile
from mutagen.flac import FLAC
from mutagen.mp4 import MP4
from mutagen.easyid3 import EasyID3


AUDIO_EXTS = {".flac", ".mp3", ".m4a", ".mp4"}

YEAR_ARTIST_PAT = re.compile(r"^\s*(\d{4})\s*-\s*(.+?)\s*-\s*(.+)\s*$")
ARTIST_DASH_PAT = re.compile(r"^\s*(.+?)\s*-\s*(.+)\s*$")

# Remove leading track numbers: "01 - " / "01." / "01 " / "A1 " etc.
LEADING_TRACKNUM_PAT = re.compile(r"^\s*(?:[A-D]\s*\.)?\s*\d{1,3}\s*([.\-)\]]|\s+)\s*")

# Characters not great for folder names
BAD_FS_CHARS = re.compile(r'[\/:*?"<>|]+')

REMIX_HINT = re.compile(
    r"(remix|mix|edit|version|dub|extended|club|instrumental|12\"|12in|12-inch)",
    re.IGNORECASE
)

@dataclass
class Guess:
    artist: str
    source: str  # tag/filename/parent/unknown


def clean_artist(s: str) -> str:
    s = s.strip()
    s = s.replace("_", " ")
    s = re.sub(r"\s+", " ", s)
    return s


def safe_folder_name(s: str) -> str:
    s = clean_artist(s)
    s = BAD_FS_CHARS.sub("-", s)
    s = s.strip(" .")
    return s or "_Unknown"


def read_artist_from_tags(path: str) -> Optional[str]:
    ext = os.path.splitext(path)[1].lower()

    try:
        if ext == ".flac":
            a = FLAC(path)
            v = (a.get("artist") or a.get("ARTIST") or a.get("albumartist") or a.get("ALBUMARTIST"))
            if v:
                return str(v[0]).strip()
            return None

        if ext in {".m4a", ".mp4"}:
            a = MP4(path)
            if not a.tags:
                return None
            # artist then albumartist
            v = a.tags.get("\xa9ART") or a.tags.get("aART")
            if v:
                return str(v[0]).strip()
            return None

        if ext == ".mp3":
            # EasyID3 can throw if there’s no ID3
            try:
                a = EasyID3(path)
                v = (a.get("artist") or a.get("albumartist"))
                if v:
                    return str(v[0]).strip()
                return None
            except Exception:
                audio = MutagenFile(path, easy=True)
                if audio and audio.tags:
                    v = audio.tags.get("artist") or audio.tags.get("albumartist")
                    if v:
                        return str(v[0]).strip()
                return None

        # fallback
        audio = MutagenFile(path, easy=True)
        if audio and audio.tags:
            v = audio.tags.get("artist") or audio.tags.get("albumartist")
            if v:
                return str(v[0]).strip()
    except Exception:
        return None

    return None


def infer_artist_from_name(name: str) -> Optional[str]:
    base = os.path.splitext(name)[0]
    base = base.replace("–", "-").replace("—", "-")

    # strip leading track number like "01 - "
    base = LEADING_TRACKNUM_PAT.sub("", base).strip()

    m = YEAR_ARTIST_PAT.match(base)
    if m:
        return clean_artist(m.group(2))

    m = ARTIST_DASH_PAT.match(base)
    if m:
        # If left side looks like a year, don't treat it as artist
        left = m.group(1).strip()
        if re.fullmatch(r"\d{4}", left):
            return None
        return clean_artist(left)

    return None


def guess_artist(path: str) -> Guess:
    # 1) tags
    a = read_artist_from_tags(path)
    if a:
        return Guess(clean_artist(a), "tag")

    # 2) filename
    a = infer_artist_from_name(os.path.basename(path))
    if a:
        return Guess(a, "filename")

    # 3) parent folder name
    parent = os.path.basename(os.path.dirname(path))
    a = infer_artist_from_name(parent)
    if a:
        return Guess(a, "parent")

    # 4) grandparent (useful if files are "01 - Track.flac" under "Artwork" sibling etc.)
    gp = os.path.basename(os.path.dirname(os.path.dirname(path)))
    a = infer_artist_from_name(gp)
    if a:
        return Guess(a, "grandparent")

    return Guess("_Unknown", "unknown")


def iter_audio_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        # skip hidden dirs
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in filenames:
            ext = os.path.splitext(fn)[1].lower()
            if ext in AUDIO_EXTS:
                yield os.path.join(dirpath, fn)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", help="Folder containing unsorted files (recursive).")
    ap.add_argument("--triage-root", default="Triage", help="Triage folder (default: ./Triage)")
    ap.add_argument("--apply", action="store_true", help="Actually move files (default is dry run).")
    ap.add_argument("--keep-subfolders", action="store_true",
                    help="Preserve relative subfolder structure inside Artist folder.")
    ap.add_argument("--only-remixes", action="store_true",
                help="Only move files that look like remixes (name contains remix/mix/edit/etc.)")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    triage_root = os.path.abspath(args.triage_root)

    if not os.path.isdir(root):
        print(f"Not a directory: {root}")
        return 2

    planned = []
    for path in iter_audio_files(root):
        g = guess_artist(path)
        artist_folder = safe_folder_name(g.artist)

        if args.keep_subfolders:
            rel = os.path.relpath(os.path.dirname(path), root)
            dest_dir = os.path.join(triage_root, artist_folder, rel)
        else:
            dest_dir = os.path.join(triage_root, artist_folder)

        dest_path = os.path.join(dest_dir, os.path.basename(path))
        planned.append((path, dest_path, g.source, g.artist))

    print(f"Found {len(planned)} audio files under: {root}")
    print(f"Triage root: {triage_root}")
    print(f"Mode: {'APPLY (move files)' if args.apply else 'DRY RUN'}\n")

    # Preview first 30
    for i, (src, dst, source, artist) in enumerate(planned[:30], start=1):
        print(f"{i:02d}. [{source}] {artist} :: {os.path.basename(src)}")
        print(f"    -> {dst}")

    if len(planned) > 30:
        print(f"\n… +{len(planned)-30} more\n")

    if not args.apply:
        print("Dry run only. Re-run with --apply to actually move files.")
        return 0

    for src, dst, source, artist in planned:
        os.makedirs(os.path.dirname(dst), exist_ok=True)

        # Avoid clobbering: if exists, add suffix
        final_dst = dst
        if os.path.exists(final_dst):
            base, ext = os.path.splitext(final_dst)
            n = 2
            while os.path.exists(f"{base} ({n}){ext}"):
                n += 1
            final_dst = f"{base} ({n}){ext}"

        shutil.move(src, final_dst)

    print("Done. Files moved.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())