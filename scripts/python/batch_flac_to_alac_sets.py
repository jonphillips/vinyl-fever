#!/usr/bin/env python3
#source .venv/bin/activate
#python batch_flac_to_alac_sets.py "/path/to/ArchiveSets" "/path/to/ALAC_Output" --dry-run
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys
import shutil
import re

from mutagen.mp4 import MP4, MP4FreeForm, MP4Cover

# ---------------- config ----------------

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}  # we can sidecar-copy webp; embed only jpg/png
EMBED_EXTS = {".jpg", ".jpeg", ".png"}           # MP4Cover supports JPG/PNG reliably
MAX_COMMENT = 250
GROUPING_VALUE = '12" Archive'
SORT_ALBUM_PREFIX = "2000 Remix"

FOLDER_RE = re.compile(r"^\s*(\d{4})\s*-\s*(.+?)\s*-\s*(.+?)\s*$")

# ---------------- helpers ----------------

def first_existing(paths: list[pathlib.Path]) -> pathlib.Path | None:
    for p in paths:
        if p.exists():
            return p
    return None

def find_images_in_dir(d: pathlib.Path) -> list[pathlib.Path]:
    return sorted([p for p in d.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS])

def find_front_cover(set_dir: pathlib.Path) -> pathlib.Path | None:
    """
    Preferred front cover selection:
      1) Artwork/A.Front.* or A. Front.* or Side A.* or SideA.*
      2) Artwork/Front.*
      3) First image in Artwork/
      4) folder/front/cover in set root
      5) First image in set root
    """
    art = set_dir / "Artwork"
    if art.is_dir():
        candidates: list[pathlib.Path] = []
        for ext in IMAGE_EXTS:
            candidates += [
                art / f"A.Front{ext}",
                art / f"A. Front{ext}",
                art / f"Side A{ext}",
                art / f"SideA{ext}",
                art / f"Front{ext}",
            ]
        hit = first_existing(candidates)
        if hit:
            return hit

        imgs = find_images_in_dir(art)
        if imgs:
            return imgs[0]

    for stem in ["folder", "front", "cover"]:
        for ext in IMAGE_EXTS:
            p = set_dir / f"{stem}{ext}"
            if p.exists():
                return p

    imgs = sorted([p for p in set_dir.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS])
    return imgs[0] if imgs else None

def find_back_cover(set_dir: pathlib.Path, front: pathlib.Path | None) -> pathlib.Path | None:
    """
    Preferred back cover selection:
      1) Artwork/B.Back.* or B. Back.* or Side B.* or SideB.* or Back.*
      2) Otherwise: choose an image in Artwork/ that is not the front
      3) Otherwise: choose a second image in set root that is not the front
    """
    art = set_dir / "Artwork"
    if art.is_dir():
        candidates: list[pathlib.Path] = []
        for ext in IMAGE_EXTS:
            candidates += [
                art / f"B.Back{ext}",
                art / f"B. Back{ext}",
                art / f"Side B{ext}",
                art / f"SideB{ext}",
                art / f"Back{ext}",
            ]
        hit = first_existing(candidates)
        if hit:
            return hit

        imgs = find_images_in_dir(art)
        if imgs:
            if front is not None:
                imgs2 = [p for p in imgs if p.resolve() != front.resolve()]
                if imgs2:
                    return imgs2[0]
            if len(imgs) >= 2:
                return imgs[1]
            return None

    imgs = sorted([p for p in set_dir.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS])
    if not imgs:
        return None
    if front is not None:
        imgs2 = [p for p in imgs if p.resolve() != front.resolve()]
        return imgs2[0] if imgs2 else None
    return imgs[1] if len(imgs) >= 2 else None

def read_info_path(set_dir: pathlib.Path) -> pathlib.Path | None:
    for p in set_dir.iterdir():
        if p.is_file() and p.name.casefold() == "info.txt":
            return p
    return None

import re

# Matches either:
#  (1) YYYY - Artist - Album
#  (2) Artist - Album (... ) (YYYY) [stuff]
RE1 = re.compile(r"^\s*(\d{4})\s*-\s*(.+?)\s*-\s*(.+?)\s*$")
RE2 = re.compile(r"^\s*(.+?)\s*-\s*(.+?)\s*(?:\((\d{4})\))\s*(?:\[.*\])?\s*$")

def parse_release_folder(folder_name: str):
    m = RE1.match(folder_name)
    if m:
        return m.group(1).strip(), m.group(2).strip(), m.group(3).strip()

    m = RE2.match(folder_name)
    if m:
        artist = m.group(1).strip()
        album = m.group(2).strip()
        year = m.group(3).strip() if m.group(3) else None
        return year, artist, album

    return None, None, None

def copy_sidecar(src: pathlib.Path, dst: pathlib.Path, overwrite: bool) -> None:
    if dst.exists() and not overwrite:
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

