# Governance

## Roles (OPS-GOV-002)

| Role | What | Who |
|---|---|---|
| Maintainer | Merges pull requests, tags and publishes releases, decides on ADRs | @sleepe229 |
| Reviewer | Reviews pull requests in an area they know; approves but does not merge | open |
| Key holder | Holds a copy of the release signing key or the offline model-manifest key B | @sleepe229 |

The specification asks for at least two key holders and two people who can release
(bus factor ≥ 2, OPS-GOV-005) before 1.0. Until a second maintainer joins, a single maintainer
releases alone (SEC-CI-003 amendment of 2026-10-16 in
[09-security](docs/spec/09-security.md); [docs/ops/release.md](docs/ops/release.md)); this is a
known gap, not the target.

## Decisions

- Day-to-day changes: pull requests, merged by a maintainer once CI is green.
- Architecture: ADRs in [`docs/spec/adr/`](docs/spec/adr/README.md). A disputed change is decided
  by lazy consensus of the maintainers: it passes if no maintainer objects within 72 hours.
- The [prohibited features](CONTRIBUTING.md#not-accepted) are not up for a vote.

## Becoming a reviewer or maintainer

Contribute and review for a while; a maintainer then proposes you in an issue, and you join if
no maintainer objects within 72 hours. Maintainers who become key holders keep their copies of
the keys offline (docs/ops/release.md).
