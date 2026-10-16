# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through
[GitHub Private Vulnerability Reporting](https://github.com/sleepe229/refocal/security/advisories/new),
not in public issues. Useful details: the version, the device and OS, the input that triggers it
(a crafted image, model pack or manifest) and what happens.

What to expect:

| Step | Time |
|---|---|
| Acknowledgement | within 72 hours |
| Assessment | within 7 days |
| Fix for critical and high severity | within 30 days |
| Public disclosure | after the fix, at the latest 90 days after the report |

You will be credited in the CHANGELOG if you wish.

## Supported versions

Only the latest minor release gets security fixes.

## Scope

The app decodes untrusted images and model packs on the device (`native/`, fuzzed in CI) and
verifies the signed model manifest (ADR-0011, ADR-0021). Reports about these are especially
welcome. Release APKs come with SHA256SUMS, an SPDX SBOM and GitHub build provenance and SBOM
attestations (`gh attestation verify <apk> --repo sleepe229/refocal`).