def is_set_folder(folder: pathlib.Path) -> bool:
    return any(folder.glob("*.flac"))

# ---------------- ffmpeg conversion ----------------

def ffmpeg_convert(flac_path: pathlib.Path, out_path: pathlib.Path) -> None:
    """
    Convert FLAC -> ALAC 16-bit / 48kHz with dithering.
    Writes via a temp .m4a and commits atomically.

    NOTE: We DO NOT embed artwork via ffmpeg anymore.
    We embed artwork via mutagen as MP4 'covr' (front + back) after conversion.
    """
    tmp_out = out_path.with_name(out_path.stem + ".tmp.m4a")

    # ALAC on your build wants planar 16-bit: s16p
    af_soxr  = "aresample=48000:resampler=soxr:dither_method=triangular,aformat=sample_fmts=s16p"
    af_basic = "aresample=48000:dither_method=triangular,aformat=sample_fmts=s16p"

    def build_cmd(audio_filter: str) -> list[str]:
        return [
            "ffmpeg", "-y",
            "-nostdin", "-hide_banner", "-loglevel", "error",
            "-i", str(flac_path),
            "-map", "0:a:0",
            "-af", audio_filter,
            "-c:a", "alac",
            "-map_metadata", "0",
            "-movflags", "+faststart",
            "-f", "ipod",
            str(tmp_out),
        ]

    if tmp_out.exists():
        tmp_out.unlink()

    try:
        try:
            subprocess.check_call(build_cmd(af_soxr))
        except subprocess.CalledProcessError:
            if tmp_out.exists():
                tmp_out.unlink()
            subprocess.check_call(build_cmd(af_basic))

        if not tmp_out.exists() or tmp_out.stat().st_size < 1024:
            raise RuntimeError(f"Conversion produced an invalid file: {tmp_out}")

        if out_path.exists():
            out_path.unlink()
        tmp_out.replace(out_path)

    finally:
        if tmp_out.exists():
            tmp_out.unlink()

# ---------------- tagging + artwork embed ----------------

def load_image_bytes(img: pathlib.Path) -> tuple[bytes, MP4Cover]:
    ext = img.suffix.lower()
    data = img.read_bytes()

    if ext in {".jpg", ".jpeg"}:
        return data, MP4Cover.FORMAT_JPEG
    if ext == ".png":
        return data, MP4Cover.FORMAT_PNG

    # webp or unknown: we cannot embed reliably as covr without converting
    raise ValueError(f"Unsupported embed image type for covr: {img.name} (use JPG/PNG)")

def write_custom_tags_and_artwork(
    m4a_path: pathlib.Path,
    info_text: str,
    year: str | None,
    artist: str | None,
    album: str | None,
    front: pathlib.Path | None,
    back: pathlib.Path | None,
) -> None:
    mp4 = MP4(str(m4a_path))
    if mp4.tags is None:
        mp4.add_tags()

    # Album-level tags derived from folder name
    if artist:
        mp4.tags["\xa9ART"] = [artist]   # Artist
        mp4.tags["aART"] = [artist]      # Album Artist

    if album:
        mp4.tags["\xa9alb"] = [album]
        if year:
            mp4.tags["soal"] = [f"{SORT_ALBUM_PREFIX} - {year} - {album}"]
        else:
            mp4.tags["soal"] = [f"{SORT_ALBUM_PREFIX} - {album}"]

    if year:
        mp4.tags["\xa9day"] = [year]

    # Grouping for Smart Playlists
    mp4.tags["\xa9grp"] = [GROUPING_VALUE]

    # Long provenance
    if info_text.strip():
        mp4.tags["----:com.apple.iTunes:INFOTXT"] = [MP4FreeForm(info_text.encode("utf-8"))]
        short = " ".join(info_text.strip().split())
        mp4.tags["\xa9cmt"] = [short[:MAX_COMMENT]]
    else:
        mp4.tags["\xa9cmt"] = ["12in archive; see INFOTXT"[:MAX_COMMENT]]

    # Embed artwork (front first, then back)
    covers: list[MP4Cover] = []

    if front and front.exists() and front.suffix.lower() in EMBED_EXTS:
        data, fmt = load_image_bytes(front)
        covers.append(MP4Cover(data, imageformat=fmt))
    elif front and front.exists():
        # Non-embeddable type (e.g. webp) — keep as sidecar only
        pass

    if back and back.exists() and back.suffix.lower() in EMBED_EXTS:
        data, fmt = load_image_bytes(back)
        covers.append(MP4Cover(data, imageformat=fmt))
    elif back and back.exists():
        pass

    if covers:
        mp4.tags["covr"] = covers

    mp4.save()

# ---------------- set processing ----------------

