#!/usr/bin/env python3
"""Writes the SPDX 2.3 SBOM of a release (OPS-REL-002): what goes into the APK.

  (cd app && flutter pub deps --json) > deps.json
  tools/sbom/make_sbom.py VERSION deps.json OUT.spdx.json

Packages: the app; the Dart packages it runs (the dependency closure of the app package without
dev dependencies, from `pub deps`); the Flutter engine; the native libraries built into libenh.so
(git submodules, at their commits); SQLite (package:sqlite3's build hook); the bundled models
(tools/models/models.lock). Licenses of the native parts and models are declared here; the Dart
packages' are not (NOASSERTION; the in-app Licenses screen has their texts).
"""
import datetime, hashlib, json, pathlib, re, subprocess, sys, uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
REPO = "https://github.com/sleepe229/refocal"

# path -> (name, SPDX license); glslang carries several licenses (see its LICENSE.txt).
NATIVE = {
    "native/third_party/ncnn": ("ncnn", "BSD-3-Clause"),
    "native/third_party/ncnn/glslang": ("glslang", "NOASSERTION"),
    "native/third_party/libjpeg-turbo": ("libjpeg-turbo", "IJG AND BSD-3-Clause AND Zlib"),
    "native/third_party/libpng": ("libpng", "libpng-2.0"),
    "native/third_party/libwebp": ("libwebp", "BSD-3-Clause"),
    "native/third_party/json": ("nlohmann-json", "MIT"),
    "native/third_party/monocypher": ("Monocypher", "BSD-2-Clause OR CC0-1.0"),
}
MODELS = {"sr.general-x4v3": "BSD-3-Clause", "det.yunet-2023mar": "MIT"}


def git(*args: str, cwd: pathlib.Path = ROOT) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True,
                          text=True).stdout.strip()


def submodule(path: str) -> tuple[str, str]:
    """(url, commit) of a submodule, nested ones included (its parent must be checked out)."""
    full = ROOT / path
    top = pathlib.Path(git("rev-parse", "--show-toplevel", cwd=full.parent))
    name = str(full.relative_to(top))
    entry = git("ls-tree", "HEAD", name, cwd=top).split()
    if not entry or entry[1] != "commit":
        raise SystemExit(f"{path}: not a submodule")
    paths = git("config", "-f", ".gitmodules", "--get-regexp", r"\.path$", cwd=top)
    key = next(k for k, v in (l.split(" ", 1) for l in paths.splitlines()) if v == name)
    return git("config", "-f", ".gitmodules", key[: -len("path")] + "url", cwd=top), entry[2]


def spdx_id(s: str) -> str:
    return "SPDXRef-" + re.sub(r"[^A-Za-z0-9.-]", "-", s)


def runtime_closure(deps: dict, root: str) -> list[dict]:
    pkgs = {p["name"]: p for p in deps["packages"]}
    seen, todo = set(), [root]
    while todo:
        p = pkgs[todo.pop()]
        if p["name"] in seen:
            continue
        seen.add(p["name"])
        # A workspace package's dev dependencies are not shipped; anything else's are none.
        todo += p.get("directDependencies", p["dependencies"]) if p["kind"] == "root" \
            else p["dependencies"]
    return [pkgs[n] for n in sorted(seen) if n != root]


def main() -> int:
    version, deps_path, out = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    deps = json.loads(deps_path.read_text())
    app = {
        "SPDXID": "SPDXRef-refocal", "name": "refocal", "versionInfo": version,
        "supplier": "Organization: Refocal", "downloadLocation": f"git+{REPO}@v{version}",
        "licenseDeclared": "Apache-2.0", "licenseConcluded": "NOASSERTION",
        "copyrightText": "NOASSERTION", "filesAnalyzed": False,
        "externalRefs": [{"referenceCategory": "PACKAGE-MANAGER", "referenceType": "purl",
                          "referenceLocator": f"pkg:github/sleepe229/refocal@v{version}"}],
    }
    packages = [app]

    def add(p: dict) -> None:
        p.setdefault("licenseConcluded", "NOASSERTION")
        p.setdefault("copyrightText", "NOASSERTION")
        p.setdefault("filesAnalyzed", False)
        packages.append(p)

    for p in runtime_closure(deps, "refocal"):
        if p["source"] == "root":  # the workspace's own packages are part of the app
            continue
        if p["source"] == "sdk":
            add({"SPDXID": spdx_id("dart-" + p["name"]), "name": p["name"],
                 "versionInfo": p["version"], "supplier": "Organization: Flutter",
                 "downloadLocation": "git+https://github.com/flutter/flutter",
                 "licenseDeclared": "BSD-3-Clause"})
            continue
        add({"SPDXID": spdx_id("dart-" + p["name"]), "name": p["name"],
             "versionInfo": p["version"], "supplier": "NOASSERTION",
             "downloadLocation": f"https://pub.dev/packages/{p['name']}/versions/{p['version']}",
             "licenseDeclared": "NOASSERTION",
             "externalRefs": [{"referenceCategory": "PACKAGE-MANAGER", "referenceType": "purl",
                               "referenceLocator": f"pkg:pub/{p['name']}@{p['version']}"}]})

    url, commit = submodule("flutter")
    add({"SPDXID": "SPDXRef-flutter-engine", "name": "flutter-engine",
         "versionInfo": commit, "supplier": "Organization: Flutter",
         "downloadLocation": f"git+{url}@{commit}", "licenseDeclared": "BSD-3-Clause"})
    for path, (name, lic) in NATIVE.items():
        url, commit = submodule(path)
        add({"SPDXID": spdx_id("native-" + name), "name": name, "versionInfo": commit,
             "supplier": "NOASSERTION", "downloadLocation": f"git+{url}@{commit}",
             "licenseDeclared": lic})
    sqlite = next((p for p in deps["packages"] if p["name"] == "sqlite3"), None)
    if sqlite:
        add({"SPDXID": "SPDXRef-native-sqlite", "name": "SQLite",
             "versionInfo": f"built by package:sqlite3 {sqlite['version']}",
             "supplier": "Organization: SQLite", "downloadLocation": "https://sqlite.org",
             "licenseDeclared": "blessing"})
    for line in (ROOT / "tools/models/models.lock").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        mid, file, sha, url = line.split()
        sid = spdx_id(f"model-{mid}")
        if not any(p["SPDXID"] == sid for p in packages):
            add({"SPDXID": sid, "name": mid, "versionInfo": "v1", "supplier": "NOASSERTION",
                 "downloadLocation": url.rsplit("/", 1)[0], "licenseDeclared": MODELS[mid],
                 "checksums": []})
        next(p for p in packages if p["SPDXID"] == sid)["checksums"].append(
            {"algorithm": "SHA256", "checksumValue": sha})

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    doc = {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"refocal-{version}",
        "documentNamespace": f"{REPO}/releases/v{version}/sbom-{uuid.uuid4()}",
        "creationInfo": {"created": now, "creators": ["Tool: tools/sbom/make_sbom.py"]},
        "packages": packages,
        "relationships": [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES",
                           "relatedSpdxElement": "SPDXRef-refocal"}] + [
            {"spdxElementId": "SPDXRef-refocal", "relationshipType": "CONTAINS",
             "relatedSpdxElement": p["SPDXID"]} for p in packages[1:]],
    }
    out.write_text(json.dumps(doc, indent=1) + "\n")
    print(f"{out}: {len(packages)} packages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
