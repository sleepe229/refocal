# 08. Платформы, сторы, регуляторика

Политики сторов меняются; раздел пересматривается перед каждым мажорным релизом (OPS-REL-005). Пункты с пометкой **[проверить]** требуют подтверждения на момент релиза.

## 1. Android

| ID | Требование | Приоритет | Релиз | Критерий / источник |
|---|---|---|---|---|
| COMP-AND-001 | `minSdk 29`, `targetSdk 36` (обязательно для новых приложений и обновлений в Play с 31.08.2026, продление до 01.11.2026) | Must | R0.1 | [Target API requirements](https://developer.android.com/google/play/requirements/target-sdk) |
| COMP-AND-002 | Ввод только через Photo Picker (`PickVisualMedia`, AndroidX Activity ≥ 1.7) с автоматическим fallback на `ACTION_OPEN_DOCUMENT`; **нет** `READ_MEDIA_IMAGES`, `READ_MEDIA_VIDEO`, `READ_EXTERNAL_STORAGE` | Must | R0.1 | [Photo and Video Permissions policy](https://support.google.com/googleplay/android-developer/answer/14115180) — с 28.05.2025 приложения с разовым доступом обязаны использовать пикер; TEST-COMP-001 |
| COMP-AND-003 | Для пакетов — `takePersistableUriPermission` либо копия в inbox сразу после выбора | Must | R0.3 | ADR-0010 |
| COMP-AND-004 | Сохранение через MediaStore (`Pictures/Refocal`) без разрешений (API 29+) | Must | R0.1 | — |
| COMP-AND-005 | Foreground service `foregroundServiceType="mediaProcessing"`, запуск только из действия пользователя, разрешение `FOREGROUND_SERVICE_MEDIA_PROCESSING`, `POST_NOTIFICATIONS` (запрос в контексте); обработка `onTimeout` (API 35+, 6 ч / 24 ч) | Must | R0.3 | [FGS timeout](https://developer.android.com/develop/background-work/services/fg-service-timeout); ADR-0019 |
| COMP-AND-006 | Edge-to-edge (принудительно при target 35+), корректные insets; без блокировки ориентации на больших экранах (target 36) | Must | R0.3 | Тесты на планшете/foldable |
| COMP-AND-007 | 16 КБ page size: все native-библиотеки собраны с выравниванием 16 КБ | Must | R0.1 | Требование Play для target 35+ [проверить]; CI-проверка `zipalign -P 16` / `readelf` |
| COMP-AND-008 | Политика Play по AI-генерируемому контенту: в приложении есть способ сообщить о проблемном результате; приложение не генерирует запрещённый контент | Must | R0.5 | Применимость к «улучшению» не определена [проверить]; FR-REP-001 |
| COMP-AND-009 | Data Safety: «не собирается / не передаётся» (см. 07 §8) | Must | R0.5 | — |
| COMP-AND-010 | `android:allowBackup` / `dataExtractionRules` исключают inbox, jobs, models | Should | R0.3 | PRIV-DATA-005 |
| COMP-AND-011 | `cleartextTrafficPermitted=false` в network security config | Must | R0.2 | PRIV-NET-004 |
| COMP-AND-012 | Ни один флейвор не содержит GMS/Firebase/Sentry и иных SDK отправки данных; флейворы `play` и `fdroid` отличаются только метаданными и подписью | Must | R0.1 | TEST-COMP-004 |

## 2. iOS

| ID | Требование | Приоритет | Релиз | Критерий / источник |
|---|---|---|---|---|
| COMP-IOS-001 | Минимальная версия iOS 16 (Q-02) | Must | R0.1 | — |
| COMP-IOS-002 | Ввод через `PHPickerViewController` (вне процесса, без разрешений); сохранение — `PHPhotoLibrary` с уровнем `.addOnly`, только `NSPhotoLibraryAddUsageDescription`; `NSPhotoLibraryUsageDescription` отсутствует | Must | R0.1 | TEST-COMP-001 |
| COMP-IOS-003 | `PrivacyInfo.xcprivacy` в приложении и расширении: `NSPrivacyTracking=false`, `NSPrivacyCollectedDataTypes=[]`, Required Reason APIs: UserDefaults `CA92.1`, File timestamp `C617.1`, Disk space `E174.1` | Must | R0.1 | [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files); TEST-COMP-002 |
| COMP-IOS-004 | Аудит манифестов всех плагинов; при статической линковке — объявление их Required Reason APIs в манифесте приложения | Must | R0.3 | Известная проблема Flutter (#131940) [проверить статус] |
| COMP-IOS-005 | Никакого GPU-инференса в фоне (ADR-0019); `beginBackgroundTask` только для сохранения checkpoint | Must | R0.3 | TEST-INT-008 |
| COMP-IOS-006 | Share Extension: только копирование в App Group и открытие приложения; память ≤ 60 МБ (лимит ≈ 120 МБ) | Must | R0.3 | NFR-MEM-007 |
| COMP-IOS-007 | Entitlement `com.apple.developer.kernel.increased-memory-limit` (не полагаться в бюджете) | Should | R0.2 | — |
| COMP-IOS-008 | Заметки для App Review: обработка на устройстве, модели — данные (не исполняемый код, гайдлайн 2.5.2), NC-паки загружаются по выбору пользователя, сбор данных отсутствует | Must | R1.0 | — |
| COMP-IOS-009 | Гайдлайн 5.1.2(i) (согласие перед передачей данных сторонним AI) — к on-device не применяется, но в описании явно указано «обработка на устройстве» | Should | R1.0 | [проверить] |
| COMP-IOS-010 | Совместимость лицензий: Apache-2.0 совместима с App Store; GPL/AGPL-зависимости запрещены (12 §2) | Must | R0.1 | TEST-COMP-004 |
| COMP-IOS-011 | Export compliance: используется только стандартная криптография (проверка подписей, HTTPS) — `ITSAppUsesNonExemptEncryption=false` | Must | R1.0 | [проверить формулировку] |

## 3. F-Droid

| ID | Требование | Приоритет | Релиз | Критерий / источник |
|---|---|---|---|---|
| COMP-FDR-001 | Сборка из исходников полностью свободным тулчейном; флейвор `fdroid` без GMS/Firebase/ML Kit/Sentry/проприетарных blobs | Must | R0.5 | [Inclusion Policy](https://f-droid.org/en/docs/Inclusion_Policy/) |
| COMP-FDR-002 | В APK нет ассетов под NC/ND-лицензиями (иначе анти-фича `NonFreeAssets`); NC-паки — опциональная загрузка, задекларированная в описании | Must | R0.5 | [Anti-Features](https://f-droid.org/en/docs/Anti-Features/); ADR-0022 |
| COMP-FDR-003 | Сетевые функции — только по действию пользователя / opt-in (нет анти-фичи Tracking); при необходимости — пометка `NonFreeNet` не требуется (HF/GitHub — хостинг файлов) [проверить] | Must | R0.5 | — |
| COMP-FDR-004 | Воспроизводимая сборка: Flutter как git-сабмодуль (согласно `srclibs/flutter.yml` fdroiddata), детерминированный CMake/NDK, проверка `diffoscope` → F-Droid публикует APK с подписью разработчика | Should | R0.5 | S8 |
| COMP-FDR-005 | Метаданные в `fastlane/metadata/android/<locale>/` (F-Droid читает эту структуру), changelogs по `versionCode` | Must | R0.5 | — |
| COMP-FDR-006 | `UpdateCheckMode: Tags`, автосборка по git-тегам | Should | R0.5 | — |
| COMP-FDR-007 | В манифесте `fdroid`-сборки нет `com.google.android.gms` метаданных (`ModuleDependencies` для backport Photo Picker) | Must | R0.5 | [проверить, вызывает ли сканер предупреждение] |

## 4. Регуляторика

| ID | Требование | Приоритет | Релиз | Источник |
|---|---|---|---|---|
| COMP-REG-001 | EU AI Act, ст. 50 (обязанности прозрачности для систем, создающих/изменяющих изображения; применяется с 08.2026): результат машинно-читаемо маркирован как изменённый ИИ | Must | R0.3 | Применимость к некоммерческому open-source инструменту не определена [проверить]; соблюдаем добровольно |
| COMP-REG-002 | IPTC `DigitalSourceType = compositeWithTrainedAlgorithmicMedia` в XMP по умолчанию | Must | R0.3 | [IPTC NewsCodes](https://cv.iptc.org/newscodes/digitalsourcetype/) |
| COMP-REG-003 | GDPR/152-ФЗ: персональные данные не собираются и не обрабатываются вне устройства; серверов у проекта нет | Must | R0.5 | — |
| COMP-REG-004 | Возрастной рейтинг: 4+ / Everyone; приложение не создаёт контент для взрослых | Must | R1.0 | — |
| COMP-REG-005 | Отсутствие товарных знаков третьих лиц в названии/маркетинге («Remini» и др. — только в сравнительном README без логотипов) | Must | R0.5 | 12 §8 |

## 5. Лицензии в приложении

| ID | Требование | Приоритет | Релиз |
|---|---|---|---|
| COMP-LIC-001 | Экран лицензий: Flutter `showLicensePage` (пакеты автоматически) + `LicenseRegistry.addLicense` для native-библиотек (ncnn, libjpeg-turbo, libpng, libwebp, Monocypher, lz4, json) и моделей (включая установленные паки) | Must | R0.2 |
| COMP-LIC-002 | Файл `NOTICE` в репозитории и в приложении (Apache-2.0) | Must | R0.1 |
