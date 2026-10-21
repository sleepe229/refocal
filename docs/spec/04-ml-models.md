# 04. ML-модели

Маркировка достоверности: **[V]** — проверено по первоисточнику при подготовке ТЗ; **[R]** — по памяти/вторичным источникам, перепроверить до фиксации (задача S9 и ML-REG-002).

## 1. Реестр моделей

| ID пака | Назначение | Архитектура | Параметры | Размер fp16 | Лицензия кода / весов | Поставка | Тир | Релиз |
|---|---|---|---|---|---|---|---|---|
| `det.yunet-2023mar` | Детекция лиц + 5 точек | YuNet | ~75k | < 0.3 МБ | MIT [V] | **встроена** | T0+ | R0.2 |
| `sr.general-x4v3` | SR/денойз, по умолчанию | SRVGGNetCompact | ~1.2M [R] | ~2.3 МБ | BSD-3 [R] | **встроена** (уровень денойза 0.5) | T0+ | R0.1 |
| `sr.general-x4v3-dn` | Уровни денойза 0 и 1.0 | то же (DNI) | ~1.2M | ~2.3 МБ × 2 | BSD-3 | пак «Compact+» | T0+ | R0.2 |
| `sr.x4plus` | HQ SR | RRDBNet 23 блока | 16.7M [R] | ~32 МБ | BSD-3 | пак | T2 | R0.5 |
| `sr.x4plus-anime6b` | Аниме/арт | RRDBNet 6 блоков | ~4.5M [R] | ~9 МБ | BSD-3 | пак | T1+ | R0.5 |
| `face.gfpgan-1.4` | Восстановление лиц | GFPGANv1Clean (+ ADR-0023) | 86.4M, 398 GFLOPs [S1] | 177 МБ ncnn / 176 МБ Core ML [S1] | Apache-2.0 код; NC-составляющие (см. §3) | пак, **NC, согласие** | T1+ (T0 — CPU, 1 лицо) | R0.2 |
| `face.codeformer` | Лица, с fidelity | CodeFormer | 94.4M [V] | ~189 МБ | S-Lab License 1.0 (NC) [V] | пак, **NC, согласие** | T2 | R0.5 |
| `jpeg.fbcnn` | Удаление JPEG-артефактов | FBCNN | ~70M [R] | ~140 МБ | Apache-2.0 [V] | пак | T2 | R1.1 |
| `old.scratch-det` | Детекция царапин | U-Net из BOPBTL | — | — | MIT [V] | пак | T1+ | R1.1 |
| `old.inpaint` | Заполнение царапин | MI-GAN / LaMa (выбор — спайк) | — | — | проверить | пак | T1+ | R1.1 |
| `color.ddcolor-tiny` | Колоризация | DDColor paper_tiny | — | ~220 МБ fp32 [V] | Apache-2.0 код и веса (HF `piddnad/ddcolor_paper_tiny`) [V] | пак | T1+ | R1.2 |
| `parse.bisenet` | Маски лица/волос | BiSeNet | ~13M [R] | ~26 МБ | MIT код; данные CelebAMask-HQ NC [R] | пак, NC | T1+ | R1.2 |
| `sr.lsdir-compact` | SR, реальные деградации (кандидат) | SRVGGNetCompact (4xLSDIRCompactR3 / C3, Phhofm) | ~1.2M | ~2.3 МБ | CC-BY-4.0 [V] | пак (ADR-0026), рядом с general-x4v3 | T0+ | R1.1 (S11) |
| `sr.nomos-span` | SR, реальные деградации (кандидат) | SPAN (4xNomos8k_span_otf medium/strong) | ~0.5M | ~1 МБ | CC-BY-4.0 [V] | пак | T0+ | R1.1 (S11) |
| `sr.nomos-compact-x2` | Родной 2x (кандидат) | SRVGGNetCompact (2xNomosUni_compact_otf_medium) | ~1.2M | ~2.3 МБ | CC-BY-4.0 [V] | пак; нужен x2-путь в ядре | T0+ | R1.1 (S11) |
| `sr.webphoto-realplksr` | HQ SR рядом с x4plus (кандидат) | RealPLKSR 64dim/28 блоков, PixelShuffle (4xNomosWebPhoto_RealPLKSR) | ~7.4M [R] | ~15 МБ | CC-BY-4.0 [V] | пак | T2 | R1.2 |
| `sr.public-realplksr-x2` | HQ 2x, permissive (кандидат) | RealPLKSR + DySample + LayerNorm (2xPublic_realplksr_dysample_layernorm_real) | ~7M [R] | ~14 МБ | Apache-2.0 [V] | пак; нужен Vulkan GridSample | T2 | R1.2 |
| `face.restoreformerpp` | Лица, лучшая идентичность (кандидат) | RestoreFormer++ | — | — | Apache-2.0 код и веса — релиз `v1.0.0` репозитория [V] | пак с согласием (лица, FFHQ; ADR-0022) | T1+ | R1.3 |
| `face.vqfr` | Лица с регулятором fidelity (кандидат) | VQFR | — | — | Apache-2.0 код и веса — релизы `v1.0.0`/`v2.0.0`, NC-компонентов в LICENSE нет [V] | пак с согласием (лица, FFHQ) | T1+ | R1.3 |
| `denoise.scunet` | Слепое шумоподавление реальных фото (кандидат) | SCUNet `color_real_psnr` / DRUNet | 17.9M / 32.6M [V] | ~36 / ~65 МБ | веса — релиз `cszn/KAIR` v1.0, MIT [V] | пак; категория `denoise` в схеме | T1+ | R1.3 |
| `face.gen-*` | Генеративные лица, эксперимент | одношаговая диффузия (OSDFace / PMRF / InterLCM — S12) | 160M–1B | до ~2 ГБ | OSDFace и InterLCM — NC [V]; PMRF — MIT [V] (проверить стадию SwinIR из DifFace) | пак, только явное включение, никогда не Auto | T2 + NPU | R1.5 |
| `sr.span-real` | Своя permissive SR | SPAN/SPANV2 retrain | ~0.15M | < 1 МБ | Apache-2.0 (своя) | встроена (замена general-x4v3) | T0+ | R2.0 (R&D) |

