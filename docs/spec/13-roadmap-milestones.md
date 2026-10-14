# 13. Роадмап и вехи

Сроки ориентировочные для команды из 2–3 человек (1 Flutter, 1 native/ML, частично релиз/QA). Привязка к датам — после M0.

```
M0 Спайки ─► 0.1 Internal alpha ─► 0.2 Alpha ─► 0.3 Closed beta ─► 0.5 Public beta ─► 1.0 GA
  4–6 нед       6–8 нед              6–8 нед       6–8 нед            6–8 нед           4–6 нед
                                                                          └─► 1.1 ─► 1.2 ─► 1.3 ─► 2.0
```

## M0 — Спайки

Цель — снять ключевые технические риски до фиксации архитектуры. Каждый спайк завершается отчётом в `docs/spikes/Sx.md` с вердиктом go / no-go / изменить ADR.

| Спайк | Вопрос | Результат | Риск |
|---|---|---|---|
| **S1** | Конвертируется ли GFPGAN 1.4 в ncnn (pnnx) и Core ML без потерь; fp16-переполнения; латентность на 3 Android (флагман SD 8 Gen 2+, средний Mali, low-end) и 2 iPhone (A14, A17) | Таблица паритета (PSNR/LPIPS), латентность; фиксация NFR-PERF-003. **Статус: GO на десктопе ([отчёт](../spikes/S1.md)), нужна перезапись графа (ADR-0023); замеры на устройствах — S1b** | R1 |
| **S2** | Потоковая обработка 12 МП → ×4 → JPEG/PNG/HEIC через BandStore: пиковый RSS ≤ 600 МБ, время I/O, ограничения HeifWriter. **Статус: GO на десктопе ([отчёт](../spikes/S2.md)): пик 212 МБ (T=128), I/O < 1%, швов нет, resume побайтово; S2b — устройства, тепло, батарея, HEIC** | Замеры; фиксация NFR-PERF-001/002, NFR-BAT-001 | R2 |
| **S3** | Матрица Vulkan-драйверов: корректность и стабильность compact/x4plus/GFPGAN на Adreno/Mali/Xclipse/PowerVR | Первичный blocklist, формат, пороги тиров **Статус: GO для механизма ([отчёт](../spikes/S3.md)): гейт корректности ловит мусор GFPGAN-fp16 и 6 видов порчи, sentinel проверен с реальным падением; S3b — Adreno/Mali/PowerVR и калибровка порогов** | R3 |
| **S4** | Core ML: ANE vs GPU для compact/x4plus/GFPGAN, EnumeratedShapes, время компиляции и кэш | Выбор computeUnits по модели; NFR-PERF-021 | R4 |
| **S5** | Жизненный цикл фона: iOS 18/26 (пауза GPU, beginBackgroundTask), Android 14/15/16 (FGS mediaProcessing, onTimeout) | Подтверждение ADR-0019 | R5 |
| **S6** | FFI: 10k событий/джоб, утечки, гонки, задержка отмены | Подтверждение ADR-0005/0006. **Статус: ADR-0005 изменён ([отчёт](../spikes/S6.md)): `NativeCallable.listener` → `Dart_PostCObject` в native port (listener роняет процесс при смерти изолята); 10k событий p99 ≤ 0.2 мс, 0 утечек, отмена ≤ 1 тайла; ADR-0006 подтверждён** | R6 |
| **S7** | CompareViewer на пирамиде тайлов: 60 fps при зуме 48 МП на T1 | Прототип виджета | R7 |
| **S8** | Воспроизводимая сборка F-Droid с native ncnn и Flutter-сабмодулем | Docker-rebuilder, отчёт diffoscope. **Статус: GO ([отчёт](../spikes/S8.md)): две сборки в разных окружениях побайтово равны, подпись Gradle-сборки переносится `apksigcopier`; S8b — `fdroid build` по рецепту fdroiddata** | R8 |
| **S9** (не код) | Юридический разбор лицензий GFPGAN/CodeFormer/FFHQ/DDColor, решение о хостинге NC-весов | Письменное заключение, Q-04 закрыт | R9 |

**Критерии выхода M0:** все спайки с вердиктом; ADR обновлены; эталонная матрица (≥ 6 устройств) доступна; монорепо-скелет и `pr.yml` работают.

## 0.1 — Internal alpha

**Объём:** Android + iOS; пикер → compact 4×/2× → тайлинг + BandStore → слайдер сравнения → сохранение JPEG; ncnn Vulkan/CPU, Core ML; `refocal-cli` + golden CI; crash sentinel; базовые метаданные (ориентация).

**Критерии выхода:**
- 12 МП ×2 без OOM на T1-устройствах матрицы;
- golden PSNR vs fp32 ≥ 35 дБ на обоих бэкендах;
- отмена ≤ 1 тайла;
- APK ≤ 30 МБ, IPA ≤ 40 МБ.

**Статус (2026-10-12), Android-часть готова, проверена на десктопе и в эмуляторе:**

