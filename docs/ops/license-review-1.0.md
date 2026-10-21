# Pack licence review for 1.0

The 1.0 exit criteria ask for a legal review of the licence texts the app shows for model packs
(13 §1.0). This page is its record: what was checked mechanically, and what needs a person.

## Mechanical check (2026-10-21, manifest serial 7)

For every pack of `tools/models/manifest.json`: the licence text the app downloads
(`license.url`) was fetched, its SHA-256 compared with `license.text_sha256` (what the app
verifies before showing it, ADR-0022), and the text compared with the licence file in the
upstream repository today (whitespace ignored).

| Pack | SPDX | Commercial use | Consent before download | Hash = manifest | Contains upstream licence |
|---|---|---|---|---|---|
| `sr.general-x4v3-dn0` | BSD-3-Clause | yes | no | ✅ | ✅ Real-ESRGAN `LICENSE` |
| `sr.general-x4v3-dn100` | BSD-3-Clause | yes | no | ✅ | ✅ Real-ESRGAN `LICENSE` |
| `sr.x4plus` | BSD-3-Clause | yes | no | ✅ | ✅ Real-ESRGAN `LICENSE` |
| `sr.x4plus-anime6b` | BSD-3-Clause | yes | no | ✅ | ✅ Real-ESRGAN `LICENSE` |
| `face.gfpgan-1.4` | LicenseRef-GFPGAN-NC | **no** | **yes** | ✅ | ✅ GFPGAN `LICENSE` |
| `face.codeformer` | LicenseRef-S-Lab-1.0 | **no** | **yes** | ✅ | ✅ CodeFormer `LICENSE` (S-Lab 1.0) |
| `jpeg.fbcnn` | Apache-2.0 | yes | no | ✅ | ✅ FBCNN `LICENSE` |
| `old.scratch` | MIT | yes | no | ✅ | ✅ Bringing-Old-Photos-Back-to-Life `LICENSE` |
| `old.inpaint-migan` | MIT | yes | no | ✅ | ✅ MI-GAN `LICENSE` and `LICENSE-WEIGHTS` |
| `old.lowlight-cidnet` | MIT | yes | no | ✅ | ✅ HVI-CIDNet `LICENSE` |

Bundled models (`tools/models/models.lock`): `sr.general-x4v3` and `sr.general-x4v3-dn0`
(BSD-3-Clause, Real-ESRGAN), `det.yunet-2023mar` (MIT, opencv_zoo); their notices are in the
app's licence page (`tools/licenses/collect.sh`, OPS-LIC-002).

## For a person to decide

- The two non-commercial face packs: the consent text and the "non-commercial use only" line in
  the offer (06 §3.3) say enough for an Apache-2.0 app that does not sell anything.
- `old.inpaint-migan`: the weights are MIT, but they were trained on Places2, whose terms are for
  research. MODELS.md says so; whether that needs more than the note is a judgement call.
- Store texts (appendix/store-listing.md) are not part of 1.0: no store is used (Q-06).

**1.0 status:** the mechanical check passed. The owner released 1.0 on 2026-10-21 without a
separate legal opinion; the points above stay open for one.
