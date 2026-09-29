# Verification

The standing pattern for every dispatch. Run each command through
`~/code/jon-platform/scripts/quiet-run`, so only errors and verdicts reach context
(jon-platform `docs/agent-workflow.md` § Token discipline).

```bash
qr=~/code/jon-platform/scripts/quiet-run
$qr swift test --package-path VinylFeverCore
$qr xcodebuild -scheme VinylFever -destination 'platform=macOS' test
~/code/jon-platform/scripts/check-handoff     # warn-only document-shape hygiene (ADR-0005)
```

Run `xcodegen generate` first when `project.yml` or the file list changed. Start with the
narrowest test (`swift test --filter …`) and run the full set once before marking a PR ready.
Vinyl Fever is Mac-first: no simulator; name any Music.app or on-device risk in the PR as
unverified.
