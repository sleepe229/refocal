# 11. CI/CD и релизы

## 1. Пайплайны GitHub Actions

| Workflow | Триггер | Шаги | Время |
|---|---|---|---|
| `pr.yml` | PR, push в `main` | format check (`dart format`, `clang-format`), `flutter analyze`, `clang-tidy`; Dart unit/widget; golden UI; C++ gtest (Linux, ASan/UBSan); фаззинг 5 мин; `refocal-cli` golden (ncnn CPU); license check; size gate; проверка разрешений и PrivacyInfo; build APK (play, fdroid) и iOS (без подписи) | ≤ 25 мин |
| `ml.yml` | PR с изменениями в `ml/` | smoke-конверсия compact-модели, паритет vs PyTorch, проверка MODELS.md | ≤ 20 мин |
| `macos.yml` | PR с изменениями в native/ios | `refocal-cli` golden на Core ML (macOS runner, Apple Silicon), iOS-симулятор Patrol | ≤ 30 мин |
| `nightly.yml` | cron 02:00 UTC | Patrol на эмуляторах (API 29/34/36, AOSP без GMS), iOS-симуляторы; NR-IQA и ArcFace; фаззинг 1 ч; сетевой эгресс; device farm perf | ≤ 3 ч |
| `release.yml` | тег `v*` | сборка, подпись, SBOM, attestations, загрузка в каналы (§4) | ≤ 60 мин |
| `packs.yml` | ручной (`workflow_dispatch`) | сборка паков из `ml/packs/*.yaml`, eval, загрузка файлов на HF + GitHub Release; **подпись манифеста — офлайн** (§5) | — |

| ID | Требование | Приоритет | Релиз |
|---|---|---|---|
| OPS-CI-001 | PR не сливается без зелёного `pr.yml` и ревью мейнтейнера | Must | R0.1 |
| OPS-CI-002 | Кэш Gradle, CocoaPods, pub, ccache для native — время PR ≤ 25 мин (NFR-MNT-006) | Must | R0.1 |
| OPS-CI-003 | Тулчейны закреплены: Flutter (сабмодуль + FVM), NDK, CMake, Xcode, Python `requirements.lock` | Must | R0.1 |
| OPS-CI-004 | Ночные падения создают issue автоматически (label `nightly-failure`) | Should | R0.3 |
| OPS-CI-005 | Size gate: рост APK > 500 КБ в PR требует пометки `size-approved` | Should | R0.2 |

## 2. Версионирование

- Приложение: SemVer `MAJOR.MINOR.PATCH`, `pubspec: x.y.z+build`; `versionCode = MAJOR*1_000_000 + MINOR*1_000 + PATCH` (×10 + ABI-сплит при необходимости).
- Conventional Commits; **release-please** формирует CHANGELOG.md, PR релиза и `fastlane/metadata/android/<locale>/changelogs/<versionCode>.txt`.
- Паки моделей — независимые версии `id@semver`; манифест — монотонный `serial`.
- C ABI — `enh_version()` + `ENH_ABI_VERSION`; несовместимое изменение ABI — мажорная версия native-пакета.

## 3. Подпись

| Платформа | Схема |
|---|---|
| Android (play, если Q-06) | Upload key в GitHub Environment `release` (base64 keystore + пароль), Play App Signing |
| Android (GitHub/F-Droid) | Отдельный release key; при воспроизводимой сборке F-Droid публикует APK с этой подписью (COMP-FDR-004) |
| iOS (если Q-06) | Fastlane `match` (сертификаты в приватном зашифрованном репозитории) или App Store Connect API key; Environment `release` |
| Манифест моделей | minisign, офлайн, 2 хранителя (SEC-SUP-005) |

## 4. Каналы дистрибуции

| Канал | Артефакт | Поток |
|---|---|---|
| GitHub Releases | APK arm64-v8a (Q-03) + `SHA256SUMS` + SBOM (CycloneDX) + attestations | Каждый тег; pre-release для бет (0.3) |
| Google Play *(если Q-06)* | AAB | internal → closed (бета) → open testing → production (staged rollout 10% → 50% → 100%, по 2 дня, стоп при crash-rate > 1%) |
| App Store *(если Q-06)* | IPA | TestFlight (internal → external) → App Review → phased release 7 дней |
| F-Droid | Сборка F-Droid по тегу (`UpdateCheckMode: Tags`) | Автоматически после тега |
| Hugging Face / GitHub Releases | Паки + подписанный манифест | `packs.yml` + офлайн-подпись |

| ID | Требование | Приоритет | Релиз |
|---|---|---|---|
| OPS-REL-001 | Релизы собираются только в CI из тега на `main`; локальные сборки не публикуются | Must | R0.3 |
| OPS-REL-002 | Каждый релиз: CHANGELOG, SHA256SUMS, SBOM, attestations | Must | R0.5 |
| OPS-REL-003 | Staged rollout и критерии остановки (crash-rate > 1%, массовые жалобы на качество) | Must | R1.0 |
| OPS-REL-004 | Откат: Play — остановка rollout и выпуск PATCH; App Store — остановка phased release; паки — новый манифест с большим `serial`, возвращающий предыдущую версию пака | Must | R1.0 |
| OPS-REL-005 | Чек-лист релиза (`docs/ops/release-checklist.md`): пересмотр 08 (политики сторов), лицензий, privacy labels, скриншотов | Must | R0.5 |
| OPS-REL-006 | Ритм: минорные релизы ~каждые 6–8 недель; PATCH — по необходимости; security-фиксы — вне ритма | Should | R1.0 |

## 5. Публикация модельных паков

1. PR с `ml/packs/<id>.yaml` (источник, лицензия, параметры конверсии) → `ml.yml` (smoke + паритет).
2. После мержа — `packs.yml`: конверсия всех целей, eval на golden, генерация фрагмента манифеста, загрузка файлов на HF и в GitHub Release `packs-<id>-<ver>`.
3. Мейнтейнер-хранитель офлайн: собирает итоговый `manifest.json` (`serial += 1`), проверяет хэши, подписывает `minisign -S`, загружает `manifest.json` + `.minisig`.
4. CI-проверка опубликованного манифеста: подпись, доступность всех URL, совпадение SHA-256 (nightly).

## 6. Окружения и секреты

| Environment | Секреты | Защита |
|---|---|---|
| `release` | Android keystore, Play service account JSON, App Store Connect API key, match password | Обязательный ревьюер, только теги `v*` |
| `packs` | HF token (write), GitHub token (releases) | Обязательный ревьюер |
| — | Ключ манифеста | **Не хранится в CI** |
