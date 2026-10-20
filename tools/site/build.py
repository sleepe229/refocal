#!/usr/bin/env python3
"""Builds the project site (refocal on GitHub Pages, .github/workflows/site.yml) into OUT.

The texts are not duplicated: the landing page is the store description
(fastlane/metadata/android/en-US), the privacy page is PRIVACY.md (07 §7). Needs the
`markdown` package.

    tools/site/build.py OUT
"""

import html
import pathlib
import sys

import markdown

ROOT = pathlib.Path(__file__).resolve().parents[2]
REPO = "https://github.com/sleepe229/refocal"

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{summary}">
<link rel="icon" href="icon.png">
<style>
:root {{
  color-scheme: light dark; --fg: #1b1b1f; --bg: #fdfcff; --muted: #5d5e66; --link: #2f5bd3;
}}
@media (prefers-color-scheme: dark) {{
  :root {{ --fg: #e4e2e6; --bg: #121316; --muted: #a9a9b2; --link: #9db6ff; }}
}}
body {{ margin: 0; background: var(--bg); color: var(--fg);
  font: 17px/1.55 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
main {{ max-width: 44rem; margin: 0 auto; padding: 2rem 16px 4rem; }}
header {{ display: flex; align-items: center; gap: 12px; }}
header img {{ width: 48px; height: 48px; border-radius: 12px; }}
header a {{ color: inherit; text-decoration: none; font-weight: 600; font-size: 1.3rem; }}
a {{ color: var(--link); }}
.summary {{ font-size: 1.15rem; color: var(--muted); }}
.links a {{ margin-right: 1.2rem; white-space: nowrap; }}
footer {{ margin-top: 3rem; color: var(--muted); font-size: .9rem; }}
</style>
</head>
<body>
<main>
<header><img src="icon.png" alt=""><a href="./">Refocal</a></header>
{body}
<footer>Apache-2.0 · <a href="{repo}">Source code</a> · <a href="privacy">Privacy</a></footer>
</main>
</body>
</html>
"""


def page(title: str, summary: str, body: str) -> str:
    return PAGE.format(title=html.escape(title), summary=html.escape(summary), body=body, repo=REPO)


def main(out: pathlib.Path) -> None:
    meta = ROOT / "fastlane/metadata/android/en-US"
    summary = (meta / "short_description.txt").read_text(encoding="utf-8").strip()
    # The store description is HTML already (F-Droid's subset).
    description = (meta / "full_description.txt").read_text(encoding="utf-8")
    links = (
        f'<p class="links"><a href="{REPO}/releases">Download (GitHub Releases)</a>'
        f'<a href="{REPO}/blob/main/CHANGELOG.md">What\'s new</a>'
        f'<a href="{REPO}/issues">Report a problem</a></p>'
    )
    index = f'<h1>Refocal</h1><p class="summary">{html.escape(summary)}</p>{links}{description}'

    policy = (ROOT / "PRIVACY.md").read_text(encoding="utf-8")
    # Relative links in PRIVACY.md point into the repository.
    policy = policy.replace("](SECURITY.md)", f"]({REPO}/blob/main/SECURITY.md)")
    privacy = markdown.markdown(policy)

    out.mkdir(parents=True, exist_ok=True)
    (out / "index.html").write_text(page("Refocal", summary, index), encoding="utf-8")
    (out / "privacy.html").write_text(
        page("Refocal privacy policy", "Refocal collects no data.", privacy), encoding="utf-8"
    )
    (out / "icon.png").write_bytes((meta / "images/icon.png").read_bytes())


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(pathlib.Path(sys.argv[1]))
