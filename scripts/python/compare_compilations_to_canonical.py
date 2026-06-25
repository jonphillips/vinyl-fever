#!/usr/bin/env python3
"""
compare_compilations_to_canonical.py

Find tracks in compilation folders (e.g., "Promo Only*", "Radio Essential Series*")
that are NOT present in canonical library roots (70s/80s/90s/2000s, etc).

Matching priority:
  1) MusicBrainz Track ID (if present)
  2) normalized (artist, title, duration bucket)
  3) normalized (artist, title) fallback

Requires: mutagen (pip install mutagen) for best results.
If mutagen is unavailable, it will fall back to filename-based heuristics (less accurate).
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple

AUDIO_EXTS = {".flac", ".mp3", ".m4a", ".aac", ".alac", ".ogg", ".opus", ".wav", ".aiff", ".aif"}

# Folder prefixes under the Compilations directory to include
DEFAULT_COMP_PREFIXES = ["Promo Only", "Radio Essential Series"]

# Default canonical roots (exactly what you described)
DEFAULT_CANONICAL_ROOTS = [
    "/Volumes/Music Library/70s Unified",
    "/Volumes/Music Library/80s Unified",
    "/Volumes/Music Library/90s Unified",
    "/Volumes/Music Library/821.Greatest.Hit.Singles.of.the.2000s.FLAC.h33t.-.Kitlope",
]

DEFAULT_COMPILATIONS_ROOT = "/Volumes/Music Library/Jon Music Library/Media.localized/Music/Compilations"

# --- Optional metadata reading via mutagen ---
try:
    from mutagen import File as MutagenFile  # type: ignore
    MUTAGEN_AVAILABLE = True
except Exception:
    MUTAGEN_AVAILABLE = False


@dataclass(frozen=True)
class TrackMeta:
    path: Path
    artist: str = ""
    title: str = ""
    album: str = ""
    albumartist: str = ""
    tracknumber: str = ""
    duration_sec: Optional[int] = None
    mbid: str = ""


def is_audio_file(p: Path) -> bool:
    return p.is_file() and p.suffix.lower() in AUDIO_EXTS


_feat_re = re.compile(r"\b(feat\.?|featuring|ft\.?)\b.*$", re.IGNORECASE)
_punct_re = re.compile(r"[^a-z0-9]+", re.IGNORECASE)


def normalize_text(s: str) -> str:
    """Lowercase, strip, drop trailing feat/ft clauses, remove punctuation, collapse whitespace."""
    if not s:
        return ""
    s = s.strip().lower()
    s = _feat_re.sub("", s).strip()
    s = _punct_re.sub(" ", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def duration_bucket(seconds: Optional[int], bucket: int) -> Optional[int]:
    """Bucket duration to reduce tiny encoding differences. bucket=2 -> nearest 2 sec."""
    if seconds is None:
        return None
    if bucket <= 1:
        return int(seconds)
    return int(round(seconds / bucket) * bucket)


def get_meta_with_mutagen(path: Path) -> TrackMeta:
    m = TrackMeta(path=path)
    try:
        f = MutagenFile(str(path), easy=True)
        if f is None:
            return m

        def first(key: str) -> str:
            v = f.get(key)
            if not v:
                return ""
            if isinstance(v, list):
                return str(v[0])
            return str(v)

        artist = first("artist")
        title = first("title")
        album = first("album")
        albumartist = first("albumartist")
        tracknumber = first("tracknumber")

        # MusicBrainz track id keys vary; try a few common ones
        mbid = (
            first("musicbrainz_trackid")
            or first("musicbrainz track id")
            or first("mb_trackid")
        ).strip()

        dur = None
        try:
            if hasattr(f, "info") and getattr(f.info, "length", None) is not None:
                dur = int(round(float(f.info.length)))
        except Exception:
            dur = None

        return TrackMeta(
            path=path,
            artist=artist,
            title=title,
            album=album,
            albumartist=albumartist,
            tracknumber=tracknumber,
            duration_sec=dur,
            mbid=mbid,
        )
    except Exception:
        return m


_filename_guess_re = re.compile(
    r"""
    ^
    (?:
        \d+\s*[-_.]\s*   # leading track number like "01 - "
    )?
    (.*?)               # title-ish
    $
    """,
    re.VERBOSE,
)


def get_meta_filename_fallback(path: Path) -> TrackMeta:
    # We can’t reliably infer artist/title; do a best effort on title from filename.
    stem = path.stem
    m = _filename_guess_re.match(stem)
    title = m.group(1) if m else stem
    title = title.replace("_", " ").replace(".", " ").strip()
    return TrackMeta(path=path, title=title)


def read_meta(path: Path) -> TrackMeta:
    if MUTAGEN_AVAILABLE:
        return get_meta_with_mutagen(path)
    return get_meta_filename_fallback(path)


def track_keys(meta: TrackMeta, bucket_sec: int) -> List[Tuple[str, ...]]:
    """
    Generate match keys in priority order.
    """
    keys: List[Tuple[str, ...]] = []

    mbid = meta.mbid.strip().lower()
    if mbid:
        keys.append(("mbid", mbid))

    artist = normalize_text(meta.artist or meta.albumartist)
    title = normalize_text(meta.title)

    durb = duration_bucket(meta.duration_sec, bucket_sec)
    if artist and title and durb is not None:
        keys.append(("atd", artist, title, str(durb)))

    if artist and title:
        keys.append(("at", artist, title))

    # As a last-ditch: title-only (very weak, not used by default for matching)
    return keys


def iter_audio_files(root: Path) -> Iterable[Path]:
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            p = Path(dirpath) / fn
            if is_audio_file(p):
                yield p


def find_compilation_dirs(comp_root: Path, prefixes: List[str]) -> List[Path]:
    prefixes_norm = [p.lower() for p in prefixes]
    dirs: List[Path] = []
    if not comp_root.exists():
        return dirs
    for child in comp_root.iterdir():
        if child.is_dir():
            name = child.name.lower()
            if any(name.startswith(pref.lower()) for pref in prefixes_norm):
                dirs.append(child)
    return sorted(dirs)


def build_canonical_index(
    canonical_roots: List[Path],
    bucket_sec: int,
) -> Dict[Tuple[str, ...], List[Path]]:
    index: Dict[Tuple[str, ...], List[Path]] = {}
    total = 0
    for root in canonical_roots:
        for p in iter_audio_files(root):
            total += 1
            meta = read_meta(p)
            for k in track_keys(meta, bucket_sec):
                index.setdefault(k, []).append(p)
    return index


def main() -> int:
    ap = argparse.ArgumentParser(description="Report compilation tracks not present in canonical decade libraries.")
    ap.add_argument(
        "--canonical",
        action="append",
        default=[],
        help="Canonical library root (repeatable). If omitted, uses built-in defaults.",
    )
    ap.add_argument(
        "--compilations-root",
        default=DEFAULT_COMPILATIONS_ROOT,
        help="Root directory containing compilation folders (default matches your path).",
    )
    ap.add_argument(
        "--prefix",
        action="append",
        default=[],
        help='Compilation directory prefix to include (repeatable). Defaults: "Promo Only", "Radio Essential Series".',
    )
    ap.add_argument(
        "--bucket-sec",
        type=int,
        default=2,
        help="Duration bucketing in seconds for matching (default: 2).",
    )
    ap.add_argument(
        "--csv",
        default="",
        help="Optional path to write missing-track CSV report.",
    )
    ap.add_argument(
        "--show-matches",
        action="store_true",
        help="Also print which canonical track matched each compilation track (verbose).",
    )
    args = ap.parse_args()

    canonical_roots = [Path(p) for p in (args.canonical or DEFAULT_CANONICAL_ROOTS)]
    comp_root = Path(args.compilations_root)
    prefixes = args.prefix or DEFAULT_COMP_PREFIXES

    # Basic sanity checks
    missing_roots = [str(p) for p in canonical_roots if not p.exists()]
    if missing_roots:
        print("WARNING: Some canonical roots do not exist:", file=sys.stderr)
        for r in missing_roots:
            print(f"  - {r}", file=sys.stderr)

    if not comp_root.exists():
        print(f"ERROR: Compilations root not found: {comp_root}", file=sys.stderr)
        return 2

    comp_dirs = find_compilation_dirs(comp_root, prefixes)
    if not comp_dirs:
        print(f"No compilation folders found under {comp_root} starting with: {prefixes}")
        return 0

    if not MUTAGEN_AVAILABLE:
        print("WARNING: 'mutagen' not available. Matching will be filename-based and less accurate.", file=sys.stderr)
        print("Install with: pip install mutagen", file=sys.stderr)

    print("Building canonical index...")
    index = build_canonical_index(canonical_roots, args.bucket_sec)

    missing_rows: List[dict] = []
    total_comp_tracks = 0
    total_missing = 0

    print("\nScanning compilation folders...\n")
    for d in comp_dirs:
        missing_in_dir: List[TrackMeta] = []
        matched_in_dir = 0
        tracks_in_dir = 0

        for p in iter_audio_files(d):
            tracks_in_dir += 1
            total_comp_tracks += 1
            meta = read_meta(p)

            ks = track_keys(meta, args.bucket_sec)
            found_paths: List[Path] = []
            for k in ks:
                if k in index:
                    found_paths = index[k]
                    break

            if found_paths:
                matched_in_dir += 1
                if args.show_matches:
                    show_artist = meta.artist or meta.albumartist or "(unknown artist)"
                    show_title = meta.title or meta.path.stem
                    print(f"[MATCH] {d.name}: {show_artist} — {show_title}")
                    # show just the first match path to avoid noisy output
                    print(f"        -> {found_paths[0]}")
            else:
                missing_in_dir.append(meta)

        if missing_in_dir:
            print(f"=== {d.name} ===")
            print(f"Tracks scanned: {tracks_in_dir} | Matched: {matched_in_dir} | Missing: {len(missing_in_dir)}\n")
            for meta in sorted(missing_in_dir, key=lambda m: (normalize_text(m.artist or m.albumartist), normalize_text(m.title), str(m.path))):
                artist = meta.artist or meta.albumartist or "(unknown artist)"
                title = meta.title or meta.path.stem
                dur = f"{meta.duration_sec}s" if meta.duration_sec is not None else ""
                mbid = f" mbid={meta.mbid}" if meta.mbid else ""
                rel = meta.path.relative_to(d)
                print(f"  - {artist} — {title} {dur}{mbid}")
                print(f"    {rel}")
                missing_rows.append({
                    "compilation_dir": d.name,
                    "file_path": str(meta.path),
                    "artist": artist,
                    "title": title,
                    "album": meta.album,
                    "albumartist": meta.albumartist,
                    "tracknumber": meta.tracknumber,
                    "duration_sec": meta.duration_sec if meta.duration_sec is not None else "",
                    "musicbrainz_trackid": meta.mbid,
                })
            print()
            total_missing += len(missing_in_dir)
        else:
            print(f"=== {d.name} ===")
            print(f"Tracks scanned: {tracks_in_dir} | Matched: {matched_in_dir} | Missing: 0\n")

    print("---- SUMMARY ----")
    print(f"Compilation folders scanned: {len(comp_dirs)}")
    print(f"Compilation tracks scanned:  {total_comp_tracks}")
    print(f"Missing tracks found:        {total_missing}")

    if args.csv:
        out = Path(args.csv)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=[
                "compilation_dir",
                "file_path",
                "artist",
                "title",
                "album",
                "albumartist",
                "tracknumber",
                "duration_sec",
                "musicbrainz_trackid",
            ])
            w.writeheader()
            w.writerows(missing_rows)
        print(f"\nWrote CSV: {out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())