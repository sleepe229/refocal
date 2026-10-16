# Release runbook (0.0.x alphas)

Releases are built only by `.github/workflows/release.yml` from a tag (OPS-REL-001). The workflow
creates a **draft**; a maintainer publishes it.

## One-time setup

### 1. Release signing key (keep it forever)

The same key signs every future update on GitHub Releases and, through reproducible builds,
on F-Droid (COMP-FDR-004). Losing it means users must uninstall to update. Keep two offline
copies (SEC-SUP-005: two key holders).

```sh
keytool -genkeypair -v -keystore refocal-release.jks -alias refocal \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Refocal, O=Refocal" 
# remember the store and key passwords; never commit the .jks
```

### 2. GitHub Environment `release`

Repository → Settings → Environments → New environment `release`; restrict deployments to tags
`v*` (SEC-CI-003). Only admins may create, move or delete those tags (ruleset "release tags"):

```sh
gh api -X POST repos/OWNER/refocal/rulesets --input - <<'JSON'
{"name": "release tags", "target": "tag", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
 "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}],
 "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]}
JSON
```

With more than one maintainer, also add the other maintainers as required reviewers. Then:

```sh
gh secret set ANDROID_KEYSTORE_B64 --env release < <(base64 -w0 refocal-release.jks)
gh secret set ANDROID_KEYSTORE_PASSWORD --env release
gh secret set ANDROID_KEY_ALIAS --env release --body refocal
gh secret set ANDROID_KEY_PASSWORD --env release
```

### 3. Model weights (bundled model)

Weights are not in git. Upload the converted files once as assets of a separate release; the
SHA-256 pins in `tools/models/models.lock` are checked on every download.

```sh
tools/models/fetch.sh --from spikes/_shared/models     # verifies the pins locally
gh release create model-sr.general-x4v3-v1 --title "Model: sr.general-x4v3 v1" \
  --notes "Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause, (c) 2021 Xintao Wang), DNI denoise 0.5, ncnn. See MODELS.md." \
  app/assets/models/sr.general-x4v3/model.ncnn.param app/assets/models/sr.general-x4v3/model.ncnn.bin
tools/models/fetch.sh                                   # must now succeed from the URLs
```

## Every release

1. Device check on at least one real phone: [device-checklist.md](device-checklist.md).
2. Bump `version:` in `app/pubspec.yaml`, the only copy (the native core compiles it in and the
   app reads it from there); add the section to `CHANGELOG.md` (its text becomes the release
   notes).
3. `git tag v0.0.2-alpha.1 && git push origin v0.0.2-alpha.1` (the version from step 2)
4. Approve the `release` environment run; review the draft (APK, SHA256SUMS, notes); publish.