### Отклонённые модели

| Модель | Причина |
|---|---|
| SwinIR, HAT | Тяжёлые (HAT 20.8M / 102 GMACs [V]), window attention плохо экспортируется и не ложится на NPU. HAT — только как офлайн-эталон/учитель. |
| SCRFD, ArcFace (InsightFace) | Только некоммерческое исследовательское использование [V]. ArcFace допускается **только офлайн** для оценки в `ml/eval`. |
| MediaPipe BlazeFace | Только short-range, слаб на мелких/групповых лицах. |
| DiffBIR | 50 шагов, 3B параметров; в составе DifFace (S-Lab NC) и SD 2.1 (OpenRAIL-M) [V]. Одношаговые OSDFace, InterLCM, PMRF перенесены в экспериментальные (`face.gen-*`, R1.5): на кропе лица 512 и NPU это около 0.1–0.3 с [V, Qualcomm AI Hub SD 2.1], а на весь кадр по-прежнему нереально. |
| Официальный SPAN / NTIRE ESR | Обучены на бикубической деградации (PSNR) — не справляются с реальными фото. Версии сообщества, переобученные на реальных деградациях (`sr.nomos-span`), — кандидаты R1.1. |
| NAFNet, Restormer (deblur) | Спайк S10 (ветка `spike/s10-defocus`): Restormer — 225 с и 1.2 ГБ на 0.3 МП на CPU, после SR — полосы на лицах; NAFNet GoPro почти не меняет фото, REDS «рисует» лица. Возврат — только на NPU (R1.4). |
| 4xRealWebPhoto_v4_dat2, v3_atd | DAT2/ATD (window attention, 80–140 МБ) — не для телефона; офлайн-эталон и учитель для дистилляции (R2.0). |
| ClearRealityV1, UltraSharpV2 | CC-BY-NC-SA-4.0 [V]; ниже приоритетом, чем CC-BY-кандидаты с тем же графом. |
| GPEN, OneRestore | Нет лицензии; модели GPEN отозваны автором [V]. |

### Источники кандидатов R1.1–R1.5 (проверено 2026-10-21)

Кандидаты только добавляются рядом с текущими моделями (ADR-0026). Класс лицензии проверяется по первоисточнику до публикации пака (ML-REG-002). Сравнений этих моделей с Real-ESRGAN Compact по MUSIQ, CLIP-IQA и MANIQA никто не публиковал — выигрыш доказывает S11 на нашем golden-наборе.

