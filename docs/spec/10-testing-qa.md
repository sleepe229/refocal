# 10. Тестирование и QA

## 1. Стратегия

```
                 ▲  Ручное: a11y-аудит, exploratory, бета
                ▲▲  Реальные устройства: perf, тепло, драйверы (nightly)
               ▲▲▲  Интеграционные (Patrol): эмулятор/симулятор
              ▲▲▲▲  Golden: модели (refocal-cli) + UI (alchemist)
             ▲▲▲▲▲  Unit: C++ (gtest), Dart (test), виджеты
```

- Тяжёлая логика живёт в C++ core и `refocal_core` → основная масса тестов — быстрые desktop-тесты.
- Модели проверяются **числовыми порогами**, а не побайтовым сравнением (GPU недетерминированы между устройствами).
- Каждое FR/NFR трассируется на тест или ревью (матрица — §10).

## 2. Unit-тесты

| ID | Объект | Что проверяется | Инструмент |
|---|---|---|---|
| TEST-UNIT-001 | Tiler/Scheduler | Покрытие изображения без пропусков, корректный pad/reflect на краях, сдвиг последнего ряда, все размеры 1×1…30000 | gtest + property-based (rapidcheck) |
| TEST-UNIT-002 | Blend | Feather-шов, strength 0/1 (тождества), Region-маски | gtest |
| TEST-UNIT-003 | FaceAlign | Similarity transform по эталонным точкам, обратная матрица × scale, маска; сравнение с эталоном facexlib (Python) | gtest + эталонные векторы |
| TEST-UNIT-004 | metaio | 8 EXIF-ориентаций, сохранение даты/камеры/ICC, удаление GPS/MakerNotes, запись XMP DigitalSourceType, размеры, удаление миниатюры; проверка `exiftool` | gtest + exiftool в CI |
| TEST-UNIT-005 | BandStore | Запись/чтение полос, LZ4, checkpoint, восстановление после обрыва записи | gtest |
| TEST-UNIT-006 | Crypto | SHA-256 (векторы NIST), minisign (эталонные подписи, неверные подписи, неверный ключ) | gtest |
| TEST-UNIT-007 | Recipe/Preset | Сериализация, миграция схемы, неизвестная модель → ошибка | dart test |
| TEST-UNIT-008 | AutoPolicy | Таблица «анализ → решение», детерминизм, граничные значения | dart test |
| TEST-UNIT-009 | TierPolicy, MemoryGovernor | Классификация по сигналам; бюджет и уменьшение тайла по estimate | dart test, gtest |
| TEST-UNIT-010 | Декодеры | JPEG/PNG/WebP/HEIC/AVIF/BMP/GIF: размеры, цвет, 16-бит → 8-бит, ICC | gtest + платформенные тесты |
| TEST-UNIT-011 | Альфа | Сохранение прозрачности PNG/WebP при всех масштабах | gtest |
| TEST-UNIT-012 | Inbox/квоты | Дедуп по SHA-256, LRU-очистка, «Хранить» не удаляется | dart test |

## 3. Golden-тесты моделей (`refocal-cli`)

| ID | Что проверяется | Порог | Когда |
|---|---|---|---|
| TEST-ML-001 | SR на golden-наборе: ncnn CPU (Linux), Core ML (macOS runner) vs PyTorch fp32 | PSNR ≥ 40/35 дБ, LPIPS ≤ 0.02 | Каждый PR в native/ml |
| TEST-ML-002 | Детекция и восстановление лиц: число/IoU боксов, ΔE color match | IoU ≥ 0.9, ΔE ≤ 3 | Каждый PR |
| TEST-ML-003 | Идентичность: ArcFace cos результат vs вход-апскейл при faceStrength 0.5; монотонность по CodeFormer w | ≥ 0.95 | Nightly (ArcFace только офлайн) |
| TEST-ML-004 | Тождества: strength=0 → Lanczos; faceStrength=0 → SR-фон | PSNR ≥ 50 дБ | Каждый PR |
| TEST-ML-005 | Паритет конверсии и детерминизм в пределах бэкенда; гейт int8 | NFR-QLT-001; побайтово для одного бэкенда | При изменении паков / каждый PR |
| TEST-ML-006 | NR-IQA (MUSIQ, CLIP-IQA, MANIQA) vs предыдущий релиз | Падение ≤ 2% | Nightly, перед релизом (fail) |
| TEST-ML-007 | Швы тайлов: градиент на границах | ≤ 1.5× среднего | Каждый PR |
| TEST-ML-008 | Bias: метрики по подгруппам (тон кожи Monk, возраст, очки, профиль) | Разница ArcFace между подгруппами публикуется; алерт при разнице > 0.03 | Перед релизом паков |