def process_set(
    set_dir: pathlib.Path,
    out_set_dir: pathlib.Path,
    overwrite: bool,
    dry_run: bool,
    copy_sidecars: bool,
) -> None:
    flacs = sorted(set_dir.glob("*.flac"))
    if not flacs:
        return

    front = find_front_cover(set_dir)
    back = find_back_cover(set_dir, front)
    info_path = read_info_path(set_dir)
    info_text = info_path.read_text(errors="replace") if info_path else ""
    year, artist, album = parse_release_folder(set_dir.name)

    out_set_dir.mkdir(parents=True, exist_ok=True)

    print(f"\nSET:   {set_dir}")
    print(f"OUT:   {out_set_dir}")
    print(f"FRONT: {front.name if front else '(none)'}")
    print(f"BACK:  {back.name if back else '(none)'}")
    print(f"INFO:  {'yes' if info_text.strip() else 'no'} (Info.txt)")
    print(f"TAGS:  artist={artist or '(from tags/filename)'} | album={album or '(from tags/filename)'} | year={year or '(none)'}")
    print(f"FILES: {len(flacs)}  (ALAC 16/48 w dither)")

    # Sidecars
    if copy_sidecars and not dry_run:
        if info_path:
            copy_sidecar(info_path, out_set_dir / "00 - Info.txt", overwrite=overwrite)
        if front and front.exists():
            copy_sidecar(front, out_set_dir / f"00 - Front{front.suffix.lower()}", overwrite=overwrite)
        if back and back.exists():
            copy_sidecar(back, out_set_dir / f"00 - Back{back.suffix.lower()}", overwrite=overwrite)

    for flac in flacs:
        out_path = out_set_dir / (flac.stem + ".m4a")
        if out_path.exists() and not overwrite:
            print(f"  skip (exists): {out_path.name}")
            continue

        print(f"  convert: {flac.name} -> {out_path.name}")
        if dry_run:
            continue

        try:
            ffmpeg_convert(flac, out_path)
            write_custom_tags_and_artwork(out_path, info_text, year, artist, album, front, back)
        except Exception as e:
            print(f"  ERROR: failed on {flac.name}: {e}", file=sys.stderr)
            if out_path.exists():
                out_path.unlink()  # remove broken output so reruns work cleanly

# ---------------- main ----------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Batch convert FLAC archive sets to ALAC 16/48 with dither; embed Info.txt + front/back artwork; mirror folder structure."
    )
    ap.add_argument("src_root", help="Root directory containing many archive-set folders (recursive).")
    ap.add_argument("dest_root", help="Destination root directory for ALAC outputs.")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing .m4a outputs and sidecars.")
    ap.add_argument("--dry-run", action="store_true", help="Show what would happen without converting.")
    ap.add_argument("--max-depth", type=int, default=0, help="Limit traversal depth from src_root (0 = unlimited).")
    ap.add_argument("--no-sidecars", action="store_true", help="Do not copy Info/Front/Back sidecars into output folders.")
    args = ap.parse_args()

    src_root = pathlib.Path(args.src_root).expanduser().resolve()
    dest_root = pathlib.Path(args.dest_root).expanduser().resolve()

    if not src_root.is_dir():
        print(f"Not a directory: {src_root}", file=sys.stderr)
        return 2
    dest_root.mkdir(parents=True, exist_ok=True)

    print(f"SRC_ROOT:  {src_root}")
    print(f"DEST_ROOT: {dest_root}")
    print(f"DRY_RUN:   {args.dry_run}")
    print(f"OVERWRITE: {args.overwrite}")
    print(f"MAX_DEPTH: {args.max_depth if args.max_depth else 'unlimited'}")
    print(f"SIDECARS:  {'no' if args.no_sidecars else 'yes'}")
    print(f"GROUPING:  {GROUPING_VALUE}")
    print(f"SORTALBUM: {SORT_ALBUM_PREFIX} - <YEAR> - <ALBUM>")

    # Walk tree and find set folders
    src_root_parts = len(src_root.parts)
    set_folders: list[pathlib.Path] = []

    for folder in src_root.rglob("*"):
        if not folder.is_dir():
            continue
        if args.max_depth:
            depth = len(folder.parts) - src_root_parts
            if depth > args.max_depth:
                continue
        if is_set_folder(folder):
            set_folders.append(folder)

    if not set_folders:
        print("No set folders found (no directories containing *.flac).", file=sys.stderr)
        return 1

    print(f"\nFound {len(set_folders)} set folder(s).")

    for set_dir in sorted(set_folders):
        rel = set_dir.relative_to(src_root)
        out_set_dir = dest_root / rel
        process_set(
            set_dir=set_dir,
            out_set_dir=out_set_dir,
            overwrite=args.overwrite,
            dry_run=args.dry_run,
            copy_sidecars=(not args.no_sidecars),
        )

    print("\nDone.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())