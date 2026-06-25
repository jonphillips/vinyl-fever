#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import os
import re
from dataclasses import dataclass
from typing import Optional, Tuple, List

from mutagen import File as MutagenFile
from mutagen.mp4 import MP4, MP4Cover
from mutagen.easyid3 import EasyID3
from mutagen.flac import FLAC

# For MP3 artwork
from mutagen.id3 import ID3, APIC, ID3NoHeaderError


AUDIO_EXTS = {".mp3", ".m4a", ".mp4", ".flac"}

PAREN_GROUPS_PAT = re.compile(r"\(([^)]{1,180})\)")
LEADING_NUM_SPACE = re.compile(r"^\s*\d{1,4}\s+")
ARTIST_DASH_TITLE = re.compile(r"^\s*(.+?)\s*-\s*(.+?)\s*$")

# NEW: strip leading track numbers from TITLE tags (e.g., "094 Foo", "01 - Foo", "7. Foo")
LEADING_TRACKNUM_TITLE_RE = re.compile(
    r"""(?x) ^
    \s*
    (?P<num>\d{1,4})
    (?:
        \s*[-.)\]]\s*      # "01 - ", "7.) ", "12] "
      | \s+                # "094 "
    )
    (?P<rest>.+?)
    \s*$"""
)

# Strip a "covers compilation" prefix up to the first dash, keep the rest
STRIP_COVERS_PREFIX_RE = re.compile(
    r"(?ix)^\s*"
    r"\d+\s*best\s*covers\b"
    r"(?:\s*ever)?\b"
    r".*?"
    r"\s*-\s*"
    r"(.+?)\s*$"
)

# Strip "99 Best Covers ..." album prefix.
# If the string has TWO " - " separators, we drop:
#   "99 Best Covers ... - <comp track title> - "
# and keep the remainder (the real source album).
STRIP_COVERS_2DASH_RE = re.compile(
    r"(?ix)^\s*"
    r"\d+\s*best\s*covers\b"          # "99 Best Covers"
    r"(?:\s*ever)?\b"                 # optional "Ever"
    r".*?"                            # anything like "(III)"
    r"\s*-\s*.+?\s*-\s*"              # dash, comp track title, dash
    r"(.+?)\s*$"                      # capture remainder (real source album)
)

# Fallback: if only ONE dash exists, keep prior behavior
STRIP_COVERS_1DASH_RE = re.compile(
    r"(?ix)^\s*"
    r"\d+\s*best\s*covers\b"
    r"(?:\s*ever)?\b"
    r".*?"
    r"\s*-\s*"
    r"(.+?)\s*$"
)

# Cleans "(R. E. M.)" -> "R.E.M."
SPACED_INITIALS = re.compile(r"\b([A-Z])\.\s+(?=[A-Z]\.)")

# Remove fluff around "cover"
COVER_WORD = re.compile(r"(?i)\bcover\b")
LEADING_FLUFF = re.compile(r"(?i)^\s*(?:cover\s+of\s+|originally\s+by\s+|by\s+)\s*")
TRAILING_FLUFF = re.compile(r"(?i)\s*(?:song)?\s*(?:cover|original)\s*$")


@dataclass
class Meta:
    path: str
    ext: str
    artist: str
    title: str
    album: str


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").replace("\u00A0", " ")).strip()


def filename_stem(path: str) -> str:
    stem = os.path.splitext(os.path.basename(path))[0]
    stem = stem.replace("–", "-").replace("—", "-")
    stem = LEADING_NUM_SPACE.sub("", stem).strip()
    return stem


def parse_artist_title_from_filename(path: str) -> Tuple[str, str]:
    stem = filename_stem(path)
    m = ARTIST_DASH_TITLE.match(stem)
    if not m:
        return "", ""
    return norm(m.group(1)), norm(m.group(2))


def normalize_spaced_initials(s: str) -> str:
    out = s
    while True:
        out2 = SPACED_INITIALS.sub(r"\1.", out)
        if out2 == out:
            break
        out = out2
    return out


def clean_parenthetical_artist(s: str) -> str:
    s = norm(s)
    if not s:
        return s

    s = LEADING_FLUFF.sub("", s).strip()
    s = TRAILING_FLUFF.sub("", s).strip()
    s = COVER_WORD.sub("", s).strip()

    # If "A-B" style, default to first token (you can change if you want)
    if "-" in s:
        parts = [norm(p) for p in s.split("-") if norm(p)]
        if parts:
            s = parts[0]

    s = normalize_spaced_initials(s)
    return s.strip(" -–—")


def looks_like_artist(s: str) -> bool:
    s = norm(s)
    if not s:
        return False
    bad = {"live", "remix", "edit", "mix", "mono", "stereo", "version", "demo"}
    if s.casefold() in bad:
        return False
    if not re.search(r"[A-Za-z]", s):
        return False
    return True