## 4. UI и виджеты

| ID | Что | Инструмент |
|---|---|---|
| TEST-UI-001 | Golden-скриншоты экранов: светлая/тёмная тема, en/ru, textScaler 1.0/2.0, телефон/планшет | alchemist |
| TEST-UI-002 | Виджет-тесты: состояния экранов (empty/loading/progress/error), диалоги fallback, лицензия пака | flutter_test |

## 5. Интеграционные тесты

Patrol (нативные диалоги: пикер, уведомления, share) на Android-эмуляторе (API 29, 34, 36; AOSP без GMS для fdroid) и iOS-симуляторе (16, 18, 26).

| ID | Сценарий | Критерий |
|---|---|---|
| TEST-INT-001 | Выбор фото (Photo Picker и fallback) → Auto → обработка → сохранение | Файл в галерее, без запроса разрешений |
| TEST-INT-002 | Очередь 30 фото: добавление, порядок, ошибки элементов, итог | Корректный отчёт |
| TEST-INT-003 | Kill процесса посреди джоба → перезапуск → продолжение | Потеря ≤ 1 полосы, результат идентичен непрерванному |
| TEST-INT-004 | Share intake Android (SEND/SEND_MULTIPLE) и iOS Share Extension | Файлы в редакторе/очереди |
| TEST-INT-005 | Скачивание пака: обрыв сети на 50% → докачка; переключение на зеркало; отказ подписи | Докачка без повтора; корректные ошибки |
| TEST-INT-006 | Экспорт JPEG/PNG/WebP/HEIC из одного джоба; очистка временных файлов и «сирот» после удаления истории | Все форматы открываются; нет «сирот» |
| TEST-INT-007 | Отмена и пауза на разных стадиях | Задержка по NFR-PERF-008 |
| TEST-INT-008 | iOS: сворачивание во время GPU-стадии → пауза → возврат → продолжение | Нет крэша, нет GPU-вызовов в фоне |
| TEST-INT-009 | Android FGS: очередь при выключенном экране; симуляция `onTimeout` | Очередь завершается; при таймауте — пауза и уведомление |
| TEST-INT-010 | Режим без сети (авиарежим): все офлайн-функции работают | — |

## 6. Производительность

