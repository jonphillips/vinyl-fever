#!/opt/homebrew/bin/bash
set -euo pipefail
shopt -s nullglob

# music_pipeline.sh
#
# A guided pipeline for live-show folders that NEVER modifies your originals.
#
# Supports:
#   EXT=flac (default): normalize/rename/tag FLACs, optional FLAC->ALAC
#   EXT=mp3           : normalize/rename/tag MP3s (no conversion step)
#   EXT=m4a           : normalize/rename/tag M4A/MP4 audio files (no conversion step)
#
# Workflow:
#  0) Create/reuse ./Working/ and copy source tracks into it (and optional cover art)
#  1) Optional: consolidate multi-disc/set subfolders into Working/TrackNN.$EXT
#  2) Normalize filenames in Working/ to TrackNN.$EXT (handles s1t01 / s2t01, disc restarts, etc.)
#  3) Prompt-paste setlist content -> Working/setlist.txt
#  4) Apply setlist: rename to "NN - Title.$EXT", tag files, embed optional cover
#     - Strict by default: #titles must equal #files (override via ALLOW_MISMATCH=1)
#  5) Prompt to confirm/edit ALBUM suffix like (DSBD)/(AUD) and retag ALBUM on all files
#  6) Pause, then optional FLAC->ALAC conversion in parallel (only when EXT=flac)
#     - Output goes OUTSIDE Working (./ALAC by default)
#
# Requirements:
#  - Bash 5+ (Homebrew bash recommended)
#  - FLAC tagging:   brew install flac    (metaflac)
#  - MP3/M4A tagging:brew install ffmpeg  (ffmpeg/ffprobe)
#  - ALAC conversion:brew install ffmpeg
#
# Intel Homebrew note:
#  - Change shebang to: #!/usr/local/bin/bash

# ---------- config ----------
EXT="${EXT:-flac}"
if [[ "$EXT" != "flac" && "$EXT" != "mp3" && "$EXT" != "m4a" ]]; then
  echo "Error: EXT must be 'flac' or 'mp3' or 'm4a' (got: $EXT)" >&2
  exit 1
fi

