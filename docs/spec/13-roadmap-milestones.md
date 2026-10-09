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
| **S6** | FFI: 10k событий/джоб, утечки, гонки, задержка отмены | Подтверждение ADR-0005/0006 | R6 |
| **S7** | CompareViewer на пирамиде тайлов: 60 fps при зуме 48 МП на T1 | Прототип виджета | R7 |
| **S8** | Воспроизводимая сборка F-Droid с native ncnn и Flutter-сабмодулем | Docker-rebuilder, отчёт diffoscope | R8 |
| **S9** (не код) | Юридический разбор лицензий GFPGAN/CodeFormer/FFHQ/DDColor, решение о хостинге NC-весов | Письменное заключение, Q-04 закрыт | R9 |

**Критерии выхода M0:** все спайки с вердиктом; ADR обновлены; эталонная матрица (≥ 6 устройств) доступна; монорепо-скелет и `pr.yml` работают.

## 0.1 — Internal alpha

**Объём:** Android + iOS; пикер → compact 4×/2× → тайлинг + BandStore → слайдер сравнения → сохранение JPEG; ncnn Vulkan/CPU, Core ML; `refocal-cli` + golden CI; crash sentinel; базовые метаданные (ориентация).

**Критерии выхода:**
- 12 МП ×2 без OOM на T1-устройствах матрицы;
- golden PSNR vs fp32 ≥ 35 дБ на обоих бэкендах;
- отмена ≤ 1 тайла;
- APK ≤ 30 МБ, IPA ≤ 40 МБ.

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
