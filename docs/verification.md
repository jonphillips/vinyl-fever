# Verification

The standing pattern for every dispatch. Run each command through
`~/code/jon-platform/scripts/quiet-run`, so only errors and verdicts reach context
(jon-platform `docs/agent-workflow.md` § Token discipline).

```bash
qr=~/code/jon-platform/scripts/quiet-run
$qr swift test --package-path VinylFeverListening
$qr swift test --package-path VinylFeverNotes
$qr swift test --package-path VinylFeverCore
$qr xcodebuild -scheme VinylFever -destination 'platform=macOS' test
$qr xcodebuild -scheme VinylFeverMobile -destination 'generic/platform=iOS Simulator' build
$qr xcodebuild -scheme VinylFeverMobile -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
VF_PERF_TESTS=1 $qr swift test --package-path VinylFeverCore
VF_PERF_TESTS=1 $qr swift test --package-path VinylFeverListening
~/code/jon-platform/scripts/check-handoff     # warn-only document-shape hygiene (ADR-0005)
```

After cloning, run `xcodegen generate`; the generated project is not committed. Git hooks
regenerate it after checkout, pull, and rebase. Run `xcodegen generate` first when `project.yml`
or the file list changed. Run the opt-in performance suites before a PR that touches
`LibraryIndex`, `ArtistIdentity`, or the listening log reader. Start with the
narrowest test (`swift test --filter …`) and run the full set once before marking a PR ready.
The Mac app has no simulator; name any Music.app or on-device risk in the PR as unverified.
The iPhone companion builds and runs in the iOS Simulator, but Siri, MusicKit playback and
Up Next, and ShazamKit need a device: name those as owed device gates.