def extract_original_artist_from_filename(path: str) -> Optional[str]:
    stem = filename_stem(path)
    groups = [g.strip() for g in PAREN_GROUPS_PAT.findall(stem)]
    if not groups:
        return None

    candidates: List[str] = []
    for g in groups:
        g2 = clean_parenthetical_artist(g)
        if looks_like_artist(g2):
            candidates.append(g2)

    if not candidates:
        return None

    # choose last "artist-like" parenthetical
    return candidates[-1]


def strip_leading_tracknum_from_title(title: str) -> str:
    """
    Remove leading track numbers from the *tag title*:
      "094 The Walkmen - ..."  -> "The Walkmen - ..."
      "01 - Foo"               -> "Foo"
      "7. Bar"                 -> "Bar"

    Safety: do NOT strip real year-like titles such as "1999".
    """
    t = norm(title)
    m = LEADING_TRACKNUM_TITLE_RE.match(t)
    if not m:
        return t

    num_s = m.group("num")
    rest = norm(m.group("rest"))

    # Guard: if it's a plausible year title like "1999" and the "rest" looks like a title itself,
    # we should NOT strip. (Most track numbers you have are <= 999 or have leading zeros.)
    try:
        n = int(num_s)
    except ValueError:
        return t

    if len(num_s) == 4 and not num_s.startswith("0") and 1900 <= n <= 2099:
        # Example: "1999" (Prince) should stay "1999"
        # If the original title is exactly "1999" it would not match anyway;
        # this guard mostly protects weird cases like "1999 Something".
        return t

    return rest if rest else t


def read_meta(path: str) -> Optional[Meta]:
    ext = os.path.splitext(path)[1].lower()
    if ext not in AUDIO_EXTS:
        return None

    audio = MutagenFile(path)
    if audio is None:
        return None

    artist = title = album = ""

    try:
        if ext == ".mp3":
            eid3 = EasyID3(path)
            artist = (eid3.get("artist") or [""])[0]
            title  = (eid3.get("title") or [""])[0]
            album  = (eid3.get("album") or [""])[0]
        elif ext in {".m4a", ".mp4"}:
            mp4 = MP4(path)
            tags = mp4.tags or {}
            artist = (tags.get("\xa9ART") or [""])[0]
            title  = (tags.get("\xa9nam") or [""])[0]
            album  = (tags.get("\xa9alb") or [""])[0]
        elif ext == ".flac":
            fl = FLAC(path)
            tags = fl.tags or {}
            artist = (tags.get("ARTIST") or tags.get("artist") or [""])[0]
            title  = (tags.get("TITLE") or tags.get("title") or [""])[0]
            album  = (tags.get("ALBUM") or tags.get("album") or [""])[0]
    except Exception:
        pass

    artist = norm(str(artist))
    title  = norm(str(title))
    album  = norm(str(album))

    # filename fallback for missing artist/title
    if not artist or not title:
        fa, ft = parse_artist_title_from_filename(path)
        artist = artist or fa
        title  = title or ft

    if not title:
        return None

    return Meta(path=path, ext=ext, artist=artist, title=title, album=album)


def build_new_title(title: str, orig_artist: str, source_album: str) -> str:
    src = norm(source_album)

    m = STRIP_COVERS_2DASH_RE.match(src)
    if m:
        src = m.group(1).strip()
    else:
        m = STRIP_COVERS_1DASH_RE.match(src)
        if m:
            src = m.group(1).strip()

    # If the remaining "real source album" begins with a track number, strip it:
    # e.g. "086 Remake the Ultimate Covers Collection" -> "Remake the Ultimate Covers Collection"
    src = LEADING_NUM_SPACE.sub("", src).strip()

    if src:
        return f"{title} ({orig_artist}) [{src}]"
    return f"{title} ({orig_artist})"


def write_tags(m: Meta, new_title: str, new_album: str, new_albumartist: str) -> None:
    ext = m.ext

    if ext == ".mp3":
        eid3 = EasyID3(m.path)
        eid3["title"] = [new_title]
        eid3["album"] = [new_album]
        eid3["albumartist"] = [new_albumartist]
        eid3.save()
        return

    if ext in {".m4a", ".mp4"}:
        mp4 = MP4(m.path)
        if mp4.tags is None:
            mp4.add_tags()
        mp4.tags["\xa9nam"] = [new_title]
        mp4.tags["\xa9alb"] = [new_album]
        mp4.tags["aART"] = [new_albumartist]
        mp4.tags["cpil"] = [1]  # compilation
        mp4.save()
        return

    if ext == ".flac":
        fl = FLAC(m.path)
        fl["TITLE"] = new_title
        fl["ALBUM"] = new_album
        fl["ALBUMARTIST"] = new_albumartist
        fl.save()
        return


# ---------------- Artwork embedding ----------------

def load_art_bytes(art_path: str) -> tuple[bytes, str]:
    p = os.path.abspath(os.path.expanduser(art_path))
    if not os.path.isfile(p):
        raise FileNotFoundError(f"Artwork not found: {p}")
    ext = os.path.splitext(p)[1].lower()
    if ext not in {".jpg", ".jpeg", ".png"}:
        raise ValueError(f"Artwork must be .jpg/.jpeg or .png (got {ext})")
    with open(p, "rb") as f:
        return f.read(), ext


