#!/usr/bin/env python3
import argparse
import os
import re
import sys
from pathlib import Path

PAT = re.compile(r"^(\d{3,4})_(.+)$")

def main():
    ap = argparse.ArgumentParser(description="Remove leading 3–4 digits + underscore from filenames.")
    ap.add_argument("dir", nargs="?", default=".", help="Directory to process (default: current)")
    ap.add_argument("--apply", action="store_true", help="Actually rename files (default: dry run)")
    ap.add_argument("--ext", default="", help="Optional extension filter (e.g. flac, mp3, m4a). Default: all")
    args = ap.parse_args()

    d = Path(args.dir).expanduser().resolve()
    if not d.is_dir():
        print(f"Not a directory: {d}", file=sys.stderr)
        return 2

    ext_filter = args.ext.lower().lstrip(".")
    files = sorted([p for p in d.iterdir() if p.is_file()])

    planned = []
    violations = []

    for p in files:
        name = p.name
        if ext_filter:
            if p.suffix.lower().lstrip(".") != ext_filter:
                continue

        m = PAT.match(name)
        if not m:
            continue

        # Verify only one underscore (the leading one)
        if name.count("_") != 1:
            violations.append(name)
            continue

        new_name = m.group(2)
        new_path = p.with_name(new_name)

        planned.append((p, new_path))

    if violations:
        print("Found files matching the prefix pattern BUT containing additional underscores (not renaming these):")
        for v in violations:
            print("  ", v)
        print()

    if not planned:
        print("No files to rename.")
        return 0

    print(f"Directory: {d}")
    print(f"Planned renames: {len(planned)}")
    for old, new in planned[:50]:
        print(f"  {old.name} -> {new.name}")
    if len(planned) > 50:
        print(f"  ... (+{len(planned)-50} more)")

    # Check for collisions
    dests = {}
    collisions = []
    for old, new in planned:
        if new.exists() and new != old:
            collisions.append((old.name, new.name, "destination exists"))
        key = new.name.lower()
        if key in dests:
            collisions.append((old.name, new.name, f"duplicate target with {dests[key]}"))
        else:
            dests[key] = old.name

    if collisions:
        print("\nCollisions detected (no changes made):", file=sys.stderr)
        for a, b, why in collisions:
            print(f"  {a} -> {b}  ({why})", file=sys.stderr)
        return 1

    if not args.apply:
        print("\nDry run only. Re-run with --apply to rename.")
        return 0

    for old, new in planned:
        old.rename(new)

    print("Done.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())