| Кандидат | Источник лицензии | Замечания для ncnn |
|---|---|---|
| 4xLSDIRCompactR3 / C3 | <https://openmodeldb.info/models/4x-LSDIRCompactR3>, <https://openmodeldb.info/models/4x-LSDIRCompactC3> | Граф `general-x4v3`, drop-in |
| 4xNomos8k_span_otf | <https://openmodeldb.info/models/4x-Nomos8k-span-otf-strong>; SPAN — Apache-2.0, <https://github.com/hongyuanyu/SPAN> | Экспорт после репараметризации Conv3XC; порт на ncnn есть (tntwise/SPAN-ncnn-vulkan) |
| 2xNomosUni_compact_otf_medium | <https://openmodeldb.info/models/2x-NomosUni-compact-otf-medium> | Граф Compact, масштаб 2 |
| 4xNomosWebPhoto_RealPLKSR | <https://openmodeldb.info/models/4x-NomosWebPhoto-RealPLKSR>; PLKSR — MIT, <https://github.com/dslisleedh/PLKSR> | Свёртка 17×17, GroupNorm по тайлу (швы), pad ≥ рецептивного поля |
| 2xPublic_realplksr_dysample_layernorm_real | <https://github.com/Phhofm/models/releases/tag/2xPublic_realplksr_dysample_layernorm_real> | DySample → `F.grid_sample`; у ncnn нет Vulkan-слоя GridSample |
| RestoreFormer++ | <https://github.com/wzhouxiff/RestoreFormerPlusPlus> | Deg 29.63 против 37.28 у CodeFormer (таблица PMRF, CelebA-Test) |
| VQFR | <https://github.com/TencentARC/VQFR> | Регулятор fidelity `-f` |
| SCUNet, DRUNet | <https://github.com/cszn/SCUNet>, <https://github.com/cszn/DPIR> | SCUNet — окна Swin (roll, reshape); DRUNet — простой CNN |
| DDColor tiny | <https://huggingface.co/piddnad/ddcolor_paper_tiny> | — |
| OSDFace | <https://github.com/jkwang28/OSDFace> (NC academic) | SD 2.1 UNet, 978M; реалистично только на NPU |
| PMRF | <https://github.com/ohayonguy/PMRF>, <https://huggingface.co/ohayonguy/PMRF_blind_face_image_restoration> (MIT) | 160M × K шагов; neighborhood attention — своё ядро |
| InterLCM | <https://github.com/sen-mao/InterLCM> (CC BY-NC 4.0) | 1–3 шага LCM |

## 2. Требования к моделям (ML)

| ID | Требование | Приоритет | Релиз | Критерий приёмки | Трассировка |
|---|---|---|---|---|---|
| ML-REG-001 | Каждая модель имеет запись в `MODELS.md`: источник, коммит/релиз upstream, SHA-256 исходных весов, лицензия, команды конверсии, квантизация, результаты оценки, известные ограничения/bias | Must | R0.1 | Ревью; CI проверяет наличие записи для каждого id в манифесте | TEST-COMP-004 |
| ML-REG-002 | Лицензия каждой модели проверена по первоисточнику до публикации пака | Must | R0.2 | Чек-лист в PR пака | S9 |
| ML-REG-003 | Встроенные в приложение модели — только permissive (MIT/BSD/Apache) | Must | R0.1 | license-check | ADR-0022 |
| ML-DET-001 | Детектор: recall ≥ 0.85 на лицах ≥ 24 px в golden-наборе, ложные срабатывания ≤ 1 на 20 фото без лиц | Must | R0.2 | TEST-ML-002 | — |
| ML-SR-001 | Выход мобильных бэкендов совпадает с PyTorch fp32 (см. NFR-QLT-001) | Must | R0.1 | TEST-ML-005 | — |
| ML-SR-002 | Нет видимых швов при тайлинге (NFR-QLT-003) | Must | R0.1 | TEST-ML-007 | — |
| ML-FACE-001 | ArcFace cos ≥ 0.95 при faceStrength 0.5 | Must | R0.2 | TEST-ML-003 | — |
| ML-FACE-002 | Проверка NaN/Inf на выходе face-модели; при обнаружении — повтор в fp32 CPU, затем пропуск лица | Must | R0.2 | TEST-FAULT-003 | ADR-0016 |
| ML-FACE-003 | Маска вставки без видимого шва (erode + feather) | Must | R0.2 | визуальное ревью golden + метрика градиента | — |
| ML-FACE-004 | Color match: ΔE средних в LAB ≤ 3 | Should | R0.2 | TEST-ML-002 | — |
| ML-BIAS-001 | Оценка качества по подгруппам golden-лиц (тон кожи по шкале Monk, возраст, очки, профиль) публикуется в MODELS.md | Must | R0.5 | TEST-ML-008 | [15](15-ethics-responsible-ai.md) |
| ML-QNT-001 | Квантизованная (int8) модель допускается только при выполнении golden-гейта (PSNR ≥ 35 дБ, LPIPS ≤ 0.02 vs fp32) | Must | R1.4 | TEST-ML-005 | — |

