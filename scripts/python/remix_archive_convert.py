#!/usr/bin/env python3
import argparse, pathlib, subprocess, sys
from mutagen.mp4 import MP4, MP4FreeForm

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_COMMENT = 250

def first_existing(paths):
    for p in paths:
        if p.exists():
            return p
    return None

def find_cover(folder: pathlib.Path) -> pathlib.Path | None:
    art = folder / "Artwork"
    candidates = []

    if art.is_dir():
        # Strong preferences
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

        # Otherwise: first image in Artwork/
        imgs = sorted([p for p in art.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS])
        if imgs:
            return imgs[0]

    # Fallback: look in main folder for common names
    for stem in ["folder", "front", "cover"]:
        for ext in IMAGE_EXTS:
            p = folder / f"{stem}{ext}"
            if p.exists():
                return p

    # Last fallback: any image in main folder
    imgs = sorted([p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS])
    return imgs[0] if imgs else None

def read_info(folder: pathlib.Path) -> str:
    # Case-insensitive lookup for Info.txt in main dir
    for p in folder.iterdir():
        if p.is_file() and p.name.casefold() == "info.txt":
            return p.read_text(errors="replace")
    return ""

def ffmpeg_convert(flac_path: pathlib.Path, out_path: pathlib.Path, cover: pathlib.Path | None):
    tmp_out = out_path.with_name(out_path.stem + ".tmp.m4a")

    af_soxr  = "aresample=48000:resampler=soxr:dither_method=triangular,aformat=sample_fmts=s16p"
    af_basic = "aresample=48000:dither_method=triangular,aformat=sample_fmts=s16p"

    def build_cmd(audio_filter: str) -> list[str]:
        cmd = ["ffmpeg", "-y", "-nostdin", "-hide_banner", "-loglevel", "error"]
        cmd += ["-i", str(flac_path)]

        if cover is not None:
            cmd += ["-i", str(cover)]
            cmd += [
                "-map", "0:a:0",
                "-map", "1:v:0",
                "-af", audio_filter,
                "-c:a", "alac",
                "-c:v", "mjpeg",
                "-disposition:v:0", "attached_pic",
                "-map_metadata", "0",
                "-movflags", "+faststart",
                "-f", "ipod",
                str(tmp_out),
            ]
        else:
            cmd += [
                "-map", "0:a:0",
                "-af", audio_filter,
                "-c:a", "alac",
                "-map_metadata", "0",
                "-movflags", "+faststart",
                "-f", "ipod",
                str(tmp_out),
            ]
        return cmd

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

def write_custom_tags(m4a_path: pathlib.Path, info_text: str):
    mp4 = MP4(str(m4a_path))
    if mp4.tags is None:
        mp4.add_tags()

    if info_text.strip():
        mp4.tags["----:com.apple.iTunes:INFOTXT"] = [MP4FreeForm(info_text.encode("utf-8"))]
        short = " ".join(info_text.strip().split())
        mp4.tags["\xa9cmt"] = [short[:MAX_COMMENT]]

    mp4.save()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src", help="Folder containing FLACs + Info.txt + Artwork/")
    ap.add_argument("--out", default="ALAC_OUT", help="Output folder name under src (default: ALAC_OUT)")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing m4a files")
    args = ap.parse_args()

    src = pathlib.Path(args.src).expanduser().resolve()
    if not src.is_dir():
        print(f"Not a directory: {src}", file=sys.stderr)
        sys.exit(2)

    out_dir = (src / args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    cover = find_cover(src)
    info_text = read_info(src)

    flacs = sorted([p for p in src.glob("*.flac")])
    if not flacs:
        print("No .flac files found.", file=sys.stderr)
        sys.exit(1)

    print(f"Source: {src}")
    print(f"Output: {out_dir}")
    print(f"Cover:  {cover.name if cover else '(none)'}")
    print(f"Info:   {'yes' if info_text.strip() else 'no'} (Info.txt)")
    print(f"Files:  {len(flacs)}")
    print("Target: ALAC 16-bit / 48 kHz")

    for p in flacs:
        out_path = out_dir / (p.stem + ".m4a")
        if out_path.exists() and not args.overwrite:
            print(f"Skip (exists): {out_path.name}")
            continue

        print(f"Convert: {p.name} -> {out_path.name}")
        try:
            ffmpeg_convert(p, out_path, cover)
            write_custom_tags(out_path, info_text)   # or your expanded version
        except Exception as e:
            print(f"ERROR: {p.name}: {e}", file=sys.stderr)
            if out_path.exists():
                out_path.unlink()

    print("Done.")

if __name__ == "__main__":
    main()