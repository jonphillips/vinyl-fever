#!/usr/bin/env python3
"""
opus_to_aac.py

Recursively convert .opus files to AAC .m4a (Apple-friendly).
Default: AAC 256 kbps (CBR target), copy metadata when possible.

Dry run:
  python opus_to_aac.py "/path/to/in" --dry-run

Convert into ./AAC_OUT next to the input folder:
  python opus_to_aac.py "/path/to/in"

Specify output folder:
  python opus_to_aac.py "/path/to/in" --out "/path/to/out"

Overwrite existing outputs:
  python opus_to_aac.py "/path/to/in" --overwrite
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys


def iter_opus_files(root: pathlib.Path) -> list[pathlib.Path]:
    out: list[pathlib.Path] = []
    for p in root.rglob("*.opus"):
        if p.is_file() and not any(part.startswith(".") for part in p.parts):
            out.append(p)
    return sorted(out)


def run_ffmpeg(src: pathlib.Path, dst: pathlib.Path, overwrite: bool) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)

    # Use a temp output for atomic-ish behavior.
    tmp = dst.with_name(dst.stem + ".tmp.m4a")
    if tmp.exists():
        tmp.unlink()

    cmd = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error"]
    if overwrite:
        cmd.insert(1, "-y")
    else:
        cmd.insert(1, "-n")

    cmd += [
        "-i", str(src),
        # AAC in M4A container
        "-c:a", "aac",
        "-b:a", "256k",
        # Try to carry over tags if present
        "-map_metadata", "0",
        # Better playback start
        "-movflags", "+faststart",
        str(tmp),
    ]

    subprocess.check_call(cmd)

    # Sanity check: file exists & non-trivial size
    if not tmp.exists() or tmp.stat().st_size < 1024:
        raise RuntimeError(f"Conversion produced an invalid file: {tmp}")

    # If final exists and overwrite=False, ffmpeg would have refused earlier.
    if dst.exists():
        dst.unlink()
    tmp.replace(dst)


def main() -> int:
    ap = argparse.ArgumentParser(description="Batch convert .opus to AAC .m4a (256k) recursively.")
    ap.add_argument("in_root", help="Input folder (recursively scanned for *.opus).")
    ap.add_argument("--out", default="", help="Output root folder (default: <in_root>/AAC_OUT).")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing outputs.")
    ap.add_argument("--dry-run", action="store_true", help="Print what would happen without converting.")
    args = ap.parse_args()

    in_root = pathlib.Path(args.in_root).expanduser().resolve()
    if not in_root.is_dir():
        print(f"Not a directory: {in_root}", file=sys.stderr)
        return 2

    out_root = pathlib.Path(args.out).expanduser().resolve() if args.out else (in_root / "AAC_OUT")

    files = iter_opus_files(in_root)
    if not files:
        print("No .opus files found.")
        return 1

    print(f"IN:   {in_root}")
    print(f"OUT:  {out_root}")
    print(f"DRY:  {args.dry_run}")
    print(f"OVR:  {args.overwrite}")
    print(f"FOUND {len(files)} file(s)\n")

    ok = 0
    failed = 0
    skipped = 0

    for src in files:
        rel = src.relative_to(in_root)
        dst = (out_root / rel).with_suffix(".m4a")

        if dst.exists() and not args.overwrite:
            print(f"skip (exists): {rel}")
            skipped += 1
            continue

        print(f"convert: {rel} -> {dst.relative_to(out_root)}")
        if args.dry_run:
            ok += 1
            continue

        try:
            run_ffmpeg(src, dst, overwrite=args.overwrite)
            ok += 1
        except subprocess.CalledProcessError as e:
            failed += 1
            print(f"  ERROR: ffmpeg failed ({e.returncode}) on {rel}", file=sys.stderr)
            # remove partial output if any
            if dst.exists():
                try:
                    dst.unlink()
                except Exception:
                    pass
        except Exception as e:
            failed += 1
            print(f"  ERROR: {e} on {rel}", file=sys.stderr)
            if dst.exists():
                try:
                    dst.unlink()
                except Exception:
                    pass

    print("\nDone.")
    print(f"Converted: {ok}")
    print(f"Skipped:   {skipped}")
    print(f"Failed:    {failed}")
    return 0 if failed == 0 else 3


if __name__ == "__main__":
    raise SystemExit(main())