## 3. Лицензионный анализ face-моделей

**GFPGAN v1.4** [V]:

- код — Apache-2.0;
- LICENSE перечисляет сторонние компоненты: StyleGAN2 (код rosinality, MIT) со ссылкой на **NVIDIA Source Code License** (некоммерческое, «research or evaluation only»); части, адаптированные из DFDNet (CC BY-NC-SA 4.0);
- обучение на **FFHQ** (CC BY-NC-SA 4.0); распространяется ли лицензия датасета на веса — юридически не определено.

**CodeFormer** [V]: S-Lab License 1.0 — разрешено распространение для **некоммерческих** целей в исходном и бинарном виде, с модификациями или без, при сохранении уведомления об авторских правах (в документации бинарных форм); запрет использовать имена авторов для продвижения; коммерческое использование — по согласованию с авторами.

**Решение** ([ADR-0022](adr/ADR-0022-face-models-licensing-defaults.md)):

1. Face-модели не встраиваются в приложение и не хранятся в основном репозитории под Apache-2.0.
2. Поставляются как отдельные паки с собственной лицензией, отображаемой и принимаемой в приложении.
3. Проект некоммерческий — условия NC соблюдаются; донаты — GitHub Sponsors/Liberapay на развитие кода, без привязки к NC-моделям, подключаются после S9 (Q-10).
4. В F-Droid это не вызывает `NonFreeAssets` для APK (веса не в APK), но опциональная загрузка декларируется в описании.
5. Долгосрочно (R2.0) — исследование clean-room face-модели на permissive-данных.

## 4. Pre/post-processing

### 4.1 SR (Real-ESRGAN семейство)

| Параметр | Значение |
|---|---|
| Вход | RGB, float, диапазон [0, 1], NCHW (ncnn — свой формат Mat, Core ML — MLMultiArray/CVPixelBuffer) |
| Выход | RGB [0, 1], clamp, ×255, round |
| Масштаб | ×4 |
| Цветовое пространство | Как во входе (gamma-encoded), без линеаризации (ADR-0013) |
| Тайл | 128 / 256 / 512 входа, pad 16 (x4plus — 24), reflect на краях изображения |
| Альфа | Отдельно Lanczos ×scale |

### 4.2 Детектор YuNet

- Вход: изображение, уменьшенное до 640 по длинной стороне, BGR (как в OpenCV Zoo), фиксированная форма для варианта `2023mar` (паддинг до 640×640).
- Порог score ≥ 0.7, NMS IoU 0.3, минимальный размер лица 24 px во входе.
- Выход: bbox + 5 точек (глаза, нос, углы рта) → масштабирование в координаты исходного входа.

### 4.3 Выравнивание и вставка лица

- Шаблон FFHQ-512 (5 точек, как в facexlib) [R — сверить с `facexlib/utils/face_restoration_helper.py`]:

```
[[192.98, 239.95], [318.90, 240.19], [256.63, 314.02], [201.26, 371.41], [313.09, 371.15]]
```

- Similarity transform (`estimateAffinePartial2D`-эквивалент, LMEDS) по 5 точкам → кроп 512×512 bicubic **из входа**.
- Вход face-модели: RGB, [-1, 1] (GFPGAN/CodeFormer), NCHW 1×3×512×512 статично.
- Обратная аффинная матрица умножается на `scale` → варп восстановленного патча сразу в **координаты выхода**.
- Маска: белый квадрат 512² → erode 2–4% → Gaussian feather ~5% размера → варп той же матрицей.
- Color match (опц.): выравнивание среднего и σ в LAB патча под SR-фон в области маски.
- Бленд: `px = lerp(px_sr, patch, mask × faceStrength × perFace[k])`.

