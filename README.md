# Refocal

**Bring your photos back into focus. On your phone.**

Refocal is an open-source, cross-platform (Flutter, Android + iOS) AI photo enhancer:
upscaling, denoising and face restoration that run **entirely on the device** —
no servers, no accounts, no telemetry.

> Status: **pre-alpha / design phase.** The technical specification lives in
> [`docs/spec/`](docs/spec/README.md) (in Russian). Current milestone: M0 spikes.

## Principles

- **On-device only.** Photos never leave the phone. Network is used only to download models on explicit user action.
- **Honest results.** AI invents details; results are labeled as AI-edited, and you control how much faces may change.
- **Free and open.** Apache-2.0, no ads, no subscriptions.

## Repository layout (planned)

| Path | Contents |
|---|---|
| `app/` | Flutter application |
| `packages/` | `refocal_core`, `refocal_ffi`, `refocal_platform` |
| `native/` | Shared C++ core (ncnn / Core ML backends) |
| `ml/` | Model conversion, evaluation, golden set |
| `spikes/` | M0 technical spikes |
| `docs/spec/` | Technical specification |

## License

Code: [Apache-2.0](LICENSE). Some optional face-restoration models are distributed
by their authors under **non-commercial** licenses and are downloaded separately,
on demand, after you accept their license.