`perf-set`: 1 МП без лиц, 1 МП с 2 лицами, 12 МП с 1 лицом, 48 МП (T2). Условия замера — [02 §2](02-nfr.md#2-производительность-perf).

| ID | Что | Где |
|---|---|---|
| TEST-PERF-001 | Латентность по стадиям, с/МП, время загрузки моделей, бенчмарк | Устройства матрицы, nightly |
| TEST-PERF-002 | Пиковая память (VmHWM / phys_footprint), память в покое, Share Extension | Устройства матрицы |
| TEST-PERF-003 | Тепло: 20 джобов подряд, тепловое состояние и замедление | T1/T2, еженедельно |
| TEST-PERF-004 | Батарея: 10 джобов, отсутствие фоновой активности | T1, перед релизом |
| TEST-PERF-005 | Холодный старт | Все тиры, каждый релиз-кандидат |
| TEST-PERF-006 | UI: fps/jank при зуме и слайдере, отсутствие кадров > 100 мс во время инференса (`flutter drive --profile`, timeline) | T0/T1 |
| TEST-PERF-007 | Размер APK/IPA и встроенных моделей — size gate | CI каждый PR |

Регрессия > 10% по любой метрике perf — блокирует релиз до разбора.

## 7. Инъекция отказов

| ID | Отказ | Ожидание |
|---|---|---|
| TEST-FAULT-001 | OOM (тестовый хук аллокатора, `enh_set_memory_pressure`) | Тайл ÷2, событие FALLBACK, диалог понижения масштаба при исчерпании |
| TEST-FAULT-002 | `DEVICE_LOST` / ошибка компиляции Core ML (mock-бэкенд) | Переход на следующий бэкенд |
| TEST-FAULT-003 | NaN на выходе face-модели | Повтор fp32 CPU → пропуск лица с предупреждением |
| TEST-FAULT-004 | Диск заполнен во время записи полосы | Ошибка с требуемым объёмом, джоб в Paused, без порчи checkpoint |
| TEST-FAULT-005 | Crash sentinel: принудительный abort в GPU-стадии → перезапуск | CPU-режим, баннер; blocklist после 2 срабатываний |
| TEST-FAULT-006 | Повреждённый / обрезанный файл пака | Отказ загрузки, предложение переустановить |
| TEST-FAULT-007 | Синтетическая порча выхода бенчмарка (zero, noise, одиночный NaN, блок 32×32, половина, перестановка каналов, сдвиг +2/255) | Все виды порчи → `wrong_output`; сдвиг +2/255 → `ok` (S3 `run_detection.sh`) |
| TEST-FAULT-008 | Оригинальный граф GFPGAN (без ADR-0023) в fp16 на GPU | `wrong_output` без NaN → локальное правило `gpu_fp32` → следующий запуск проходит в fp32 |
| TEST-FAULT-009 | Смерть изолята или движка посреди джоба: hot restart; Android — «назад» с работающим FGS | Процесс жив, джоб доходит до конца, новый движок подключается к нему (`enh_job_set_port`), утечек нет (S6 `isolate_kill`) |
| TEST-FAULT-010 | Невалидный UTF-8 в пути файла или в сообщении ошибки | Ядро экранирует строку, все события, включая терминальное, доставлены (S6 `bad_utf8`) |

## 8. Безопасность и соответствие

| ID | Что | Инструмент |
|---|---|---|
| TEST-SEC-001 | Фаззинг декодеров + лимиты размеров | libFuzzer + ASan, корпус из golden + OSS-Fuzz корпусы |
| TEST-SEC-002 | Фаззинг metaio (EXIF/XMP/ICC) | libFuzzer |
| TEST-SEC-003 | Подменённый файл пака / манифест с неверной подписью | gtest + интеграционный |
| TEST-SEC-004 | Откат `serial` | gtest |
| TEST-SEC-005 | `.rfpack`: path traversal, симлинки, zip bomb | gtest |
| TEST-SEC-006 | ASan/UBSan/TSan сборки core-тестов, включая стресс моста событий (S6 `stress`) | CI. TSan — только на раннерах с совместимым ядром; шаг-самопроверка: сборка с заведомой гонкой обязана упасть (S6: на Linux 7.0 TSan молча ничего не находит) |
| TEST-COMP-001 | Разрешения: в merged-манифесте Android нет `READ_MEDIA_*`/`READ_EXTERNAL_STORAGE`; в Info.plist нет `NSPhotoLibraryUsageDescription` | Скрипт в CI (aapt2 dump / plutil) |
| TEST-COMP-002 | PrivacyInfo.xcprivacy присутствует и валиден, объявлены нужные причины | Скрипт + Xcode privacy report |
| TEST-COMP-003 | Сетевой эгресс: сценарии без действий пользователя дают 0 запросов (прокси mitmproxy в интеграционном тесте) | CI nightly |
| TEST-COMP-004 | License check: зависимости Dart (`flutter pub deps` + лицензии), native-сабмодули, модели в бандле; fail на GPL/AGPL/LGPL (статика), отсутствие записи в MODELS.md, GMS/Firebase в любом флейворе | CI каждый PR |

## 9. Доступность и БД

| ID | Что | Инструмент |
|---|---|---|
| TEST-A11Y-001 | `meetsGuideline` для labeled tap targets, Android/iOS tap target size | flutter_test |
| TEST-A11Y-002 | Ручной аудит TalkBack и VoiceOver по чек-листу (все потоки §3 из 06) | Перед R0.3, R1.0, каждым мажорным UI-изменением |
| TEST-A11Y-003 | textScaler 2.0 — golden UI без обрезки | alchemist |
| TEST-A11Y-004 | Контраст (`textContrastGuideline`) | flutter_test |
| TEST-DB-001 | Миграции drift со всех предыдущих версий схемы | drift `SchemaVerifier` |

## 10. Матрица устройств

Список — [appendix/device-matrix.md](appendix/device-matrix.md). Минимум: 6 устройств (2 на тир), покрывающих GPU Adreno, Mali, Xclipse (AMD), PowerVR (если есть в T0), Apple A12–A17.

Источники устройств (Q-14):

- собственный парк мейнтейнеров;
- DeviceFarmer (self-hosted, бывш. OpenSTF);
- AWS Device Farm / Firebase Test Lab (не добавляют SDK в APK — допустимы);
- community-матрица: добровольцы прогоняют nightly + perf-экран и прикладывают JSON к issue «perf report».

## 11. Трассировка

`docs/spec/appendix/traceability.csv` генерируется скриптом `tools/trace.py` (R0.2) из таблиц требований: `REQ_ID → TEST_ID / ADR`. CI проверяет, что каждое Must-требование текущего релиза имеет хотя бы одну ссылку на TEST или пометку «ревью».

## 12. Критерии качества релиза

| Канал | Критерии |
|---|---|
| Internal (R0.1–0.2) | Все unit/golden/integration зелёные; perf на 2 устройствах |
| Beta (R0.3–0.5) | + perf на всей матрице, a11y-аудит, фаззинг 1 ч без падений |
| GA (R1.0) | + фаззинг 24 ч, security review, все Must-FR закрыты, crash-free ≥ 99.5% в бете |
