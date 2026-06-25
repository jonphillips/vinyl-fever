#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage:
  prep_release.sh [--dry-run] [PATH]

If PATH is omitted, uses current directory.

Does, in order:
  0) Sanitizes filenames (Windows-problem chars, weird quotes, NO trailing whitespace, no spaces before extensions)
  1) Removes .DS_Store and AppleDouble ._* files
  2) Creates/overwrites fingerprints.ffp (FLAC audio fingerprints via metaflac)
  3) Creates/overwrites checksums.md5 (MD5 of all files except .ffp/.md5 outputs)

Options:
  --dry-run   Show what would be renamed, but don't rename.

Requirements:
  - macOS built-in 'md5'
  - 'metaflac' (from flac). Install with: brew install flac
EOF
}

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

TARGET="${1:-.}"
if [[ "${TARGET}" == "-h" || "${TARGET}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -d "${TARGET}" ]]; then
  echo "ERROR: Not a directory: ${TARGET}" >&2
  exit 1
fi

if ! command -v metaflac >/dev/null 2>&1; then
  echo "ERROR: 'metaflac' not found. Install with: brew install flac" >&2
  exit 1
fi

cd "${TARGET}"
echo "==> Working in: $(pwd)"

# ------------------------------------------------------------
# 0) Sanitize filenames (recursive), before any other processing
# ------------------------------------------------------------
echo "==> Sanitizing filenames (Windows-safe)..."
python3 - <<PY
import os, re, unicodedata

dry_run = ${DRY_RUN}

# Windows-illegal characters: < > : " / \ | ? *
BAD = r'<>:"/\\\\|?*'
bad_re = re.compile(r'[' + re.escape(BAD) + r']')

REPL = {
    "\\u2018": "'", "\\u2019": "'", "\\u201B": "'",
    "\\u201C": '"', "\\u201D": '"',
    "\\u2013": "-", "\\u2014": "-",
}

def sanitize_component(s: str) -> str:
    s = unicodedata.normalize("NFKC", s)
    s = "".join(REPL.get(ch, ch) for ch in s)
    s = bad_re.sub(" ", s)                 # replace illegal chars with space
    s = "".join(ch for ch in s if ch >= " " and ch != "\\x7f")  # remove controls
    s = re.sub(r"\\s+", " ", s).strip()    # collapse + trim whitespace
    s = s.rstrip(" .")                     # Windows: no trailing dot/space
    return s

def sanitize_name(name: str) -> str:
    # Keep extension, sanitize base separately so we never end up with "Song .flac"
    base, ext = os.path.splitext(name)
    base = sanitize_component(base)
    # ext usually fine; keep as-is but normalize odd whitespace just in case
    ext = ext.strip()
    # If base becomes empty (rare), fall back
    if not base:
        base = "untitled"
    return base + ext

def unique_path(dirpath: str, desired: str) -> str:
    base, ext = os.path.splitext(desired)
    candidate = desired
    n = 1
    while os.path.exists(os.path.join(dirpath, candidate)):
        candidate = f"{base} ({n}){ext}"
        n += 1
    return candidate

# Rename bottom-up so directory renames don't break traversal
renames = []
for root, dirs, files in os.walk(".", topdown=False):
    for fname in files:
        new = sanitize_name(fname)
        if new != fname:
            renames.append((root, fname, new))
    for dname in dirs:
        new = sanitize_component(dname)  # directories don't have extensions
        if new != dname and new:
            renames.append((root, dname, new))

for root, old, new in renames:
    old_path = os.path.join(root, old)
    new_name = new
    new_path = os.path.join(root, new_name)

    if os.path.exists(new_path):
        new_name = unique_path(root, new_name)
        new_path = os.path.join(root, new_name)

    if dry_run:
        print(f"DRY-RUN: {old_path}  ->  {new_path}")
    else:
        os.rename(old_path, new_path)
        print(f"RENAMED: {old_path}  ->  {new_path}")
PY

# --- cleanup ---
echo "==> Removing .DS_Store files..."
find . -type f -name ".DS_Store" -print -delete || true

echo "==> Removing AppleDouble ._* files..."
find . -type f -name "._*" -print -delete || true

# --- generate fingerprints.ffp ---
echo "==> Generating fingerprints.ffp..."
tmp_ffp="$(mktemp -t fingerprints.XXXXXX.ffp)"
find . -type f -name "*.flac" -print0 \
  | LC_ALL=C sort -z \
  | xargs -0 metaflac --show-md5sum --with-filename \
  > "${tmp_ffp}"
mv -f "${tmp_ffp}" "fingerprints.ffp"

# --- generate checksums.md5 ---
echo "==> Generating checksums.md5..."
tmp_md5="$(mktemp -t checksums.XXXXXX.md5)"
find . -type f \
  ! -name "checksums.md5" \
  ! -name "fingerprints.ffp" \
  -print0 \
  | LC_ALL=C sort -z \
  | xargs -0 md5 -r \
  > "${tmp_md5}"
mv -f "${tmp_md5}" "checksums.md5"

# --- sanity counts (more robust than the old grep) ---
flac_count="$(find . -type f -name "*.flac" | wc -l | tr -d ' ')"
# count non-empty lines in the ffp (format can vary)
ffp_lines="$(grep -cve '^[[:space:]]*$' fingerprints.ffp || true)"

echo "==> FLAC files: ${flac_count}"
echo "==> FFP lines : ${ffp_lines}"
if [[ "${flac_count}" != "${ffp_lines}" ]]; then
  echo "WARNING: FLAC count != fingerprint lines." >&2
  echo "         This can happen if metaflac outputs multiple lines per file or errors on a file." >&2
  echo "         Quick check: open fingerprints.ffp and confirm one entry per .flac." >&2
fi

echo "==> Done."
echo "    - fingerprints.ffp"
echo "    - checksums.md5"