### 4.4 Смешивание по силе

`out = lerp(lanczos_up(input), model_out, strength)` полосой, в 8-бит с округлением; для `Region.face` маска фона = 0, для `Region.background` маска лиц = 0.

## 5. Конвейер конверсии (`ml/convert`)

```
upstream .pth ──► PyTorch (eval, fixed seed, randomize_noise=False)
   ├─► ONNX opset 17, статические формы (тайлы 128/256/512; лица 512)
   │      └─► onnxsim ──► pnnx ──► ncnn .param/.bin (fp16 storage)
   └─► coremltools (torch.export / TorchScript) ──► mlprogram, FLOAT16,
          EnumeratedShapes {128,256,512}, iOS16 target ──► .mlpackage
   (R1.4) └─► ONNX ──► ORT QNN (w8a8, QAT/PTQ + golden-гейт)
```

| ID | Требование | Приоритет | Релиз |
|---|---|---|---|
| ML-CNV-001 | Конверсия воспроизводима: зафиксированные версии (requirements.lock), скрипт `make pack ID=…`, вывод SHA-256 совпадает между запусками | Must | R0.1 |
| ML-CNV-002 | GFPGAN: `GFPGANv1Clean`, `randomize_noise=False`, вход 1×3×512×512 статичный; **перезапись модулированных свёрток (статические веса + нормировка `s`) обязательна** — без неё модель выдаёт мусор в fp16 и уходит на CPU ([ADR-0023](adr/ADR-0023-gfpgan-mobile-graph-rewrite.md), [S1](../spikes/S1.md)); конверсия в ncnn — через ONNX | Must | R0.2 |
| ML-CNV-003 | CodeFormer: `w` — вход графа (не константа); веса `params_ema` | Must | R0.5 |
| ML-CNV-004 | Каждый сконвертированный файл проходит паритетный тест против PyTorch fp32 на golden-тайлах (порог NFR-QLT-001) | Must | R0.1 |
| ML-CNV-005 | Smoke-тест конверсии в CI (compact-модель, CPU) на каждый PR в `ml/` | Must | R0.1 |
| ML-CNV-006 | Для StyleGAN2-моделей CI проверяет: эквивалентность перезаписи (max\|Δ\| ≤ 1e-4 в fp32), прогон в чистом fp16 (PSNR ≥ 35 дБ), 0 свёрток с неконстантными весами в графе ncnn/Core ML | Must | R0.2 |

Подробности квантизации и выбора бэкенда — [05](05-inference-optimization.md).

## 6. Паки и манифест

- Пак — версионированная единица (`id@semver`) с файлами под платформу/бэкенд/точность, лицензией, IO-спецификацией, eval-метриками и provenance.
- Манифест — `manifest.json` + `manifest.json.minisig`, схема — [appendix/manifest.schema.json](appendix/manifest.schema.json), ADR-0011.
- Формат `.rfpack`: zip с `manifest.json`, `manifest.json.minisig` (подмножество с одним паком) и файлами; проверяется так же, как сетевой.

Пример записи:

```json
{
  "id": "face.gfpgan-1.4", "version": "1.0.0", "category": "face",
  "title": {"en": "GFPGAN 1.4", "ru": "GFPGAN 1.4"}, "tier_min": "T1",
  "license": {"spdx": "LicenseRef-GFPGAN-NC", "url": "https://…", "text_sha256": "…",
              "commercial": false, "requires_acceptance": true},
  "io": {"inputs": [{"name": "input", "shape": [1,3,512,512], "range": [-1,1], "color": "RGB"}],
         "outputs": [{"name": "output", "range": [-1,1]}], "scale": 1},
  "files": [
    {"platform": "android", "backend": "ncnn", "precision": "fp16",
     "path": "gfpgan14.ncnn.zip", "size": 171000000, "sha256": "…",
     "urls": ["https://huggingface.co/…", "https://github.com/…/releases/…"]},
    {"platform": "ios", "backend": "coreml", "precision": "fp16",
     "path": "gfpgan14.mlpackage.zip", "size": 172000000, "sha256": "…", "urls": ["…"]}
  ],
  "eval": {"psnr_vs_fp32": 36.1, "lpips": 0.012, "arcface_cos": 0.97},
  "provenance": {"upstream": "TencentARC/GFPGAN v1.3.0 release", "upstream_sha256": "…",
                 "conversion_commit": "…"}
}
```