| Пункт | Состояние |
|---|---|
| Пикер → compact 4×/2×/быстрый 2× → слайдер → сохранение JPEG (Android) | ✅ e2e на AOSP API 35 в эмуляторе (`tools/emulator/e2e.sh`): Photo Picker → результат в `Pictures/Refocal` |
| Тайлинг + BandStore, resume, отмена/пауза, NEEDS_USER | ✅ `native/tests/test_job.cpp` (без весов, в CI) |
| ncnn Vulkan/CPU + лестница отказов, crash sentinel, blocklist | ✅ Vulkan проверен на RTX 3060; sentinel/blocklist перенесены из S3 с тестами |
| `refocal-cli` | ✅ `run`/`compare`/`probe`; golden на настоящей модели — только локально, в CI нужен хостинг весов |
| Метаданные: ориентация | ✅ EXIF-ориентация применяется к пикселям; копирование EXIF и AI-маркер — 0.3 |
| iOS, Core ML | ❌ нужен Mac (S4) |
| Критерий: отмена ≤ 1 тайла | ✅ ~3 мс в тесте, ≤ 1 тайл по S6 |
| Критерий: golden ≥ 35 дБ на обоих бэкендах | ✅ CPU vs Vulkan fp16 (RTX) 50.6 дБ; Core ML — нет |
| Критерий: 12 МП ×2 без OOM на T1 | ⚠️ на десктопе пик 454 МБ (Vulkan) / 326 МБ (CPU, быстрый 2×); на устройствах — S2b |
| Критерий: APK ≤ 30 МБ | ✅ ≈ 28.8 МБ (`libenh.so` 9.1 МБ без int8/bf16-ядер ncnn) |

**0.0.2-alpha (2026-10-13)** — промежуточная альфа, взяты пункты 0.3, не требующие Mac и БД:

| Пункт | Состояние |
|---|---|
| Ввод PNG/WebP (FR-IMP-003), HEIC/HEIF/AVIF/GIF/BMP платформой (ADR-0003) | ✅ libpng/libwebp в ядре; Android 11+ — `AImageDecoder` (dlopen, minSdk 29), Android 10 — HEIC→PNG при импорте. Альфа → белый фон (FR-IMP-007 — 0.3), анимация → первый кадр |
| Лимиты входа SEC-INP-002 | ✅ по заголовку до декодирования |
| `metaio` (ADR-0018, FR-META-001/002/003/004/007, PRIV-META-001/002) | ✅ EXIF переписывается (ориентация, размеры, без IFD1/MakerNote/серийников/GPS), ICC, XMP-маркер; `test_codecs` + мутационный фаззинг под ASan. EXIF из HEIC — нет |
| FGS `mediaProcessing` (ADR-0019, FR-BATCH-004 для одного джоба) | ✅ уведомление с Pause/Cancel, `onTimeout` → пауза; на 10–14 тип `dataSync`. Кэшированный FlutterEngine. Очередь — 0.3 |
| Пауза/resume из UI, переживает kill (FR-BATCH-007 для одного джоба) | ✅ каталог джоба — источник истины до drift; список на главном экране |
| Настройки метаданных (FR-SET-002, FR-META-005) | ✅ JSON-файл: drift+sqlite3 (ADR-0009) не помещается в бюджет APK вместе с 0.1 |
| Очистка inbox/jobs (ADR-0010, 07 §1) | ✅ после сохранения и по возрасту 7 дней |
| APK ≤ 30 МБ | ✅ 29.7 МБ (28.3 МиБ; гейт release.yml — 30 МиБ), `libenh.so` 9.5 МБ (+0.4 МБ libpng/libwebp) |

**0.0.3-alpha (2026-10-14)** — промежуточная альфа: экспорт, сила эффекта, приём «Поделиться», l10n:

