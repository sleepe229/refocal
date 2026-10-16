# Release checklist (OPS-REL-005)

Before tagging a minor release (0.x.0, 1.0 …); patch releases need only the runbook steps.
Copy the list into the release PR and tick it there.

**Build and tests**
- [ ] `main` CI green (dart, native with sanitizers, fuzz, android)
- [ ] Emulator e2e on an x64 profile APK of the release branch: `SCENARIO=basic` and `pause`
      (`tools/emulator/e2e.sh`); `rfpack` if packs changed
- [ ] Device check on a real phone: [device-checklist.md](device-checklist.md)

**Licenses and models**
- [ ] `tools/licenses/collect.sh` rerun if a native submodule or bundled model changed
- [ ] [MODELS.md](../../MODELS.md) has every bundled model and pack, with evaluation and limits
- [ ] New third-party packages: licenses compatible with Apache-2.0 (spec 12)

**Store policies and privacy** (once a store is in use, Q-06)
- [ ] Spec 08 (platform compliance) re-read against the current Play / App Store / F-Droid
      policies; differences filed as issues
- [ ] Data Safety / Privacy Label still match what the app does (network only on user action)
- [ ] Screenshots and store texts ([appendix/store-listing.md](../spec/appendix/store-listing.md))
      show the current UI

**Release**
- [ ] `version:` in `app/pubspec.yaml`; CHANGELOG section (it becomes the notes)
- [ ] Tag, approve the `release` environment, then check the draft: APK, symbols, SBOM
      (`*.spdx.json`), SHA256SUMS matches, `libenh` version = tag, attestations
      (`gh attestation verify <apk> --repo sleepe229/refocal`)
- [ ] Publish the draft; update the roadmap status ([13](../spec/13-roadmap-milestones.md))

Runbook with the commands: [release.md](release.md).
