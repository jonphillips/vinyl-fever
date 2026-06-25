# Legacy scripts

These Python and shell tools are the current music-library workflow engines and
serve as **evidence**, not as the product interface. The plan (see
[../docs/technical-architecture.md](../docs/technical-architecture.md), Script
Reassessment) is to reimplement stable workflow logic in Swift and keep only the
audio-tool orchestration (ffmpeg / metaflac / mutagen) as subprocesses.

Do not assume `--dry-run` means no writes; verify per script (for example
`prep_release.sh` still writes checksum/fingerprint output in dry-run).

## Layout

- `shell/` — `music_pipeline.sh` (the canonical live-show prep engine) and
  `prep_release.sh`.
- `python/` — batch conversion, tag scrubbing, dedup, triage, and compilation
  helpers. Tests in `python/tests/`.

## Setup

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python -m pytest python/tests
```
