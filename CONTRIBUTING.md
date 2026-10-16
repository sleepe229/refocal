# Contributing to Refocal

Thanks for helping. Refocal is an on-device photo enhancer: nothing a contribution adds may send
photos or data off the phone.

## Before you start

- Look for issues labelled `good first issue` or `help wanted`, or open one to discuss a larger
  change first. Architecture decisions are written down as ADRs in
  [`docs/spec/adr/`](docs/spec/adr/README.md); a change that contradicts one comes with an
  amendment (decided by lazy consensus of the maintainers, 72 h, see [GOVERNANCE.md](GOVERNANCE.md)).
- The specification is in [`docs/spec/`](docs/spec/README.md) (Russian). Requirement IDs
  (`FR-…`, `NFR-…`, `TEST-…`) are quoted in code comments, commits and PRs.

## Not accepted

Pull requests that add any of these are closed ([spec 12 §6](docs/spec/12-oss-governance-licensing.md),
[15](docs/spec/15-ethics-responsible-ai.md)):

- face swap or moving a face from another photo;
- undressing, generated nudity, sexualised content;
- reshaping bodies, beautification, slimming, changing age, race or gender;
- turning the AI marker in saved photos off **by default** (the user's option stays);
- telemetry, tracking, ad SDKs, any data collection without opt-in;
- cloud processing as a required part.

## Build and test

See [README.md](README.md#building). In short:

```sh
git submodule update --init --recursive
export PATH="$PWD/flutter/bin:$PATH"
flutter pub get
dart format --output=none --set-exit-if-changed app packages
flutter analyze app packages
(cd packages/refocal_core && dart test) && (cd app && flutter test)
cmake -S native -B native/build-host -DENH_BUILD_TESTS=ON -DENH_BUILD_CLI=ON
cmake --build native/build-host -j && ctest --test-dir native/build-host
```

C/C++ is formatted with clang-format 18 (`.clang-format`); `native/include/enh.h` and
`docs/spec/appendix/enh.h` must stay identical. Model weights are not in git:
`tools/models/fetch.sh` puts the bundled ones in place.

## Commits and pull requests

- [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`,
  `test:`, `style:`, `ci:` … with the requirement IDs the change covers.
- Every commit is signed off (`git commit -s`), certifying the
  [Developer Certificate of Origin](https://developercertificate.org/): you wrote the change or
  have the right to submit it under the project's license. The `dco` check fails without a
  `Signed-off-by:` line matching the commit author; `git rebase --signoff main` fixes a branch.
- One topic per pull request, based on `main`. CI must be green; UI changes come with a
  screenshot; new strings go to `app/lib/l10n/app_en.arb` (English is the template) and
  `app_ru.arb`.
- Tests for new behaviour. Don't weaken a test to make it pass.
- Translations: once Weblate is set up, translate there instead of editing `.arb` files.

## Adding a model

A model ships only with a permissive or clearly stated license, a conversion script in
`tools/models/` and a row in [MODELS.md](MODELS.md) (source, upstream SHA-256, license,
conversion, evaluation, known limitations). Packs go into `tools/models/manifest.json`, which CI
signs and publishes on merge; `tools/models/check_manifest.py` fails without the MODELS.md row.

## Reporting

- Bugs and bad results: the issue templates. Photos only if you agree they become public.
- Security issues: privately, see [SECURITY.md](SECURITY.md).

By contributing you agree that your contribution is licensed under Apache-2.0.
Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md).
