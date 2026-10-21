# ADR — архитектурные решения

Формат: MADR (контекст → решение → последствия → альтернативы). Изменение решения — новый ADR со статусом `Proposed`, старый получает `Superseded by ADR-XXXX`.

| ADR | Решение | Статус |
|---|---|---|
| [ADR-0001](ADR-0001-inference-backends.md) | Inference backends | Accepted |
| [ADR-0002](ADR-0002-shared-native-core.md) | Shared native C++ core and refocal-cli | Accepted |
| [ADR-0003](ADR-0003-image-codecs.md) | Image codecs and HEIC | Accepted |
| [ADR-0004](ADR-0004-bandstore.md) | On-disk BandStore | Accepted |
| [ADR-0005](ADR-0005-dart-native-bridge.md) | Dart ↔ native bridge | Accepted |
| [ADR-0006](ADR-0006-threading.md) | Threading model | Accepted |
| [ADR-0007](ADR-0007-state-management.md) | State management: Riverpod 3 | Accepted |
| [ADR-0008](ADR-0008-navigation.md) | Navigation: go_router | Accepted |
| [ADR-0009](ADR-0009-persistence.md) | Persistence: drift (SQLite) | Accepted |
| [ADR-0010](ADR-0010-input-pickers-inbox.md) | System pickers and inbox copies | Accepted |
| [ADR-0011](ADR-0011-model-packs.md) | Model packs and signed manifest | Accepted |
| [ADR-0012](ADR-0012-pipeline.md) | Pipeline engine | Accepted |
| [ADR-0013](ADR-0013-color.md) | Color management | Accepted |
| [ADR-0014](ADR-0014-scales.md) | Scale strategy | Accepted |
| [ADR-0015](ADR-0015-denoise-levels.md) | Discrete denoise levels | Accepted |
| [ADR-0016](ADR-0016-fallback-crash-sentinel.md) | Fallback ladder and crash sentinel | Accepted |
| [ADR-0017](ADR-0017-device-tiers.md) | Device tiers and benchmark | Accepted |
| [ADR-0018](ADR-0018-metadata-ai-marking.md) | Metadata and AI marking | Accepted |
| [ADR-0019](ADR-0019-background-execution.md) | Background execution | Accepted |
| [ADR-0020](ADR-0020-flavors-telemetry.md) | Build flavors and telemetry | Accepted |
| [ADR-0021](ADR-0021-native-crypto.md) | Crypto in native core | Accepted |
| [ADR-0022](ADR-0022-face-models-licensing-defaults.md) | Face models: licensing and safe defaults | Accepted |
| [ADR-0023](ADR-0023-gfpgan-mobile-graph-rewrite.md) | Mobile graph rewrite for StyleGAN2-based face models | Accepted |
| [ADR-0024](ADR-0024-codeformer-split-graph.md) | CodeFormer as a split graph with the fidelity as an input | Accepted |
| [ADR-0025](ADR-0025-effective-resolution.md) | Effective resolution, sharpening and bundled denoise level 0 | Accepted |
| [ADR-0026](ADR-0026-model-license-classes.md) | Model licence classes; new models extend, never replace | Accepted |

## Шаблон

```markdown
# ADR-NNNN: <Title>

- **Статус:** Proposed | Accepted | Superseded by ADR-XXXX
- **Дата:** YYYY-MM-DD

## Контекст
## Решение
## Последствия
## Отклонённые альтернативы
```
