#!/usr/bin/env python3
"""
unify_music_dirs.py

Create a single "Unified" directory (one true copy) from two directories,
and quarantine the rest — from BOTH sides.

Key behavior:
- Groups by normalized (artist, title).
- Splits into "version clusters" by duration using --dur-cluster seconds.
  * If you set --dur-cluster 60, then differences <= 60s are treated as the same version
    (good for ignoring radio edits / small fade differences).
  * If there are clusters that differ by > dur-cluster, those are treated as distinct versions.
    The script will keep one "best" file per cluster in Unified and will write a conflicts report
    so you can review likely true remixes/alt versions.

Winner selection (within each duration cluster):
  lossless > longer duration > bitrate > sample rate > size

Install:
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install -U pip mutagen

Dry run:
  python unify_music_dirs.py "/path/to/keepers" "/path/to/possible"

Apply (copy best to Unified, move rest to Quarantine):
  python unify_music_dirs.py "/path/to/keepers" "/path/to/possible" --apply --move

Apply (copy best + copy rest; leaves originals untouched):
  python unify_music_dirs.py "/path/to/keepers" "/path/to/possible" --apply

Tuning:
  --dur-cluster 60            treat <=60s differences as same version (ignore radio edits)
  --ignore-mix-notes          ignore trailing (...) or [...] in titles for grouping
  --report unify_report.csv
  --conflicts-report duration_conflicts.csv   (reports groups that split into multiple clusters)
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
    origin: str               # "A" or "B"
    ext: str
    artist: str
    title: str
    album: str
    duration: Optional[float]
    bitrate: Optional[int]     # bits/sec
    sample_rate: Optional[int] # Hz
    size: int                  # bytes


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


def title_for_group(title: str, ignore_mix_notes: bool) -> str:
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


def read_meta(path: str, origin: str, ignore_mix_notes: bool) -> Optional[Meta]:
    ext = os.path.splitext(path)[1].lower()
    if ext not in AUDIO_EXTS:
        return None

    audio = MutagenFile(path)
    if audio is None:
        return None

    artist = ""
    title = ""
    album = ""
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
            title  = (tags.get("title") or tags.get("TITLE") or [""])[0]
            album  = (tags.get("album") or tags.get("ALBUM") or [""])[0]
        elif isinstance(audio, MP4):
            tags = audio.tags or {}
            artist = (tags.get("\xa9ART") or tags.get("aART") or [""])[0]
            title  = (tags.get("\xa9nam") or [""])[0]
            album  = (tags.get("\xa9alb") or [""])[0]
        else:
            if ext == ".mp3":
                try:
                    eid3 = EasyID3(path)
                    artist = (eid3.get("artist") or eid3.get("albumartist") or [""])[0]
                    title  = (eid3.get("title") or [""])[0]
                    album  = (eid3.get("album") or [""])[0]
                except Exception:
                    pass
    except Exception:
        pass

    artist = norm(str(artist))
    title  = norm(str(title))
    album  = norm(str(album))

    if not artist or not title:
        fa, ft = infer_artist_title_from_filename(path)
        artist = artist or fa
        title  = title or ft

    if not title:
        return None

    title = title_for_group(title, ignore_mix_notes)

    return Meta(
        path=path,
        origin=origin,
        ext=ext,
        artist=artist or "_Unknown",
        title=title,
        album=album,
        duration=float(duration) if duration is not None else None,
        bitrate=int(bitrate) if bitrate is not None else None,
        sample_rate=int(sample_rate) if sample_rate is not None else None,
        size=os.path.getsize(path),
    )


def iter_audio_files(root: str) -> List[str]:
    out: List[str] = []
    for base, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for fn in filenames:
            if os.path.splitext(fn)[1].lower() in AUDIO_EXTS:
                out.append(os.path.join(base, fn))
    return sorted(out)


def is_lossless(ext: str) -> bool:
    return ext == ".flac"


def quality_key(m: Meta) -> Tuple[int, int, int, int, int]:
    """
    Higher is better:
      lossless, duration_ms, bitrate, sample_rate, size
    """
    loss = 1 if is_lossless(m.ext) else 0
    dur = int((m.duration or 0.0) * 1000)
    br = m.bitrate or 0
    sr = m.sample_rate or 0
    sz = m.size
    return (loss, dur, br, sr, sz)


def cluster_by_duration(items: List[Meta], tol: float) -> List[List[Meta]]:
    """
    Cluster items into groups where durations are within tol seconds.
    If duration missing, treat as its own cluster.
    """
    with_dur = [m for m in items if m.duration is not None]
    no_dur   = [m for m in items if m.duration is None]

    with_dur.sort(key=lambda m: m.duration)  # type: ignore

    clusters: List[List[Meta]] = []
    current: List[Meta] = []

    for m in with_dur:
        if not current:
            current = [m]
            continue
        if abs(m.duration - current[-1].duration) <= tol:  # type: ignore
            current.append(m)
        else:
            clusters.append(current)
            current = [m]
    if current:
        clusters.append(current)

    for m in no_dur:
        clusters.append([m])

    return clusters


def copy_or_move(src: str, dst: str, move: bool) -> str:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    final = dst
    if os.path.exists(final):
        base, ext = os.path.splitext(final)
        n = 2
        while os.path.exists(f"{base} ({n}){ext}"):
            n += 1
        final = f"{base} ({n}){ext}"
    if move:
        shutil.move(src, final)
    else:
        shutil.copy2(src, final)
    return final


def fmt_range(cluster: List[Meta]) -> str:
    ds = [m.duration for m in cluster if m.duration is not None]
    if not ds:
        return "no-duration"
    return f"{min(ds):.2f}-{max(ds):.2f}s"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir_a", help="First directory (often keepers).")
    ap.add_argument("dir_b", help="Second directory (often possible dupes).")
    ap.add_argument("--apply", action="store_true", help="Perform copy/move; default is dry run.")
    ap.add_argument("--move", action="store_true", help="Move originals (dangerous); default copies.")
    ap.add_argument("--unified", default="Unified", help="Unified output folder (default: ./Unified)")
    ap.add_argument("--quarantine", default="Quarantine", help="Quarantine output folder (default: ./Quarantine)")
    ap.add_argument("--dur-cluster", type=float, default=2.0,
                    help="Cluster by duration within N seconds (default 2.0). Use 60 to ignore radio edits.")
    ap.add_argument("--ignore-mix-notes", action="store_true",
                    help="Ignore trailing (...) / [...] in titles for grouping")
    ap.add_argument("--report", default="unify_report.csv", help="CSV report filename")
    ap.add_argument("--conflicts-report", default="duration_conflicts.csv",
                    help="CSV listing artist/title groups that split into multiple duration clusters")
    args = ap.parse_args()

    dir_a = os.path.abspath(args.dir_a)
    dir_b = os.path.abspath(args.dir_b)
    unified_root = os.path.abspath(args.unified)
    quarantine_root = os.path.abspath(args.quarantine)

    if not os.path.isdir(dir_a):
        raise SystemExit(f"Not a directory: {dir_a}")
    if not os.path.isdir(dir_b):
        raise SystemExit(f"Not a directory: {dir_b}")

    metas: List[Meta] = []
    for p in iter_audio_files(dir_a):
        m = read_meta(p, "A", args.ignore_mix_notes)
        if m and m.title:
            metas.append(m)
    for p in iter_audio_files(dir_b):
        m = read_meta(p, "B", args.ignore_mix_notes)
        if m and m.title:
            metas.append(m)

    groups: Dict[Tuple[str, str], List[Meta]] = {}
    for m in metas:
        k = (norm_key(m.artist), norm_key(m.title))
        groups.setdefault(k, []).append(m)

    rows: List[List[object]] = []
    conflict_rows: List[List[object]] = []

    best_count = 0
    quarantined_count = 0
    conflict_groups = 0

    for (_ak, _tk), items in groups.items():
        if not items:
            continue

        clusters = cluster_by_duration(items, args.dur_cluster)

        if len(clusters) > 1:
            conflict_groups += 1
            summaries = []
            for idx, c in enumerate(clusters, start=1):
                summaries.append(f"C{idx}:{len(c)}@{fmt_range(c)}")
            conflict_rows.append([
                items[0].artist,
                items[0].title,
                len(items),
                len(clusters),
                args.dur_cluster,
                " | ".join(summaries),
            ])

        for cluster_idx, cluster in enumerate(clusters, start=1):
            if not cluster:
                continue

            cluster_sorted = sorted(cluster, key=quality_key, reverse=True)
            best = cluster_sorted[0]
            losers = cluster_sorted[1:]

            artist_dir = safe_name(best.artist, "_UnknownArtist")
            title_dir  = safe_name(best.title, "_UnknownTitle")

            best_name = os.path.basename(best.path)
            best_dest = os.path.join(unified_root, artist_dir, best_name)

            action_best = "WOULD_COPY"
            action_loser = "WOULD_COPY"

            cluster_range = fmt_range(cluster)

            if args.apply:
                final_best = copy_or_move(best.path, best_dest, move=False)
                action_best = "COPIED"
            else:
                final_best = best_dest

            best_count += 1

            for m in losers:
                qdir = os.path.join(quarantine_root, artist_dir, title_dir)
                qdest = os.path.join(qdir, os.path.basename(m.path))

                if args.apply:
                    final_q = copy_or_move(m.path, qdest, move=args.move)
                    action_loser = "MOVED" if args.move else "COPIED"
                else:
                    final_q = qdest
                    action_loser = "WOULD_MOVE" if args.move else "WOULD_COPY"
                quarantined_count += 1

                rows.append([
                    best.artist, best.title,
                    cluster_idx, cluster_range,
                    best.origin, best.ext, best.bitrate or "", best.sample_rate or "", f"{best.duration:.2f}" if best.duration else "", best.size,
                    m.origin, m.ext, m.bitrate or "", m.sample_rate or "", f"{m.duration:.2f}" if m.duration else "", m.size,
                    best.path, final_best, action_best,
                    m.path, final_q, action_loser,
                ])

    with open(args.report, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "artist","title",
            "cluster_id","cluster_range",
            "best_origin","best_ext","best_bitrate","best_samplerate","best_duration","best_size",
            "loser_origin","loser_ext","loser_bitrate","loser_samplerate","loser_duration","loser_size",
            "best_src_path","best_unified_path","best_action",
            "loser_src_path","loser_quarantine_path","loser_action"
        ])
        w.writerows(rows)

    with open(args.conflicts_report, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["artist", "title", "total_files", "cluster_count", "dur_cluster_seconds", "clusters"])
        w.writerows(conflict_rows)

    print(f"Scanned total tracks: {len(metas)}")
    print(f"Unified copies {'created' if args.apply else 'would be created'}: {best_count}")
    print(f"Quarantined files {'moved/copied' if args.apply else 'would be moved/copied'}: {quarantined_count}")
    print(f"Unified folder: {unified_root}")
    print(f"Quarantine folder: {quarantine_root}")
    print(f"Report: {os.path.abspath(args.report)}")
    print(f"Conflicts report: {os.path.abspath(args.conflicts_report)}")
    print(f"Version-conflict groups (clusters > 1): {conflict_groups}")

    if not args.apply:
        print("\nDry run only. Re-run with --apply to copy best + quarantine losers.")
        print("Tip: use --dur-cluster 60 to ignore radio edits but flag true remixes (>60s) in conflicts report.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())