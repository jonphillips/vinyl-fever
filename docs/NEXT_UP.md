# Next Up — Writes survive iCloud eviction

**Slices:** effort `evicted-icloud-writes`
**Briefs:** [docs/efforts/evicted-icloud-writes.md](efforts/evicted-icloud-writes.md)
**Done when:** per the brief
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Needs to be installed before New Music on Friday 2026-11-13. Evicting a file needs real iCloud and the failure needs a launchd process, so no test here reproduces it. Name that in the PR; the architect's review runs the probe.