def set_m4a_artwork(m4a_path: str, art_bytes: bytes, art_ext: str) -> None:
    fmt = MP4Cover.FORMAT_JPEG if art_ext in {".jpg", ".jpeg"} else MP4Cover.FORMAT_PNG
    mp4 = MP4(m4a_path)
    if mp4.tags is None:
        mp4.add_tags()
    mp4.tags["covr"] = [MP4Cover(art_bytes, imageformat=fmt)]
    mp4.save()


def set_mp3_artwork(mp3_path: str, art_bytes: bytes, art_ext: str) -> None:
    mime = "image/jpeg" if art_ext in {".jpg", ".jpeg"} else "image/png"
    try:
        id3 = ID3(mp3_path)
    except ID3NoHeaderError:
        id3 = ID3()

    id3.delall("APIC")
    id3.add(APIC(encoding=3, mime=mime, type=3, desc="Cover", data=art_bytes))
    id3.save(mp3_path)


def embed_artwork(path: str, art_bytes: bytes, art_ext: str) -> None:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".mp3":
        set_mp3_artwork(path, art_bytes, art_ext)
    elif ext in {".m4a", ".mp4"}:
        set_m4a_artwork(path, art_bytes, art_ext)
    # FLAC not requested here


# ---------------- Filesystem ----------------

def iter_files(root: str) -> List[str]:
    out: List[str] = []
    for base, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in filenames:
            if os.path.splitext(fn)[1].lower() in AUDIO_EXTS:
                out.append(os.path.join(base, fn))
    return sorted(out)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=(
            "Rewrite tags to build a 'Great Covers' compilation, inferring original artist from filename parentheses, "
            "optionally replace embedded artwork, and strip leading track numbers from title tags."
        )
    )
    ap.add_argument("root", help="Folder to crawl recursively.")
    ap.add_argument("--write", action="store_true", help="Apply changes (default is dry run).")
    ap.add_argument("--album", default="Great Covers", help='Album name (default: "Great Covers")')
    ap.add_argument("--albumartist", default="Various Artists", help='Album Artist (default: "Various Artists")')
    ap.add_argument("--artwork", default="", help="Path to a JPG/PNG to embed as artwork for each MP3 + M4A/MP4.")
    ap.add_argument("--quiet", action="store_true", help="Less output.")
    ap.add_argument("--skips-csv", default="", help="Write a CSV report of skipped files (path,reason,filename).")
    args = ap.parse_args()

    files = iter_files(os.path.abspath(args.root))
    if not files:
        print("No audio files found.")
        return 1

    art_bytes: bytes | None = None
    art_ext: str = ""
    if args.artwork:
        art_bytes, art_ext = load_art_bytes(args.artwork)

    changed = 0
    skipped = 0
    skip_rows: List[Tuple[str, str, str]] = []

    for path in files:
        m = read_meta(path)
        if not m:
            skipped += 1
            reason = "no_readable_metadata_or_title"
            skip_rows.append((path, reason, os.path.basename(path)))
            if not args.quiet:
                print(f"SKIP: {os.path.basename(path)}  ({reason})")
            continue

        orig = extract_original_artist_from_filename(path)
        if not orig:
            skipped += 1
            reason = "could_not_infer_original_artist_from_filename_parentheses"
            skip_rows.append((path, reason, os.path.basename(path)))
            if not args.quiet:
                print(f"SKIP: {os.path.basename(path)}  ({reason})")
            continue

        base_title = strip_leading_tracknum_from_title(m.title)
        new_title = build_new_title(base_title, orig, m.album)

        needs_tags = (new_title != m.title) or (m.album != args.album)
        ext = os.path.splitext(path)[1].lower()
        needs_art = bool(args.artwork) and ext in {".mp3", ".m4a", ".mp4"}

        if not (needs_tags or needs_art):
            continue

        changed += 1
        if not args.quiet:
            print(f"\n{os.path.basename(path)}")
            print(f"  Artist: {m.artist}")
            if needs_tags:
                print(f"  Old:    {m.title}")
                print(f"  New:    {new_title}")
                print(f"  Album:  {args.album}  | AlbumArtist: {args.albumartist}")
            if needs_art:
                print(f"  Artwork: {'set' if args.artwork else 'none'}")

        if args.write:
            if needs_tags:
                write_tags(m, new_title, args.album, args.albumartist)
            if needs_art and art_bytes is not None:
                embed_artwork(path, art_bytes, art_ext)

    if args.skips_csv:
        with open(args.skips_csv, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["path", "reason", "filename"])
            w.writerows(skip_rows)
        print(f"\nWrote skipped report: {args.skips_csv}")

    print(f"\nScanned: {len(files)}")
    print(f"{'Changed' if args.write else 'Would change'}: {changed}")
    print(f"Skipped: {skipped}")
    if not args.write:
        print("Dry run only. Re-run with --write to apply.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())