#!/usr/bin/env python3
"""
Consensus-based title scrubber for local music files.

What it does:
- Walks a directory tree and reads ARTIST + TITLE from audio files.
- For each artist, groups titles by a "normalized key" (case/punct/space-insensitive).
- Chooses the most frequent original title string as the canonical title for that key.
- Proposes changes for files whose TITLE differs from the canonical.
- Flags cases where the canonical differs from a simple rule-based Title Case output
  (a cue for sanity checking).

Supported formats:
- FLAC (.flac)
- MP3 (.mp3)
- M4A/MP4 (.m4a, .mp4)

Requires:
  pip install mutagen
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from typing import Optional, Tuple

from mutagen import File as MutagenFile
from mutagen.flac import FLAC
from mutagen.easyid3 import EasyID3
from mutagen.mp4 import MP4


# ----------------- Normalization / Rule-based suggestion -----------------

_SMALL_WORDS = {
    "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into",
    "nor", "of", "on", "or", "over", "per", "the", "to", "up", "via", "with",
}

_ROMAN = re.compile(r"^(?=[MDCLXVI])M{0,4}(CM|CD|D?C{0,3})"
                    r"(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$", re.I)

_WORD_SPLIT = re.compile(r"(\s+|[-/])")  # keep separators


def normalized_key(title: str) -> str:
    """
    Collapse titles that differ only by capitalization/punctuation/spacing.

    Example:
      "So. Central Rain" == "so central rain" == "So Central Rain"
    """
    t = title.casefold()
    t = re.sub(r"[’']", "", t)                 # normalize apostrophes away
    t = re.sub(r"[^a-z0-9]+", "", t)           # drop everything non-alnum
    return t


def title_case_rule(s: str) -> str:
    """
    Conservative title-casing:
    - keeps separators and whitespace
    - lowercases "small words" unless first/last
    - preserves ALLCAPS words and Roman numerals
    """
    parts = _WORD_SPLIT.split(s)
    words = [p for p in parts if p and not _WORD_SPLIT.fullmatch(p)]
    if not words:
        return s

    # Determine word positions among actual "word" tokens.
    word_positions = []
    idx = 0
    for i, p in enumerate(parts):
        if p and not _WORD_SPLIT.fullmatch(p) and not p.isspace():
            word_positions.append(i)
            idx += 1

    first_i = word_positions[0]
    last_i = word_positions[-1]

    def cap_word(w: str, is_first: bool, is_last: bool) -> str:
        if w.isupper() and len(w) > 1:
            return w
        if _ROMAN.match(w):
            return w.upper()

        # Split on apostrophes but preserve them in output
        chunks = re.split(r"([’'])", w)
        out = []
        for c in chunks:
            if c in {"'", "’"}:
                out.append(c)
                continue
            if not c:
                continue

            lower = c.lower()
            if not is_first and not is_last and lower in _SMALL_WORDS:
                out.append(lower)
            else:
                out.append(lower[:1].upper() + lower[1:])
        return "".join(out)

    out_parts = []
    for i, p in enumerate(parts):
        if not p or _WORD_SPLIT.fullmatch(p) or p.isspace():
            out_parts.append(p)
            continue
        is_first = (i == first_i)
        is_last = (i == last_i)
        out_parts.append(cap_word(p, is_first, is_last))

    return "".join(out_parts)


def looks_non_rule_like(canonical: str) -> bool:
    """Flag when rule-based title case would change the canonical title."""
    return canonical != title_case_rule(canonical)


# ----------------- Tag I/O -----------------

def _first_str(v) -> Optional[str]:
    if v is None:
        return None
    if isinstance(v, (list, tuple)):
        return str(v[0]) if v else None
    return str(v)


def read_artist_title(path: str) -> Tuple[Optional[str], Optional[str], object]:
    """
    Returns (artist, title, mutagen_object).
    Uses ARTIST if possible; falls back to ALBUMARTIST; else None.
    """
    audio = MutagenFile(path)
    if audio is None:
        return None, None, None

    artist = None
    title = None

    if isinstance(audio, FLAC):
        artist = _first_str(audio.tags.get("artist")) or _first_str(audio.tags.get("albumartist"))
        title = _first_str(audio.tags.get("title"))
    elif isinstance(audio, MP4):
        # MP4 atom keys
        artist = _first_str(audio.tags.get("\xa9ART")) or _first_str(audio.tags.get("aART"))
        title = _first_str(audio.tags.get("\xa9nam"))
    else:
        # MP3 (ID3) and others that Mutagen maps to dict-like tags
        try:
            if audio.tags is None:
                return None, None, audio
            # EasyID3 is nicer but may not be installed for existing files; Mutagen usually handles it.
            artist = _first_str(audio.tags.get("artist")) or _first_str(audio.tags.get("albumartist"))
            title = _first_str(audio.tags.get("title"))
        except Exception:
            pass

    return artist, title, audio


def write_title(path: str, audio_obj: object, new_title: str) -> None:
    """Writes TITLE tag back to file."""
    if audio_obj is None:
        raise RuntimeError("No mutagen object loaded")

    if isinstance(audio_obj, FLAC):
        audio_obj["title"] = [new_title]
        audio_obj.save()
    elif isinstance(audio_obj, MP4):
        audio_obj["\xa9nam"] = [new_title]
        audio_obj.save()
    else:
        # MP3 / ID3 via EasyID3 if possible
        try:
            audio = audio_obj
            if audio.tags is None:
                audio.add_tags()

            # Prefer EasyID3 mapping if available
            try:
                e = EasyID3(path)
                e["title"] = [new_title]
                e.save()
                return
            except Exception:
                # fallback: raw tags
                audio.tags["TIT2"] = new_title
                audio.save()
        except Exception as e:
            raise RuntimeError(f"Failed writing title: {e}") from e


# ----------------- Data model -----------------

@dataclass
class TrackInfo:
    path: str
    artist: str
    title: str
    audio_obj: object


# ----------------- Main logic -----------------

def gather_tracks(root: str, exts: set[str]) -> list[TrackInfo]:
    tracks: list[TrackInfo] = []
    for dirpath, _, filenames in os.walk(root):
        for fn in filenames:
            ext = os.path.splitext(fn)[1].lower()
            if ext not in exts:
                continue
            path = os.path.join(dirpath, fn)
            artist, title, audio = read_artist_title(path)
            if not audio or not title:
                continue
            artist = artist or "Unknown Artist"
            tracks.append(TrackInfo(path=path, artist=artist, title=title, audio_obj=audio))
    return tracks


def build_consensus(tracks: list[TrackInfo], min_support: int) -> dict[tuple[str, str], str]:
    """
    Returns mapping:
      (artist, normalized_key(title)) -> canonical_title
    """
    buckets: dict[tuple[str, str], Counter[str]] = defaultdict(Counter)
    for t in tracks:
        key = normalized_key(t.title)
        buckets[(t.artist, key)][t.title] += 1

    canonical: dict[tuple[str, str], str] = {}
    for k, counter in buckets.items():
        total = sum(counter.values())
        if total < min_support:
            continue
        # most common; tie-breaker: shortest (often cleaner), then lexicographic
        most = counter.most_common()
        top_count = most[0][1]
        top_titles = [s for s, c in most if c == top_count]
        top_titles.sort(key=lambda s: (len(s), s))
        canonical[k] = top_titles[0]
    return canonical


def main() -> int:
    ap = argparse.ArgumentParser(description="Consensus-based title scrubber (per artist).")
    ap.add_argument("root", nargs="?", default=".", help="Root folder to scan (default: .)")
    ap.add_argument("--apply", action="store_true", help="Apply changes (default is dry-run)")
    ap.add_argument("--min-support", type=int, default=2,
                    help="Minimum occurrences within an artist/key to trust consensus (default: 2)")
    ap.add_argument("--exts", default=".flac,.mp3,.m4a,.mp4",
                    help="Comma-separated extensions to scan (default: .flac,.mp3,.m4a,.mp4)")
    ap.add_argument("--report", default="title_scrub_report.csv",
                    help="CSV report path (default: title_scrub_report.csv)")
    args = ap.parse_args()

    exts = {e.strip().lower() for e in args.exts.split(",") if e.strip()}
    tracks = gather_tracks(args.root, exts)

    if not tracks:
        print("No tagged audio files found.")
        return 1

    canonical_map = build_consensus(tracks, min_support=args.min_support)

    changes = []
    for t in tracks:
        key = (t.artist, normalized_key(t.title))
        canonical = canonical_map.get(key)
        if not canonical:
            continue
        if t.title == canonical:
            continue

        # Notes for sanity checking
        note_parts = []
        if looks_non_rule_like(canonical):
            note_parts.append("CANONICAL_NOT_RULE_CASED")
        # If the current title would rule-case differently too, note it
        if t.title != title_case_rule(t.title):
            note_parts.append("CURRENT_NOT_RULE_CASED")
        note = ";".join(note_parts)

        changes.append((t, canonical, note))

    # Write report
    with open(args.report, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["path", "artist", "old_title", "canonical_title", "rule_case(canonical)", "note"])
        for t, canonical, note in changes:
            w.writerow([t.path, t.artist, t.title, canonical, title_case_rule(canonical), note])

    print(f"Scanned: {len(tracks)} files")
    print(f"Proposed title changes: {len(changes)}")
    print(f"Report: {args.report}")

    # Preview first 20
    for i, (t, canonical, note) in enumerate(changes[:20], start=1):
        print(f"{i:02d}. {t.artist} | {os.path.basename(t.path)}")
        print(f"    {t.title}  ->  {canonical}" + (f"   [{note}]" if note else ""))

    if not args.apply:
        print("\nDry run only. Re-run with --apply to write changes.")
        return 0

    # Apply
    ok = 0
    failed = 0
    for t, canonical, _note in changes:
        try:
            write_title(t.path, t.audio_obj, canonical)
            ok += 1
        except Exception as e:
            failed += 1
            print(f"FAIL: {t.path} :: {e}", file=sys.stderr)

    print(f"\nApplied: {ok}  Failed: {failed}")
    return 0 if failed == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())