# Translations on Weblate (NFR-L10N-005)

Translators work on [Hosted Weblate](https://hosted.weblate.org/) (free for libre projects);
Weblate opens pull requests with `.arb` changes. The Dart localization classes are generated
from the `.arb` files by every `flutter pub get` and build, so a new language needs nothing but
its `app/lib/l10n/app_<code>.arb`: the language list in Settings is built from them.

## One-time setup (maintainer)

Done 2026-10-17: <https://hosted.weblate.org/projects/refocal/>. The merge and add-on commit
templates have no `{{ author }}`; they are signed off as `Hosted Weblate <hosted@weblate.org>`.


1. Sign in to hosted.weblate.org with GitHub and apply for libre hosting:
   <https://hosted.weblate.org/hosting/> → project **Refocal**, URL
   `https://github.com/sleepe229/refocal`, license Apache-2.0. Approval is manual.
2. Project settings: web `https://github.com/sleepe229/refocal`, translation instructions link
   to this file, **Commit message** templates end with `Signed-off-by: {{ author }}` (DCO,
   OPS-GOV-001; the `dco` check compares it with the commit author).
3. Component **App**:

   | Setting | Value |
   |---|---|
   | Version control | GitHub pull requests |
   | Source code repository | `https://github.com/sleepe229/refocal.git` |
   | Repository branch / push branch | `main` / `weblate` |
   | File format | ARB file |
   | File mask | `app/lib/l10n/app_*.arb` |
   | Monolingual base language file | `app/lib/l10n/app_en.arb` |
   | Template for new translations | `app/lib/l10n/app_en.arb` |
   | Source language | English |
   | Language code style | Default based on the file format |
   | License | Apache-2.0 |
   | Translation flags | `icu-message-format` |

   Weblate pushes through the GitHub app or a bot account's token (Settings → VCS); give it
   access to this repository only.
4. Add-ons: "Squash Git commits" (per language), "Cleanup translation files".
5. Lock the existing `ru` translation to its maintainers if needed; English (`app_en.arb`) is
   edited in the repository only.
6. Add the Weblate badge and link to README and CONTRIBUTING.

## Reviewing a Weblate pull request

- CI is the same as for any PR: `flutter pub get` regenerates the classes, analyze and tests run
  with the new strings; gen-l10n fails on broken ICU placeholders.
- Check that new languages render: plural forms, long words in buttons (tests run at 200% text
  only in English and Russian), right-to-left languages (NFR-L10N-003).
- A language appears in the app when its file is merged; there is no completeness threshold,
  missing strings fall back to English.
