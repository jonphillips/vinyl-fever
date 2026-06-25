#!/usr/bin/env python3
"""
rule_scrub_tags.py

------------------------------------------------------------------------------
rule_scrub_tags.py — Rule-based metadata scrubber for audio files
------------------------------------------------------------------------------

Purpose
- Deterministic, rule-based cleanup of tags in audio files.
- No internet lookups, no consensus databases, no “smart guessing”.
- Default is DRY-RUN. Use --write to apply changes.
- Produces an optional CSV report listing every change and which rules fired.

Supported formats / tagging backends
- MP3: ID3 via mutagen.easyid3 (EasyID3)
- M4A/MP4/ALAC: MP4 atoms via mutagen.mp4 (MP4)
- FLAC: Vorbis comments + pictures via mutagen.flac (FLAC)

Install (recommended: venv)
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install -U pip mutagen

Quick start
  # DRY-RUN: scrub titles only (default)
  python rule_scrub_tags.py "/path/to/music"

  # DRY-RUN: show fewer progress messages
  python rule_scrub_tags.py "/path/to/music" --quiet

  # Apply changes + write a report
  python rule_scrub_tags.py "/path/to/music" --write --report scrub_report.csv

  # Scrub multiple fields (comma-separated)
  python rule_scrub_tags.py "/path/to/music" --write --fields title,artist,album,albumartist

  # Only spacing/punctuation normalization (no title-casing)
  python rule_scrub_tags.py "/path/to/music" --write --no-titlecase

Scope / philosophy
- “Rule-based” means: only transform what we can justify mechanically.
- If a tag is empty, we do not invent a value.
- We do not rely on Apple Music / Music.app metadata; we edit the files’ tags.

What it cleans (high level)
1) Unicode + whitespace
   - Normalize to NFC.
   - Trim and collapse repeated spaces/tabs.

2) Common mojibake cleanup
   - Fixes certain frequent broken characters from copy/paste.

3) Setlist separators (segues)
   - Normalizes segues to:  "Song A > Song B > Song C"
   - Treats ">" and "->" as *boundaries between song titles*.
   - Ensures the first word after a segue is treated like a title-start word
     (so it won’t incorrectly lowercase “The”, “A”, “An”, etc.).

4) Title casing (smart_title_case) — deterministic rules
   - Lowercases “small words” (a, an, the, and, of, …) EXCEPT:
       * at the start/end of a song title segment
       * after boundary tokens: ">", "/", "("
   - Preserves acronyms / initialisms / dotted acronyms:
       * U.S.A. stays U.S.A.
       * R.E.M. stays R.E.M.
       * FM / SBD / DSBD stays uppercase
   - Preserves internal-caps words (e.g., iZotope).
   - Fixes apostrophe behavior:
       * does NOT treat apostrophes as word boundaries
         (prevents Devil'S / Don'T artifacts).
   - Keeps "w" (with) as lowercase when used as a standalone token:
       * "(w Bob Weir)" should remain "(w Bob Weir)"
       * avoids turning it into "(W Bob Weir)"

5) Trailing garbage cleanup
   - Removes accidental trailing " -" or stray punctuation that often appears
     after filename sanitization or malformed setlists.

Numeric prefixes in titles (optional rule, if enabled)
- Some track titles include leading numbers as literal text:
    "06 Light of Day"
    "114 - Born in the U.S.A."
    "305 - Detroit Medley (...)"
- In many libraries, these numbers are redundant because the file already has
  a track number tag. When enabled, we can:
    * remove common numeric prefixes from TITLE (but do NOT change TRACKNUMBER)
    * optionally detect 101/201-style prefixes (disc/track encoding):
        101 = Disc 1 Track 1
        201 = Disc 2 Track 1
      and optionally propose updating DISCNUMBER/TRACKNUMBER tags (if desired).
  NOTE: this is a policy choice; by default we avoid modifying numbering tags.

Apple Music / Music.app note
- Editing tags on files that are already in Music.app generally works, but Music.app
  may cache or re-read metadata depending on file type and settings.
- This tool edits the files on disk. If Music.app shows stale data, you may need to:
    * quit/reopen Music, or
    * “Get Info” refresh, or
    * remove/re-add files (last resort).

Safety
- Start with DRY-RUN (no --write) and inspect the preview.
- Keep backups (especially if targeting your main library).
------------------------------------------------------------------------------
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import unicodedata
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple
import sys
import datetime

from mutagen import File as MutagenFile
from mutagen.flac import FLAC
from mutagen.mp4 import MP4
from mutagen.easyid3 import EasyID3


AUDIO_EXTS = {".flac", ".mp3", ".m4a", ".mp4"}

SMALL_WORDS = {
    "a", "an", "and", "as", "at", "but", "by",
    "for", "from", "in", "into", "of", "on", "onto",
    "or", "over", "per", "the", "to", "up", "vs", "v", "via", "with", "without",
    "w",  # setlist shorthand for "with"
}

# Setlist annotations that should always stay lowercase
SETLIST_NOTES = {
    "intro", "introduction", 
    "talk", "talking", "chatter",
    "encore", "applause", "radio", "host",
    "band",
    "jam", "jams", 
    "medley", "medleys",
    "outro", "crowd", "introductions", "thank", "yous",
    "interlude", 
    "fade", "fades", "fade-out",
    "radio", "prep",
    "tease", "teases",
    "segue", "segues",
    "cut", "cuts",
    "acoustic",
    "acapella", "a cappella",
    "solo", "solos", "talks", "break"
}

INTERNAL_CAPS_RE = re.compile(r"[a-z].*[A-Z]|[A-Z].*[a-z].*[A-Z]")
DOTTED_ACRONYM_RE = re.compile(r"^(?:[A-Za-z]\.){2,}[A-Za-z]?\.?$")

KEEP_AS_IS_RE = re.compile(
    r"(^\d+$)|"
    r"(^[A-Z]{2,}\.?$)|"
    r"(^[IVXLCDM]+$)"
)

MOJIBAKE_SUBS = [
    (re.compile(r"¥"), "'"),
    (re.compile(r""), "-"),
    (re.compile(r""), "-"),
]


@dataclass
class Change:
    path: str
    field: str
    old: str
    new: str
    rules: str


def nfc(s: str) -> str:
    return unicodedata.normalize("NFC", s)


def collapse_ws(s: str) -> str:
    return re.sub(r"[ \t]+", " ", s)


def normalize_separators(s: str) -> str:
    out = s
    out = re.sub(r"\s*-\s*>\s*", " > ", out)  # "->", "- >"
    out = re.sub(r"\s*→\s*", " > ", out)
    out = re.sub(r"\s*⇒\s*", " > ", out)
    out = re.sub(r"\s*>\s*", " > ", out)
    out = re.sub(r"\s*/\s*", " / ", out)
    out = re.sub(r"\s+-\s+", " - ", out)
    return collapse_ws(out).strip()


def strip_trailing_garbage(s: str) -> Tuple[str, List[str]]:
    rules: List[str] = []
    out = s

    if re.search(r"\s+-\s*$", out):
        out = re.sub(r"\s+-\s*$", "", out)
        rules.append("drop_trailing_dash")
    elif out.endswith("-"):
        out = out[:-1].rstrip()
        rules.append("drop_trailing_dash")

    if re.search(r"\s+[.,;:]+$", out):
        out2 = re.sub(r"\s+[.,;:]+$", "", out).rstrip()
        if out2 != out:
            out = out2
            rules.append("drop_trailing_punct")

    return out, rules


def parse_slash_number(s: str) -> Tuple[Optional[int], Optional[int]]:
    if not s:
        return None, None
    t = s.strip()
    m = re.match(r"^\s*(\d{1,4})\s*(?:/\s*(\d{1,4}))?\s*$", t)
    if m:
        return int(m.group(1)), (int(m.group(2)) if m.group(2) else None)
    m = re.match(r"^\s*(\d{1,4})\s+of\s+(\d{1,4})\s*$", t, re.IGNORECASE)
    if m:
        return int(m.group(1)), int(m.group(2))
    return None, None


def fmt_slash_number(n: Optional[int], tot: Optional[int]) -> str:
    if n is None:
        return ""
    if tot is not None and tot > 0:
        return f"{n}/{tot}"
    return str(n)


def leading_disc_track_prefix(title: str) -> Tuple[Optional[int], Optional[int], Optional[str]]:
    """
    Recognize 3-digit disc-track prefixes:
      101 = disc 1 track 1
      214 = disc 2 track 14
    Requires a separator after the number: space OR punctuation+space.
    Avoids disc-track forms like "2-1." by design (not 3 digits).
    """
    s = title.strip()
    m = re.match(r"^\s*(\d{3})\s*(?:[._)\]]|\s*-\s*)?\s+(.*\S)\s*$", s)
    if not m:
        return None, None, None
    n = int(m.group(1))
    disc = n // 100
    track = n % 100
    rest = m.group(2)
    return disc, track, rest


def leading_track_prefix(title: str) -> Tuple[Optional[int], Optional[str]]:
    s = title.strip()
    if re.match(r"^\d{1,3}-\d{1,3}\b", s):  # avoid "2-1."
        return None, None
    m = re.match(r"^\s*(\d{1,3})\s*(?:[._)\]]|\s*-\s*)?\s+(.*\S)\s*$", s)
    if not m:
        return None, None
    return int(m.group(1)), m.group(2)


def smart_title_case(s: str) -> Tuple[str, List[str]]:
    rules: List[str] = []
    original = s

    SEP_RE = r"(\s+|/|>|-|\(|\)|\[|\]|:)"
    tokens = re.split(SEP_RE, s)

    def is_sep(t: str) -> bool:
        return bool(t) and re.fullmatch(SEP_RE, t) is not None

    def has_alpha(t: str) -> bool:
        return bool(re.search(r"[A-Za-z]", t))

    def normalize_dotted_acronym(core: str) -> str:
        return re.sub(r"[a-z]", lambda m: m.group(0).upper(), core)

    def cap_word(w: str) -> str:
        if not w:
            return w
        if INTERNAL_CAPS_RE.search(w):
            return w

        m = re.match(r"^([^A-Za-z0-9]*)(.*?)([^A-Za-z0-9]*)$", w)
        lead, core, trail = m.group(1), m.group(2), m.group(3)
        if not core:
            return w

        if DOTTED_ACRONYM_RE.match(core):
            return lead + normalize_dotted_acronym(core) + trail

        stripped = core.strip(".")
        # only preserve as-is if the word is already uppercase/roman numeral/digit
        if KEEP_AS_IS_RE.match(stripped):
            return lead + core + trail

        m2 = re.match(r"^(.*?)([A-Za-z])(.*)$", core)
        if not m2:
            return lead + core + trail
        pre, first, rest = m2.group(1), m2.group(2), m2.group(3)
        core2 = pre + first.upper() + rest.lower()

        m3 = re.match(r"^([ODL])'([a-z])", core2)
        if m3:
            core2 = m3.group(1) + "'" + m3.group(2).upper() + core2[3:]

        return lead + core2 + trail

    SEG_BOUNDARIES = {">", "/"}
    alpha_indices = [i for i, t in enumerate(tokens) if t and (not is_sep(t)) and has_alpha(t)]

    seg_id = 0
    token_seg: Dict[int, int] = {}
    for i, t in enumerate(tokens):
        if not t:
            continue
        if is_sep(t):
            if not re.fullmatch(r"\s+", t) and t in SEG_BOUNDARIES:
                seg_id += 1
            continue
        token_seg[i] = seg_id

    seg_first: Dict[int, int] = {}
    seg_last: Dict[int, int] = {}
    for i in alpha_indices:
        sid = token_seg.get(i, 0)
        seg_first.setdefault(sid, i)
        seg_last[sid] = i

    # Track tokens inside parentheses; preserve their case
    in_parens = False
    protected_tokens: set = set()
    for i, t in enumerate(tokens):
        if is_sep(t):
            if t == "(":
                in_parens = True
            elif t == ")":
                in_parens = False
        elif in_parens:
            protected_tokens.add(i)

    for i, t in enumerate(tokens):
        if not t or is_sep(t):
            continue
        core = t.strip()
        lowered = core.lower()
        sid = token_seg.get(i, 0)
        first_alpha_i = seg_first.get(sid)
        last_alpha_i = seg_last.get(sid)

        # Skip capitalization for words inside parentheses
        if i in protected_tokens:
            continue

        # Handle setlist annotations specially. Recognize annotations even
        # when a leading dash is present (e.g. "- talk"). If the annotation
        # word is already lowercase, preserve that lowercase. Do NOT force
        # lowercase when the word is capitalized (may be part of a real title).
        # strip leading dashes/spaces and surrounding punctuation for recognition
        core_nomdash = re.sub(r"^[\-\s]+", "", core)
        # remove non-word chars at start/end to get the bare word for lookup
        core_nomdash_clean = re.sub(r"^[^\w]+|[^\w]+$", "", core_nomdash)
        if core_nomdash_clean.lower() in SETLIST_NOTES:
            if core_nomdash_clean == core_nomdash_clean.lower():
                # lowercase the matched bare word only (preserve punctuation)
                tokens[i] = re.sub(re.escape(core_nomdash_clean), core_nomdash_clean.lower(), core, count=1)
            else:
                tokens[i] = core
            continue

        if (has_alpha(core)
            and i != first_alpha_i
            and i != last_alpha_i
            and lowered in SMALL_WORDS
            and not INTERNAL_CAPS_RE.search(core)
            and not DOTTED_ACRONYM_RE.match(core)):
            tokens[i] = lowered
        else:
            tokens[i] = cap_word(core)

    out = "".join(tokens)
    if out != original:
        rules.append("smart_title_case")
    return out, rules


def scrub_text(s: str, do_title_case: bool = True) -> Tuple[str, List[str]]:
    rules: List[str] = []
    out = s
    # optionally convert trailing dash-date forms like " - 19841119" or " - 1984-11-19"
    # to a parenthesized ISO date: " (1984-11-19)". This is a lightweight, local
    # reformatting that runs before title-casing.
    def convert_trailing_date(t: str) -> Tuple[str, Optional[str]]:
        m = re.search(r"\s*-\s*(\d{4})-(\d{2})-(\d{2})\s*$", t)
        if not m:
            m2 = re.search(r"\s*-\s*(\d{4})(\d{2})(\d{2})\s*$", t)
            if not m2:
                return t, None
            y, mo, da = int(m2.group(1)), int(m2.group(2)), int(m2.group(3))
        else:
            y, mo, da = int(m.group(1)), int(m.group(2)), int(m.group(3))
        # validate/construct date and format as 'Month D, YYYY'
        try:
            dt = datetime.date(y, mo, da)
        except Exception:
            return t, None
        pretty = f"{dt.strftime('%B')} {dt.day}, {dt.year}"
        # remove the trailing dash+date and append parenthesized pretty date
        new = re.sub(r"\s*-\s*(?:\d{4}-?\d{2}-?\d{2})\s*$", "", t).rstrip()
        return f"{new} ({pretty})", "trailing_date_paren"

    out2 = nfc(out)
    if out2 != out:
        out = out2
        rules.append("unicode_nfc")

    for pat, rep in MOJIBAKE_SUBS:
        out2 = pat.sub(rep, out)
        if out2 != out:
            out = out2
            rules.append("mojibake_sub")

    out2 = out.strip()
    if out2 != out:
        out = out2
        rules.append("strip")

    out2 = collapse_ws(out)
    if out2 != out:
        out = out2
        rules.append("collapse_ws")

    out2 = normalize_separators(out)
    if out2 != out:
        out = out2
        rules.append("normalize_separators")

    # convert trailing date formats if requested via CLI (in main we will pass
    # a flag to enable this by calling convert here). We set a sentinel attribute
    # on the function object so main can toggle; default is False.
    if getattr(scrub_text, "convert_trailing_date_enabled", False):
        out2, rtag = convert_trailing_date(out)
        if rtag and out2 != out:
            out = out2
            rules.append(rtag)

    out2, r2 = strip_trailing_garbage(out)
    if out2 != out:
        out = out2
        rules.extend(r2)

    if do_title_case:
        out2, r3 = smart_title_case(out)
        if out2 != out:
            out = out2
            rules.extend(r3)

    return out, rules


FIELD_MAP = {
    "title": ("TITLE",),
    "artist": ("ARTIST",),
    "album": ("ALBUM",),
    "albumartist": ("ALBUMARTIST",),
    "tracknumber": ("TRACKNUMBER",),
    "discnumber": ("DISCNUMBER",),
}


def read_tags(path: str) -> Tuple[Optional[str], Dict[str, str]]:
    ext = os.path.splitext(path)[1].lower()

    if ext in {".m4a", ".mp4"}:
        try:
            audio = MP4(path)
        except Exception as e:
            print(f"Warning: failed to read MP4 tags for {path}: {e}", file=sys.stderr)
            return None, {}
        tags: Dict[str, str] = {}

        def get_atom(atom: str) -> Optional[str]:
            v = audio.tags.get(atom) if audio.tags else None
            if not v:
                return None
            if isinstance(v, list) and v:
                return str(v[0])
            return str(v)

        trk = ""
        if audio.tags and "trkn" in audio.tags and audio.tags["trkn"]:
            t0 = audio.tags["trkn"][0]
            if isinstance(t0, (tuple, list)) and len(t0) >= 1:
                track = t0[0] if t0[0] else None
                total = t0[1] if len(t0) > 1 and t0[1] else None
                if track:
                    trk = fmt_slash_number(int(track), int(total) if total else None)

        dsk = ""
        if audio.tags and "disk" in audio.tags and audio.tags["disk"]:
            d0 = audio.tags["disk"][0]
            if isinstance(d0, (tuple, list)) and len(d0) >= 1:
                disc = d0[0] if d0[0] else None
                total = d0[1] if len(d0) > 1 and d0[1] else None
                if disc:
                    dsk = fmt_slash_number(int(disc), int(total) if total else None)

        tags["title"] = get_atom("\xa9nam") or ""
        tags["artist"] = get_atom("\xa9ART") or ""
        tags["album"] = get_atom("\xa9alb") or ""
        tags["albumartist"] = get_atom("aART") or ""
        tags["tracknumber"] = trk
        tags["discnumber"] = dsk
        return "mp4", tags

    if ext == ".mp3":
        try:
            audio = EasyID3(path)
        except Exception as e:
            print(f"Warning: failed to read MP3/ID3 tags for {path}: {e}", file=sys.stderr)
            return None, {}
        tags = {
            "title": (audio.get("title", [""])[0] if audio.get("title") else ""),
            "artist": (audio.get("artist", [""])[0] if audio.get("artist") else ""),
            "album": (audio.get("album", [""])[0] if audio.get("album") else ""),
            "albumartist": (audio.get("albumartist", [""])[0] if audio.get("albumartist") else ""),
            "tracknumber": (audio.get("tracknumber", [""])[0] if audio.get("tracknumber") else ""),
            "discnumber": (audio.get("discnumber", [""])[0] if audio.get("discnumber") else ""),
        }
        return "mp3", tags

    if ext == ".flac":
        try:
            audio = FLAC(path)
        except Exception as e:
            print(f"Warning: failed to read FLAC tags for {path}: {e}", file=sys.stderr)
            return None, {}
        tags = {
            "title": (audio.get("TITLE", [""])[0] if audio.get("TITLE") else ""),
            "artist": (audio.get("ARTIST", [""])[0] if audio.get("ARTIST") else ""),
            "album": (audio.get("ALBUM", [""])[0] if audio.get("ALBUM") else ""),
            "albumartist": (audio.get("ALBUMARTIST", [""])[0] if audio.get("ALBUMARTIST") else ""),
            "tracknumber": (audio.get("TRACKNUMBER", [""])[0] if audio.get("TRACKNUMBER") else ""),
            "discnumber": (audio.get("DISCNUMBER", [""])[0] if audio.get("DISCNUMBER") else ""),
        }
        return "flac", tags

    return None, {}


def write_tag(kind: str, path: str, field: str, value: str) -> None:
    ext = os.path.splitext(path)[1].lower()

    if kind == "mp4" and ext in {".m4a", ".mp4"}:
        try:
            audio = MP4(path)
        except Exception as e:
            print(f"Warning: failed to open MP4 for writing {path}: {e}", file=sys.stderr)
            return
        if audio.tags is None:
            audio.add_tags()

        if field == "title":
            audio.tags["\xa9nam"] = [value]
        elif field == "artist":
            audio.tags["\xa9ART"] = [value]
        elif field == "album":
            audio.tags["\xa9alb"] = [value]
        elif field == "albumartist":
            audio.tags["aART"] = [value]
        elif field == "tracknumber":
            tr, tot = parse_slash_number(value)
            existing_tot = None
            if audio.tags and "trkn" in audio.tags and audio.tags["trkn"]:
                t0 = audio.tags["trkn"][0]
                if isinstance(t0, (tuple, list)) and len(t0) > 1 and t0[1]:
                    existing_tot = int(t0[1])
            if tr is None:
                if "trkn" in audio.tags:
                    del audio.tags["trkn"]
            else:
                total_to_write = tot if tot is not None else (existing_tot if existing_tot is not None else 0)
                audio.tags["trkn"] = [(int(tr), int(total_to_write))]
        elif field == "discnumber":
            dn, tot = parse_slash_number(value)
            existing_tot = None
            if audio.tags and "disk" in audio.tags and audio.tags["disk"]:
                d0 = audio.tags["disk"][0]
                if isinstance(d0, (tuple, list)) and len(d0) > 1 and d0[1]:
                    existing_tot = int(d0[1])
            if dn is None:
                if "disk" in audio.tags:
                    del audio.tags["disk"]
            else:
                total_to_write = tot if tot is not None else (existing_tot if existing_tot is not None else 0)
                audio.tags["disk"] = [(int(dn), int(total_to_write))]

        try:
            audio.save()
        except Exception as e:
            print(f"Warning: failed to save MP4 tags for {path}: {e}", file=sys.stderr)
        return

    if kind == "mp3" and ext == ".mp3":
        try:
            audio = EasyID3(path)
        except Exception as e:
            print(f"Warning: failed to open MP3/ID3 for writing {path}: {e}", file=sys.stderr)
            return

        if field in {"tracknumber", "discnumber"}:
            old = audio.get(field, [""])[0] if audio.get(field) else ""
            old_n, old_tot = parse_slash_number(old)
            new_n, new_tot = parse_slash_number(value)
            if new_n is None:
                if field in audio:
                    del audio[field]
            else:
                tot = new_tot if new_tot is not None else old_tot
                audio[field] = [fmt_slash_number(new_n, tot)]
        else:
            audio[field] = [value]

        try:
            audio.save()
        except Exception as e:
            print(f"Warning: failed to save MP3 tags for {path}: {e}", file=sys.stderr)
        return

    if kind == "flac" and ext == ".flac":
        try:
            audio = FLAC(path)
        except Exception as e:
            print(f"Warning: failed to open FLAC for writing {path}: {e}", file=sys.stderr)
            return
        key = field.upper()
        if field == "albumartist":
            key = "ALBUMARTIST"
        if value == "":
            if key in audio:
                del audio[key]
        else:
            # Vorbis/FLAC tags expect lists of strings
            audio[key] = [value]
        try:
            audio.save()
        except Exception as e:
            print(f"Warning: failed to save FLAC tags for {path}: {e}", file=sys.stderr)
        return

    try:
        audio = MutagenFile(path, easy=True)
    except Exception as e:
        print(f"Warning: failed to open file for generic writing {path}: {e}", file=sys.stderr)
        return
    if audio is None:
        print(f"Warning: Unsupported file for writing: {path}", file=sys.stderr)
        return
    # ensure easy-format values are lists
    try:
        audio[field] = [value]
        audio.save()
    except Exception as e:
        print(f"Warning: failed to save generic tags for {path}: {e}", file=sys.stderr)


def iter_audio_files(root: str) -> List[str]:
    out: List[str] = []
    for base, _, files in os.walk(root):
        for fn in files:
            ext = os.path.splitext(fn)[1].lower()
            if ext in AUDIO_EXTS:
                out.append(os.path.join(base, fn))
    return sorted(out)


def parse_fields(s: str) -> List[str]:
    fields = [x.strip().lower() for x in s.split(",") if x.strip()]
    for f in fields:
        if f not in FIELD_MAP:
            raise ValueError("Unknown field: %s. Allowed: title,artist,album,albumartist,tracknumber,discnumber" % f)
    return fields


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", help="Root folder to scan (recursive).")
    ap.add_argument("--write", action="store_true", help="Actually write changes (default is dry-run).")
    ap.add_argument("--fields", default="title",
                    help="Comma-separated: title,artist,album,albumartist,tracknumber,discnumber (default: title)")
    ap.add_argument("--no-titlecase", action="store_true",
                    help="Disable smart title-casing; keep only spacing/punct rules.")
    ap.add_argument("--trailing-date", action="store_true",
                    help="Convert trailing ' - YYYYMMDD' or ' - YYYY-MM-DD' to ' (YYYY-MM-DD)'.")
    ap.add_argument("--report", default="", help="Write CSV report of changes.")
    ap.add_argument("--quiet", action="store_true", help="Less console output.")

    ap.add_argument("--fix-leading-tracknums", choices=["off", "strip", "promote"], default="off",
                    help=("Handle titles like '06 Light of Day'. "
                          "'strip' removes prefix ONLY if tracknumber tag exists; "
                          "'promote' sets tracknumber tag if missing, then strips. Default: off"))
    ap.add_argument("--max-prefix-tracknum", type=int, default=60,
                    help="Safety: only treat leading title numbers <= this as track prefixes (default: 60).")

    ap.add_argument("--fix-leading-disc-tracknums", choices=["off", "strip", "promote"], default="off",
                    help=("Handle titles like '101 Foo' meaning Disc 1 Track 1. "
                          "'strip' removes ONLY if disc/track tags exist; "
                          "'promote' sets DISCNUMBER/TRACKNUMBER if missing, then strips. Default: off"))
    ap.add_argument("--max-discnum", type=int, default=9,
                    help="Safety: only treat disc numbers <= this (default: 9).")
    ap.add_argument("--max-disc-tracknum", type=int, default=60,
                    help="Safety: only treat disc-track track <= this (default: 60).")

    args = ap.parse_args()

    root = os.path.abspath(args.root)
    fields = parse_fields(args.fields)
    do_title_case = not args.no_titlecase

    files = iter_audio_files(root)
    if not files:
        print("No audio files found.")
        return 1

    changes: List[Change] = []
    touched_files = set()

    for idx, path in enumerate(files, start=1):
        kind, tags = read_tags(path)
        if kind is None:
            continue

        # 1) Disc-track prefixes (101/201) if enabled
        if args.fix_leading_disc_tracknums != "off":
            title = tags.get("title", "") or ""
            if title:
                disc, track, rest = leading_disc_track_prefix(title)
                if (disc is not None and track is not None and rest is not None
                        and 1 <= disc <= args.max_discnum
                        and 1 <= track <= args.max_disc_tracknum):

                    existing_tr, _ = parse_slash_number(tags.get("tracknumber", "") or "")
                    existing_dn, _ = parse_slash_number(tags.get("discnumber", "") or "")

                    if args.fix_leading_disc_tracknums == "strip":
                        if existing_tr is not None or existing_dn is not None:
                            changes.append(Change(path, "title", title, rest, "leading_disc_track_strip"))
                            if args.write:
                                write_tag(kind, path, "title", rest)
                                touched_files.add(path)
                            tags["title"] = rest

                    elif args.fix_leading_disc_tracknums == "promote":
                        # Set missing discnumber/tracknumber only (never overwrite non-matching values)
                        if existing_dn is None:
                            changes.append(Change(path, "discnumber", tags.get("discnumber", "") or "", str(disc),
                                                  "leading_disc_track_promote_disc"))
                            if args.write:
                                write_tag(kind, path, "discnumber", str(disc))
                                touched_files.add(path)
                            tags["discnumber"] = str(disc)

                        if existing_tr is None:
                            changes.append(Change(path, "tracknumber", tags.get("tracknumber", "") or "", str(track),
                                                  "leading_disc_track_promote_track"))
                            if args.write:
                                write_tag(kind, path, "tracknumber", str(track))
                                touched_files.add(path)
                            tags["tracknumber"] = str(track)

                        changes.append(Change(path, "title", title, rest, "leading_disc_track_strip"))
                        if args.write:
                            write_tag(kind, path, "title", rest)
                            touched_files.add(path)
                        tags["title"] = rest

        # 2) Plain track prefixes (06 Foo) if enabled
        if args.fix_leading_tracknums != "off":
            title = tags.get("title", "") or ""
            if title:
                num, rest = leading_track_prefix(title)
                if num is not None and rest is not None and num <= args.max_prefix_tracknum:
                    existing_tr, _ = parse_slash_number(tags.get("tracknumber", "") or "")
                    if args.fix_leading_tracknums == "strip":
                        if existing_tr is not None:
                            changes.append(Change(path, "title", title, rest, "leading_tracknum_strip"))
                            if args.write:
                                write_tag(kind, path, "title", rest)
                                touched_files.add(path)
                            tags["title"] = rest
                    elif args.fix_leading_tracknums == "promote":
                        if existing_tr is None:
                            changes.append(Change(path, "tracknumber", tags.get("tracknumber", "") or "", str(num),
                                                  "leading_tracknum_promote"))
                            if args.write:
                                write_tag(kind, path, "tracknumber", str(num))
                                touched_files.add(path)
                            tags["tracknumber"] = str(num)

                        changes.append(Change(path, "title", title, rest, "leading_tracknum_strip"))
                        if args.write:
                            write_tag(kind, path, "title", rest)
                            touched_files.add(path)
                        tags["title"] = rest

        # 3) Normal scrubbing
        for field in fields:
            old = tags.get(field, "")
            if not old:
                continue

            if field in {"tracknumber", "discnumber"}:
                n, tot = parse_slash_number(old)
                if n is None:
                    continue
                new = fmt_slash_number(n, tot)
                rules = ["normalize_" + field] if new != old.strip() else []
            else:
                # enable optional trailing-date conversion per-CLI
                scrub_text.convert_trailing_date_enabled = args.trailing_date
                new, rules = scrub_text(old, do_title_case=do_title_case)

            if new != old:
                changes.append(Change(path, field, old, new, ";".join(rules)))
                if args.write:
                    write_tag(kind, path, field, new)
                    touched_files.add(path)

        if not args.quiet and idx % 200 == 0:
            print(f"Scanned {idx}/{len(files)}...")

    print(f"Scanned files: {len(files)}")
    print(f"Planned changes: {len(changes)}")
    if args.write:
        print(f"Files modified: {len(touched_files)}")
    else:
        print("Dry-run only (no changes written). Use --write to apply.")

    if changes and not args.quiet:
        print("\nPreview (first 20 changes):")
        for ch in changes[:20]:
            rel = os.path.relpath(ch.path, root)
            print(f"- {rel} [{ch.field}]")
            print(f"    OLD: {ch.old}")
            print(f"    NEW: {ch.new}")
            print(f"    RULES: {ch.rules}")

    if args.report:
        with open(args.report, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["path", "field", "old", "new", "rules"])
            for ch in changes:
                w.writerow([ch.path, ch.field, ch.old, ch.new, ch.rules])
        print(f"\nWrote report: {args.report}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())