# ---------- helpers ----------
die(){ echo "Error: $*" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

prompt_yn() {
  local msg="$1" default="${2:-N}" ans
  if [[ "$default" == "Y" ]]; then
    read -r -p "$msg (Y/n) " ans
    [[ -z "$ans" ]] && ans="Y"
  else
    read -r -p "$msg (y/N) " ans
    [[ -z "$ans" ]] && ans="N"
  fi
  [[ "$ans" =~ ^[yY]$ ]]
}

cpu_cores(){ sysctl -n hw.ncpu; }

extract_first_int() {
  local s="$1"
  if [[ "$s" =~ ([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo "9999"
  fi
}

sanitize_filename() { sed 's/[\/:*?"<>|]/-/g' <<<"$1"; }

prepare_workdir() {
  local work="$1"
  if [[ -d "$work" ]]; then
    echo "Found existing ./$work/"
    if prompt_yn "Replace it (delete and recreate)?" N; then
      rm -rf "$work"
    else
      prompt_yn "Reuse it as-is?" Y || die "Aborting (won't touch existing $work)."
    fi
  fi
  mkdir -p "$work"
}

copy_cover_candidates() {
  # Copies cover files named front.* or image.* (any extension) into target dir (if found)
  local target="$1"
  local found src

  for base in front image; do
    found="$(find . -maxdepth 1 -type f -iname "${base}.*" -print | sort | head -n 1 || true)"
    if [[ -n "$found" ]]; then
      src="${found#./}"
      [[ -e "$target/$src" ]] || cp -- "$src" "$target/"
    fi
  done
}

copy_tracks_to_working() {
  local dest="$1"
  local tracks=( *."$EXT" )
  (( ${#tracks[@]} )) || die "No *.$EXT files in current folder to copy."
  echo "Will copy ${#tracks[@]} .$EXT files into ./$dest/ (no overwrites)."
  prompt_yn "Proceed with copy?" Y || die "Aborting."
  for f in "${tracks[@]}"; do
    [[ -e "$dest/$f" ]] && die "Destination exists: $dest/$f"
    cp -- "$f" "$dest/"
  done
  echo "Copy complete."
}

# ---------- step 1: consolidate discs/sets into Working ----------
consolidate_discs_to() {
  local dest="$1" ext="$EXT"
  local dirs=() name d tmp_list total width i shown
  local -a sorted_dirs=()

  for d in */; do
    [[ -d "$d" ]] || continue
    name="${d%/}"
    [[ "$name" == "$dest" ]] && continue
    [[ "$name" == .* ]] && continue
    dirs+=( "$name" )
  done
  (( ${#dirs[@]} )) || die "No subfolders found to consolidate."

  local any=0
  for name in "${dirs[@]}"; do
    compgen -G "$name"/*."$ext" >/dev/null && { any=1; break; }
  done
  (( any )) || die "No *.$ext files found in subfolders."

  tmp_list="$(mktemp)"
  trap 'rm -f "$tmp_list"' RETURN

  for name in "${dirs[@]}"; do
    printf "%s\t%s\n" "$(extract_first_int "$name")" "$name" >> "$tmp_list"
  done
  mapfile -t sorted_dirs < <(sort -n -k1,1 -k2,2 "$tmp_list" | cut -f2-)

  total=0
  for name in "${sorted_dirs[@]}"; do
    local c=0
    while IFS= read -r _; do ((++c)); done < <(ls -1v "$name"/*."$ext" 2>/dev/null || true)
    total=$((total + c))
  done
  (( total > 0 )) || die "No *.$ext found to consolidate."

  width=2; (( total >= 100 )) && width=3; (( total >= 1000 )) && width=4

  echo "Will consolidate into ./$dest/"
  echo "Folder order:"
  printf "  %s\n" "${sorted_dirs[@]}"
  echo "Total tracks: $total"
  echo

  echo "Preview (first ~10):"
  i=1; shown=0
  for name in "${sorted_dirs[@]}"; do
    while IFS= read -r f; do
      printf "  %s/%s -> %s/Track%0*d.%s\n" "$name" "${f##*/}" "$dest" "$width" "$i" "$ext"
      i=$((i+1)); shown=$((shown+1))
      (( shown >= 10 )) && break 2
    done < <(ls -1v "$name"/*."$ext" 2>/dev/null || true)
  done
  echo

  prompt_yn "Proceed with consolidation (copy, no overwrites)?" N || { echo "Skipping consolidation."; return 1; }

  i=1
  for name in "${sorted_dirs[@]}"; do
    while IFS= read -r f; do
      local out="$dest/Track$(printf "%0*d" "$width" "$i").$ext"
      [[ -e "$out" ]] && die "Destination exists: $out"
      cp -- "$f" "$out"
      i=$((i+1))
    done < <(ls -1v "$name"/*."$ext" 2>/dev/null || true)
  done

  echo "Consolidation complete: $dest/ contains $((i-1)) files."
  return 0
}

# ---------- step 2: normalize to TrackNN.$EXT (sequential) ----------
normalize_tracks_in_dir() {
  local dir="$1"
  pushd "$dir" >/dev/null

  local files=( *."$EXT" )
  (( ${#files[@]} )) || die "No .$EXT files found in $dir"

  make_key() {
    local f="$1"
    local base="${f%.$EXT}"   # <-- FIXED: strip current extension, not hardcoded .flac
    local disc="" track=""

    # set/disc/cd + track patterns like s1t01, set2t03, disc1 track04, cd2t10
    if [[ "$base" =~ ([sS][eE][tT]|[sS]|[dD][iI][sS][cC]|[dD]|[cC][dD])[[:space:]_.-]*([0-9]{1,3})[[:space:]_.-]*([tT]([rR][aA][cC][kK])?)[[:space:]_.-]*([0-9]{1,3}) ]]; then
      disc="${BASH_REMATCH[2]}"
      track="${BASH_REMATCH[5]}"
      printf '%06d' "$((10#$disc * 1000 + 10#$track))"
      return 0
    fi

    # underscore track pattern like "..._01 Title" or "..._27 40"
    if [[ "$base" =~ _([0-9]{1,3})[[:space:]] ]]; then
      track="${BASH_REMATCH[1]}"
      printf '%06d' "$((10#$track))"
      return 0
    fi

    # leading number with common punctuation: "03. blah", "40, blah", "2-1. blah", "01) blah"
    # (we take the FIRST number group as the track index)
    if [[ "$base" =~ ^[[:space:]]*([0-9]{1,4})[[:space:]]*[[:punct:]]+[[:space:]]* ]]; then
      track="${BASH_REMATCH[1]}"
      printf '%06d' "$((10#$track))"
      return 0
    fi

    # TrackNN anywhere
    if [[ "$base" =~ ([tT]([rR][aA][cC][kK])?)[[:space:]_.-]*([0-9]{1,4}) ]]; then
      track="${BASH_REMATCH[3]}"
      printf '%06d' "$((10#$track))"
      return 0
    fi

    # If the filename ends with a date like 2016.10.01 (or 2016-10-01), DON'T treat the day as a track number
    if [[ "$base" =~ (19|20)[0-9]{2}[._-][0-9]{1,2}[._-][0-9]{1,2}$ ]]; then
      printf '%06d' 999999
      return 0
    fi

    # trailing digits (last-resort)
    if [[ "$base" =~ ([0-9]{1,4})$ ]]; then
      track="${BASH_REMATCH[1]}"
      printf '%06d' "$((10#$track))"
      return 0
    fi

    printf '%06d' 999999
  }

  local tmp_list tmpdir
  tmp_list="$(mktemp)"
  tmpdir="$(mktemp -d)"
  trap 'rm -f "$tmp_list"; rm -rf "$tmpdir"' RETURN

  local f key
  for f in "${files[@]}"; do
    key="$(make_key "$f")"
    printf '%s\t%s\n' "$key" "$f" >> "$tmp_list"
  done

  local -a sorted=()
  mapfile -t sorted < <(sort -n -k1,1 -k2,2 "$tmp_list" | cut -f2-)

  local n="${#sorted[@]}"
  local width=2; (( n >= 100 )) && width=3; (( n >= 1000 )) && width=4

  echo
  echo "Normalize filenames in: $dir"
  echo "Planned mapping:"
  local i=1
  for f in "${sorted[@]}"; do
    printf "  %s  ->  Track%0*d.%s\n" "$f" "$width" "$i" "$EXT"
    ((i++))
  done
  echo

  prompt_yn "Proceed with normalization (sequential TrackNN)?" Y || { echo "Skipping normalization."; popd >/dev/null; return; }

  i=1
  for f in "${sorted[@]}"; do
    local new="Track$(printf "%0*d" "$width" "$i").$EXT"
    mv -n -- "$f" "$tmpdir/$new.__tmp__"
    ((i++))
  done

  for f in "$tmpdir"/*."$EXT".__tmp__; do
    [[ -e "$f" ]] || continue
    local final="${f##*/}"
    final="${final%.__tmp__}"
    mv -n -- "$f" "./$final"
  done

  echo "Normalization done."
  popd >/dev/null
}

# ---------- step 3: create setlist.txt interactively ----------
create_setlist_file() {
  local dir="$1"
  pushd "$dir" >/dev/null

  if [[ -e setlist.txt ]]; then
    prompt_yn "setlist.txt already exists in $dir. Overwrite?" N || { echo "Keeping existing setlist.txt"; popd >/dev/null; return; }
  fi

  cat <<'MSG'
Paste your setlist content now (headers + blank line + tracks).
Finish by typing a line containing only:
END
MSG

  local tmp
  tmp="$(mktemp)"
  while IFS= read -r line; do
    [[ "$line" == "END" ]] && break
    printf '%s\n' "$line" >> "$tmp"
  done

  mv "$tmp" setlist.txt
  echo "Wrote: $dir/setlist.txt"
  popd >/dev/null
}

# ---------- MP3/M4A tagging helper (stream copy; preserve/attach cover) ----------
tag_audio_in_place() {
  # Rewrites the file in-place via temp with updated tags.
  #
  # For MP3:
  #  - writes ID3v2.3, preserves embedded cover unless folder-level cover is provided (then replaces)
  #
  # For M4A:
  #  - writes MP4 atoms, preserves embedded cover unless folder-level cover is provided (then replaces)
  #
  # Notes:
  #  - We keep it simple: titles/artist/album/albumartist/date/genre/comment + track/total.
  #  - Extras (custom tags) are intentionally not handled here.
  local file="$1" title="$2" tracknum="$3" tracktotal="$4"
  local artist="${5:-}" album="${6:-}" albumartist="${7:-}" date="${8:-}" genre="${9:-}" comment="${10:-}"
  local cover="${11:-}"

  have ffmpeg || die "ffmpeg required for MP3/M4A tagging (brew install ffmpeg)"

  local ext="${file##*.}"
  local tmp

  if [[ "$ext" == "mp3" ]]; then
    tmp="${file}.tagtmp.mp3"

    if [[ -n "$cover" && -f "$cover" ]]; then
      ffmpeg -nostdin -hide_banner -loglevel error \
        -i "$file" -i "$cover" \
        -map 0:a:0 -map 1:v:0 \
        -c:a copy -c:v mjpeg \
        -id3v2_version 3 \
        -metadata "title=$title" \
        -metadata "track=${tracknum}/${tracktotal}" \
        ${artist:+-metadata "artist=$artist"} \
        ${album:+-metadata "album=$album"} \
        ${albumartist:+-metadata "album_artist=$albumartist"} \
        ${date:+-metadata "date=$date"} \
        ${genre:+-metadata "genre=$genre"} \
        ${comment:+-metadata "comment=$comment"} \
        -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
        "$tmp"
    else
      # Preserve existing attached pic if present (optional mapping via '?')
      ffmpeg -nostdin -hide_banner -loglevel error \
        -i "$file" \
        -map 0:a:0 -map '0:v:0?' \
        -c:a copy -c:v mjpeg \
        -id3v2_version 3 \
        -metadata "title=$title" \
        -metadata "track=${tracknum}/${tracktotal}" \
        ${artist:+-metadata "artist=$artist"} \
        ${album:+-metadata "album=$album"} \
        ${albumartist:+-metadata "album_artist=$albumartist"} \
        ${date:+-metadata "date=$date"} \
        ${genre:+-metadata "genre=$genre"} \
        ${comment:+-metadata "comment=$comment"} \
        -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
        "$tmp"
    fi

    mv -f -- "$tmp" "$file"
    return
  fi

  if [[ "$ext" == "m4a" || "$ext" == "mp4" ]]; then
    tmp="${file}.tagtmp.m4a"

    if [[ -n "$cover" && -f "$cover" ]]; then
      ffmpeg -nostdin -hide_banner -loglevel error \
        -i "$file" -i "$cover" \
        -map 0:a:0 -map 1:v:0 \
        -c:a copy -c:v mjpeg \
        -disposition:v:0 attached_pic \
        -map_metadata 0 \
        -metadata "title=$title" \
        -metadata "track=${tracknum}/${tracktotal}" \
        ${artist:+-metadata "artist=$artist"} \
        ${album:+-metadata "album=$album"} \
        ${albumartist:+-metadata "album_artist=$albumartist"} \
        ${date:+-metadata "date=$date"} \
        ${genre:+-metadata "genre=$genre"} \
        ${comment:+-metadata "comment=$comment"} \
        -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
        -movflags +faststart \
        -f ipod \
        "$tmp"
    else
      # Preserve existing attached pic if present (optional mapping via '?')
      ffmpeg -nostdin -hide_banner -loglevel error \
        -i "$file" \
        -map 0:a:0 -map '0:v:0?' \
        -c:a copy -c:v mjpeg \
        -disposition:v:0 attached_pic \
        -map_metadata 0 \
        -metadata "title=$title" \
        -metadata "track=${tracknum}/${tracktotal}" \
        ${artist:+-metadata "artist=$artist"} \
        ${album:+-metadata "album=$album"} \
        ${albumartist:+-metadata "album_artist=$albumartist"} \
        ${date:+-metadata "date=$date"} \
        ${genre:+-metadata "genre=$genre"} \
        ${comment:+-metadata "comment=$comment"} \
        -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
        -movflags +faststart \
        -f ipod \
        "$tmp"
    fi

    mv -f -- "$tmp" "$file"
    return
  fi

  die "tag_audio_in_place: unsupported extension for $file"
}

# ---------- step 4: apply setlist (rename + tag + optional cover) ----------
apply_setlist() {
  local dir="$1" setlist="${2:-setlist.txt}"
  pushd "$dir" >/dev/null

  [[ -f "$setlist" ]] || die "Missing $dir/$setlist"

  local -a files=()
  mapfile -t files < <(printf '%s\n' *."$EXT" | sort -V)
  (( ${#files[@]} )) || die "No .$EXT files found in $dir"

  local -A H=()
  local -a extras=()
  local -a titles=()
  local in_titles=0

  mapfile -t lines < "$setlist"
  for line in "${lines[@]}"; do
    line="${line%$'\r'}"
    if (( in_titles == 0 )); then
      [[ "$line" =~ ^[[:space:]]*$ ]] && { in_titles=1; continue; }
      if [[ "$line" =~ ^([A-Za-z0-9_ ]+):[[:space:]]*(.*)$ ]]; then
        local rawkey="${BASH_REMATCH[1]}" val="${BASH_REMATCH[2]}"
        local key
        key="$(tr '[:lower:]' '[:upper:]' <<<"$rawkey" | sed 's/[[:space:]]\+//g')"
        if [[ "$key" == "TAG" ]]; then
          if [[ "$val" =~ ^([A-Za-z0-9_ -]+)=(.*)$ ]]; then
            local tkey
            tkey="$(tr '[:lower:]' '[:upper:]' <<<"${BASH_REMATCH[1]}" | sed 's/[[:space:]]\+//g')"
            extras+=( "${tkey}=${BASH_REMATCH[2]}" )
          fi
        else
          H["$key"]="$val"
        fi
        continue
      fi
      in_titles=1
    fi
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    titles+=( "$line" )
  done

  (( ${#titles[@]} )) || die "No track titles found in $setlist"

  # Cover logic: COVER header or auto front.* then image.*
  local cover=""
  if [[ -n "${H[COVER]:-}" ]]; then
    local candidate="${H[COVER]#./}"
    [[ -f "$candidate" ]] || die "COVER specified but not found: $candidate"
    cover="$candidate"
  else
    for base in front image; do
      local found
      found="$(find . -maxdepth 1 -type f -iname "${base}.*" -print | sort | head -n 1 || true)"
      [[ -n "$found" ]] && { cover="${found#./}"; break; }
    done
  fi

  echo
  echo "Apply setlist in: $dir"
  for k in ARTIST ALBUM ALBUMARTIST DATE GENRE DISCNUMBER DISCTOTAL COMMENT COVER; do
    [[ -n "${H[$k]:-}" ]] && echo "$k: ${H[$k]}"
  done
  [[ -n "$cover" ]] && echo "Cover art: $cover" || echo "Cover art: (none)"
  echo "Files ($EXT):     ${#files[@]}"
  echo "Setlist titles:   ${#titles[@]}"
  echo

  # Strict match by default
  if (( ${#titles[@]} != ${#files[@]} )); then
    echo "ERROR: setlist track count (${#titles[@]}) does not match file count (${#files[@]})." >&2
    if [[ "${ALLOW_MISMATCH:-0}" == "1" ]]; then
      echo "ALLOW_MISMATCH=1 set; proceeding using the smaller count." >&2
    else
      echo "Fix setlist.txt or adjust files, then re-run." >&2
      echo "Or re-run with ALLOW_MISMATCH=1 to proceed anyway." >&2
      if ! prompt_yn "Proceed anyway (will use the smaller count)?" N; then
        popd >/dev/null
        return 1
      fi
    fi
  fi

  local count=${#files[@]}
  (( ${#titles[@]} < count )) && count=${#titles[@]}

  echo "Tracks to apply: $count"
  echo
  echo "Preview (first ~10):"
  for ((i=0; i< count && i<10; i++)); do
    local tn
    tn=$(printf "%02d" $((i+1)))
    echo "  ${files[$i]} -> ${tn} - ${titles[$i]}.${EXT}"
  done
  echo

  prompt_yn "Proceed with rename + tag (inside Working only)?" Y || { echo "Skipping apply_setlist."; popd >/dev/null; return; }

  # FLAC tagging requires metaflac; MP3/M4A tagging requires ffmpeg
  if [[ "$EXT" == "flac" ]]; then
    have metaflac || die "metaflac not found. Install: brew install flac"
  else
    have ffmpeg || die "ffmpeg not found. Install: brew install ffmpeg"
  fi

  for ((i=0; i<count; i++)); do
    local tn title old clean_title new
    tn=$(printf "%02d" $((i+1)))
    title="${titles[$i]}"
    old="${files[$i]}"
    clean_title="$(sanitize_filename "$title")"
    new="${tn} - ${clean_title}.${EXT}"

    mv -i -- "$old" "$new"

    if [[ "$EXT" == "flac" ]]; then
      # --- 1) TAG OPS ONLY (shorthand) ---
      local -a tag_args=(
        --remove-tag=TITLE       --set-tag="TITLE=$title"
        --remove-tag=TRACKNUMBER --set-tag="TRACKNUMBER=$((i+1))"
        --remove-tag=TRACKTOTAL  --set-tag="TRACKTOTAL=$count"
      )

      for k in ARTIST ALBUM ALBUMARTIST DATE GENRE DISCNUMBER DISCTOTAL COMMENT; do
        [[ -n "${H[$k]:-}" ]] && tag_args+=( --remove-tag="$k" --set-tag="$k=${H[$k]}" )
      done
      for kv in "${extras[@]:-}"; do
        local ek="${kv%%=*}" ev="${kv#*=}"
        tag_args+=( --remove-tag="$ek" --set-tag="$ek=$ev" )
      done

      metaflac "${tag_args[@]}" "$new"

      # --- 2) PICTURE OPS ONLY (major ops) ---
      if [[ -n "$cover" ]]; then
        metaflac --remove --block-type=PICTURE "$new" >/dev/null 2>&1 || true
        metaflac --import-picture-from="$cover" "$new" \
          || echo "WARN: cover import failed for $new (continuing)" >&2
      fi
    else
      # MP3/M4A tagging (stream copy) + cover (replace if folder-level cover exists; else preserve embedded)
      local artist="${H[ARTIST]:-}"
      local album="${H[ALBUM]:-}"
      local albumartist="${H[ALBUMARTIST]:-}"
      local date="${H[DATE]:-}"
      local genre="${H[GENRE]:-}"
      local comment="${H[COMMENT]:-}"

      tag_audio_in_place "$new" "$title" "$((i+1))" "$count" \
        "$artist" "$album" "$albumartist" "$date" "$genre" "$comment" "$cover"

      # Extras: best-effort via additional rewrite is possible, but intentionally omitted.
    fi
  done

  echo "apply_setlist complete."
  popd >/dev/null
}

# ---------- step 5: prompt/edit ALBUM source suffix like (DSBD)/(AUD) ----------
prompt_album_source_suffix() {
  local dir="$1"
  pushd "$dir" >/dev/null

  [[ -f setlist.txt ]] || { echo "No setlist.txt found in $dir; skipping source prompt."; popd >/dev/null; return; }

  local album_line album_value
  album_line="$(grep -m 1 '^ALBUM:' setlist.txt || true)"
  if [[ -z "$album_line" ]]; then
    echo "No ALBUM: line found in setlist.txt; skipping source prompt."
    popd >/dev/null
    return
  fi

  album_value="${album_line#ALBUM: }"

  local base suffix
  if [[ "$album_value" =~ ^(.*)[[:space:]]\(([A-Za-z0-9_-]+)\)$ ]]; then
    base="${BASH_REMATCH[1]}"
    suffix="${BASH_REMATCH[2]}"
  else
    base="$album_value"
    suffix=""
  fi

  echo
  echo "Album (base): $base"
  if [[ -n "$suffix" ]]; then
    echo "Current source suffix: ($suffix)"
  else
    echo "Current source suffix: (none)"
  fi
  echo
  echo "Common suffixes: DSBD, SBD, AUD, FM, WEB, MTX"
  echo "Press Return to keep as-is. Enter '-' to remove the suffix."
  read -r -p "Source suffix? " ans

  [[ -z "${ans:-}" ]] && { echo "Keeping source suffix unchanged."; popd >/dev/null; return; }

  local new_album
  if [[ "$ans" == "-" ]]; then
    new_album="$base"
  else
    ans="$(tr '[:lower:]' '[:upper:]' <<<"$ans" | tr -d ' ')"
    new_album="${base} (${ans})"
  fi

  local tmp
  tmp="$(mktemp)"
  while IFS= read -r line; do
    if [[ "$line" == ALBUM:* ]]; then
      echo "ALBUM: $new_album" >> "$tmp"
    else
      echo "$line" >> "$tmp"
    fi
  done < setlist.txt
  mv "$tmp" setlist.txt

  echo "Updated setlist.txt:"
  echo "ALBUM: $new_album"

  if [[ "$EXT" == "flac" ]]; then
    if have metaflac; then
      local f
      for f in *."$EXT"; do
        [[ -f "$f" ]] || continue
        metaflac --remove-tag=ALBUM --set-tag="ALBUM=$new_album" "$f"
      done
      echo "Updated ALBUM tag on FLAC files in $dir."
    else
      echo "metaflac not available; did not retag FLAC files."
    fi
  else
    have ffmpeg || { echo "ffmpeg not available; did not retag $EXT files."; popd >/dev/null; return; }

    local f tmpout
    for f in *."$EXT"; do
      [[ -f "$f" ]] || continue

      if [[ "$EXT" == "mp3" ]]; then
        tmpout="${f}.albumtmp.mp3"
        ffmpeg -nostdin -hide_banner -loglevel error \
          -i "$f" \
          -map 0:a:0 -map '0:v:0?' \
          -c:a copy -c:v mjpeg \
          -id3v2_version 3 \
          -map_metadata 0 \
          -metadata "album=$new_album" \
          "$tmpout"
      else
        # m4a/mp4
        tmpout="${f}.albumtmp.m4a"
        ffmpeg -nostdin -hide_banner -loglevel error \
          -i "$f" \
          -map 0:a:0 -map '0:v:0?' \
          -c:a copy -c:v mjpeg \
          -disposition:v:0 attached_pic \
          -map_metadata 0 \
          -metadata "album=$new_album" \
          -movflags +faststart \
          -f ipod \
          "$tmpout"
      fi

      mv -f -- "$tmpout" "$f"
    done
    echo "Updated ALBUM tag on $EXT files in $dir."
  fi

  popd >/dev/null
}

# ---------- step 6: optional FLAC->ALAC (output OUTSIDE Working) ----------
flac_to_alac_parallel() {
  local dir="$1"
  local cores jobs

  have ffmpeg || die "ffmpeg not found. Install: brew install ffmpeg"
  have ffprobe || die "ffprobe not found (comes with ffmpeg). Install: brew install ffmpeg"

  cores="$(cpu_cores)"

  if [[ -n "${2:-}" ]]; then
    jobs="$2"
  else
    jobs=$((cores - 1))
    (( jobs < 1 )) && jobs=1
  fi

  local base_dir parent_dir outdir
  base_dir="$(basename "$dir")"
  parent_dir="$(cd "$(dirname "$dir")" && pwd)"
  if [[ "$base_dir" == "Working" ]]; then
    outdir="$parent_dir/ALAC"
  else
    outdir="$parent_dir/ALAC_${base_dir}"
  fi

  pushd "$dir" >/dev/null
  mkdir -p "$outdir"

  local total_flacs
  total_flacs="$(find . -maxdepth 1 -type f -name '*.flac' | wc -l | tr -d ' ')"
  (( total_flacs > 0 )) || { echo "No .flac files found for ALAC conversion."; popd >/dev/null; return; }

  local existing=0 base
  while IFS= read -r -d '' f; do
    base="$(basename "$f" .flac)"
    [[ -e "$outdir/${base}.m4a" ]] && ((existing++))
  done < <(find . -maxdepth 1 -type f -name '*.flac' -print0)

  local cover=""
  for b in front image; do
    local found
    found="$(find . -maxdepth 1 -type f -iname "${b}.*" -print | sort | head -n 1 || true)"
    [[ -n "$found" ]] && { cover="${found#./}"; break; }
  done

  echo
  echo "Converting FLAC -> ALAC (preserve cover art when possible)"
  echo "Source:  $(pwd)"
  echo "Output:  $outdir"
  if [[ -n "$cover" ]]; then
    echo "Cover:   $cover (folder-level)"
  else
    echo "Cover:   (none found; will try embedded FLAC art per-track)"
  fi
  echo "FLAC files: $total_flacs  |  Already have ALAC: $existing  |  Jobs: $jobs (cores=$cores)"
  prompt_yn "Proceed with ALAC conversion now?" N || { echo "Skipping ALAC conversion."; popd >/dev/null; return; }

  find . -maxdepth 1 -type f -name '*.flac' -print0 | \
    xargs -0 -n 1 -P "$jobs" bash -lc '
      outdir="$1"
      cover="$2"
      f="$3"

      base="$(basename "$f" .flac)"
      out="$outdir/${base}.m4a"
      [[ -e "$out" ]] && exit 0

      if [[ -n "$cover" && -f "$cover" ]]; then
        ffmpeg -nostdin -hide_banner -loglevel error \
          -i "$f" -i "$cover" \
          -map 0:a:0 -map 1:v:0 \
          -map_metadata 0 \
          -c:a alac -c:v mjpeg \
          -disposition:v:0 attached_pic \
          -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
          -movflags +faststart \
          "$out"
        exit 0
      fi

      if ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$f" | grep -q .; then
        ffmpeg -nostdin -hide_banner -loglevel error \
          -i "$f" \
          -map 0:a:0 -map 0:v:0 \
          -map_metadata 0 \
          -c:a alac -c:v mjpeg \
          -disposition:v:0 attached_pic \
          -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
          -movflags +faststart \
          "$out"
        exit 0
      fi

      ffmpeg -nostdin -hide_banner -loglevel error \
        -i "$f" \
        -map 0:a:0 -vn -sn -dn \
        -map_metadata 0 \
        -c:a alac -movflags +faststart \
        "$out"
    ' _ "$outdir" "$cover"

  local now_have created
  now_have="$(find "$outdir" -maxdepth 1 -type f -name '*.m4a' | wc -l | tr -d ' ')"
  created=$(( now_have - existing ))
  (( created < 0 )) && created=0

  echo "ALAC conversion complete."
  echo "ALAC files in $(basename "$outdir"): $now_have  (created this run: $created, skipped: $existing)"

  popd >/dev/null
}

# ---------- main ----------
echo "Music pipeline starting in: $(pwd)"
echo "EXT=$EXT"

if [[ "$EXT" == "flac" ]]; then
  have metaflac || echo "Note: metaflac not found yet (brew install flac). You can still consolidate/normalize/create setlist."
else
  have ffmpeg || echo "Note: ffmpeg not found yet (brew install ffmpeg). You can still consolidate/normalize/create setlist."
fi

WORKDIR="Working"
prepare_workdir "$WORKDIR"

copy_cover_candidates "$WORKDIR"

echo
if prompt_yn "Do you need to consolidate multi-disc/set subfolders into ./$WORKDIR/ ?" N; then
  consolidate_discs_to "$WORKDIR" || die "Consolidation was selected but did not complete."
else
  copy_tracks_to_working "$WORKDIR"
fi

echo
echo "All work will happen in: $(pwd)/$WORKDIR"
echo "Original files/folders remain untouched."
echo

normalize_tracks_in_dir "$WORKDIR"
create_setlist_file "$WORKDIR"

apply_setlist "$WORKDIR" "setlist.txt"

prompt_album_source_suffix "$WORKDIR"

echo
echo "Pause: review ./$WORKDIR (filenames, tags, cover)."
read -r -p "Press Return to continue... " _

if [[ "$EXT" == "flac" ]] && have ffmpeg; then
  flac_to_alac_parallel "$WORKDIR"
else
  echo "Skipping ALAC conversion (EXT=$EXT)."
fi

echo
echo "Done."