## 7. Оценка качества

### 7.1 Метрики

| Группа | Метрики | Инструмент | Где |
|---|---|---|---|
| Паритет бэкендов | PSNR (Y), SSIM, LPIPS (AlexNet), max-abs | `ml/eval`, `refocal-cli` | CI на каждый PR |
| Качество без эталона | MUSIQ, MANIQA, CLIP-IQA, NIQE | pyiqa | CI nightly, перед релизом |
| Лица | ArcFace cosine (идентичность), LMD (landmark distance), FID vs FFHQ (опц.) | `ml/eval` (ArcFace — только офлайн) | nightly |
| С эталоном (синтетика) | PSNR/SSIM/LPIPS на CelebA-Test, DIV2K-val, RealSR | `ml/eval` | при выборе/обновлении модели |

### 7.2 Golden-набор (`ml/golden/`)

- 50–100 изображений с лицензиями CC0/CC-BY (provenance и лицензия каждого — в `golden/SOURCES.md`).
- Категории (не менее 5 изображений в каждой): старые сканы, сильный JPEG, low-light/шум, групповые фото, мелкие лица, профиль, без лиц (пейзаж, текст), иллюстрации/аниме, ч/б, большие (≥ 12 МП), с альфой, HEIC, разные EXIF-ориентации, разнообразие тонов кожи (шкала Monk), возраст (дети не используются — только взрослые и пожилые; см. 15).
- Эталонные выходы PyTorch fp32 хранятся в Git LFS / артефакте релиза `golden-refs-vN`.
- **Часть для SR (1.1):** фото в git не хранятся. `ml/golden/golden.lock` — по строке JSON на фото (категория, SHA-256, URL Wikimedia Commons, лицензия CC0 / CC BY / PD, автор), `SOURCES.md` генерируется из него (`tools/ml/golden_fetch.py --sources`, CI сверяет). 46 реальных фото без лиц: `compact` (мыльницы), `phone` (старые телефоны), `blur`, `noise`, `lowlight`, `jpeg`; кандидатов предлагает `tools/ml/golden_collect.py`, каждый просмотрен человеком. Синтетика с эталоном — 24 фото Kodak с деградациями clean/blur/noise/jpeg внутри `tools/ml/sr_eval.py` (DIV2K не берём: лицензия только для исследований).

### 7.3 Пороги CI

| Проверка | Порог | Действие |
|---|---|---|
| PSNR бэкенд vs PyTorch fp32 | ≥ 40 дБ (fp32), ≥ 35 дБ (fp16) | fail |
| LPIPS бэкенд vs PyTorch | ≤ 0.02 | fail |
| ArcFace cos (лица, faceStrength 0.5) | ≥ 0.95 | fail |
| Число и IoU боксов детектора vs эталон | одинаковое число, IoU ≥ 0.9 | fail |
| NR-IQA среднее vs предыдущий релиз | падение ≤ 2% | warn (fail перед релизом) |
| Швы тайлов | NFR-QLT-003 | fail |

## 8. Ограничения и bias

- Face-модели обучены на FFHQ — смещение в сторону фронтальных лиц, светлых тонов кожи, взрослого возраста [R]. Требуется замер по подгруппам (ML-BIAS-001) и публикация в MODELS.md.
- Восстановление «выдумывает» детали: текст, номера, мелкие объекты — не восстанавливаются достоверно. Предупреждение в UI и документации.
- На лицах > 512 px восстановление не добавляет деталей, только риск искажения — по умолчанию ослабляется (FR-FACE-009).

## 9. R&D-направления

| Направление | Цель | Релиз |
|---|---|---|
| SPAN/SPANV2 retrain с деградациями Real-ESRGAN (Apache), дистилляция от 4xRealWebPhoto_v4_dat2 | Своя встроенная модель не хуже выигравших CC-BY-паков R1.1 при ~0.15M параметров | R2.0 |
| Clean-room face restoration на permissive-данных | Убрать NC-зависимость | R2.0 |
| Дистилляция x4plus → компактная модель | HQ на T1 | R2.0 |
| Low-light модель | ✅ HVI-CIDNet (0.6) | — |
| Одношаговая диффузия для лиц на NPU (S12) | Экспериментальный пак `face.gen-*` | R1.5 |