| Пункт | Состояние |
|---|---|
| Экспорт PNG, WebP lossy/lossless (FR-EXP-001), качество JPEG/WebP и формат по умолчанию (FR-SET-001) | ✅ PNG — потоково (eXIf/iCCP/iTXt XMP); WebP — целиком в памяти, лимит 50 МП (lossless 24 МП), метаданные через WebPMux. HEIC-выход — FR-EXP-002, позже |
| Повторный экспорт без пересчёта (FR-EXP-007), «Сохранить в файл» через SAF (FR-EXP-006) | ✅ любое число экспортов из одного результата |
| Сила эффекта (FR-ENH-005) | ✅ при экспорте: `lerp(lanczos3_up(вход), sr, s)` (поправка ADR-0012); превью — наложение с прозрачностью |
| Режим 1× (FR-ENH-004) | ✅ x4 → ↓4 |
| Приём `ACTION_SEND` image/* (FR-SHARE-001) | ✅ один файл; `SEND_MULTIPLE` — с очередью |
| l10n en/ru (FR-SET-006), онбординг (FR-ONB-001) | ✅ gen-l10n; язык в настройках; онбординг пропускаемый, повтор из настроек |
| ICC источника проверяется при чтении (ADR-0018) | ✅ битый заголовок — профиль не переносится |
| Ревью 0.0.1–0.0.2 | ✅ ориентация WebP с префиксом `Exif`, setjmp в JPEG-декодере, утечка fd в AImageDecoder, лимиты HEIC на Android 10, локализованные уведомления. Открыто: гонки `settings.save`, sweep и `.part` в inbox, FORCE в старых опциях CMake, поправка ADR-0009 (JSON вместо drift), версия в трёх местах |
| APK ≤ 30 МиБ (NFR-SIZE-001) | ✅ 13.6 МБ: нативные библиотеки сжаты в APK (было 29.9 МБ несжатыми; на устройстве распаковываются, ~26 МБ), Dart-символы вынесены (`--split-debug-info`, архив в релизе), simpleomp ncnn вместо libomp (−0.8 МБ, скорость CPU та же: e2e 266–269 с против 265 с). Прогноз до 1.3 — R13 |
| e2e на эмуляторе (basic, background, pause + share) | ✅ AOSP API 35 |

## 0.2 — Alpha

**Объём:** лица (YuNet + GFPGAN-пак с лицензией), strength/faceStrength/region; менеджер моделей (подписанный манифест, докачка, зеркала); тиры + бенчмарк; лестница отказов; Auto v1; уровни денойза.

**Критерии выхода:**
- ArcFace ≥ 0.95 на golden при faceStrength 0.5;
- ни одного необработанного падения на матрице за 100 джобов;
- подделка манифеста/файла отклоняется (TEST-SEC-003/004);
- NFR-PERF-003 выполнен на T1/T2.

## 0.3 — Closed beta (GitHub pre-release APK; TestFlight / Play internal — если Q-06)

**Объём:** очередь + фон (Android FGS, iOS пауза/resume), resume после kill, история-рецепты, пресеты, экспорт JPEG/PNG/WebP/HEIC, metaio + AI-маркер + удаление GPS, share intake (Android intent, iOS Share Extension), онбординг и предупреждение об ИИ, a11y, l10n en/ru, `.rfpack`-импорт, хранилище и очистка.

**Критерии выхода:**
- TEST-INT-003 (resume после kill) зелёный;
- a11y-аудит AA пройден;
- NFR по T1/T2 выполнены на ≥ 80% матрицы;
- фаззинг 1 ч без падений.

## 0.5 — Public beta

**Объём:** GitHub APK, F-Droid (+ Play open testing, если Q-06); паки CodeFormer, x4plus, anime_6B; 8×; side-by-side, синхронный зум, лупа; «Сообщить о плохом результате»; Weblate; RTL.

**Критерии выхода:**
- все NFR на эталонной матрице;
- воспроизводимая F-Droid-сборка (или задокументированное отклонение);
- license check зелёный, MODELS.md полный, bias-отчёт опубликован;
- (если Q-06) Data Safety / Privacy Label поданы.

## 1.0 — GA

**Объём:** стабильный релиз в GitHub и F-Droid (+ App Store и Play production, если Q-06); сайт `refocal.github.io` и документация; юридическая проверка текстов лицензий паков; security review; фаззинг 24 ч; политика приватности опубликована.

**Критерии выхода:**
- crash-free ≥ 99.5% в публичной бете по отчётам тестеров (NFR-REL-001);
- все Must-FR закрыты;
- тексты сторов и приватности утверждены;
- bus factor ≥ 2 (OPS-GOV-005).

## 1.1

Old photo v1: детекция царапин (BOPBTL detector без dlib) + inpaint (MI-GAN/LaMa — выбор спайком, проверка лицензий); удаление JPEG-артефактов (FBCNN, T2); Low-light (выбор модели спайком).

Критерии: golden-категории «old» и «jpeg» с метриками; NR-IQA ≥ базовой обработки.

## 1.2

Колоризация (DDColor tiny при подтверждённой лицензии, иначе альтернатива); face parsing (BiSeNet) для точных масок; планшетный/foldable UX; новые языки.

## 1.3

Android NPU-тир (ORT + QNN, w8a8, отдельная загрузка/флейвор) с golden-гейтом; C2PA; iOS 26 `BGContinuedProcessingTask` (CPU, opt-in); Flutter build hooks.

Критерии: int8 проходит ML-QNT-001; C2PA проходит `c2patool` verify.

## 2.0

Собственные permissive-модели: SPAN-retrain по умолчанию для SR; R&D clean-room face restoration на permissive-данных; HDR/gain map; возможная desktop-сборка из того же core.

Критерии: своя SR ≥ general-x4v3 по NR-IQA при ≤ 50% латентности; face-модель без NC-лицензий с ArcFace ≥ 0.95.

## Зависимости

| Веха | Зависит от |
|---|---|
| 0.1 | S2, S4, S6 |
| 0.2 | S1, S3, S9 (для публикации GFPGAN-пака) |
| 0.3 | S5, S7 |
| 0.5 | S8 |
