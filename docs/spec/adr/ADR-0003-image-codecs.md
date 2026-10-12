# ADR-0003: Image codecs and HEIC

- **Статус:** Accepted
- **Дата:** 2026-10-09

## Контекст

Нужны потоковые декодирование и кодирование больших изображений, лицензионно совместимые с Apache-2.0 и App Store/F-Droid.

## Решение

- Декодирование: JPEG — libjpeg-turbo, PNG — libpng, WebP — libwebp. HEIC/AVIF — платформой (Android `AImageDecoder` API 30+, на 29 — JNI `ImageDecoder`; iOS ImageIO).
- Кодирование JPEG/PNG/WebP — собственными библиотеками **полосами строк**. Для JPEG `optimize_coding` выключен: двухпроходный Хаффман держит в памяти коэффициенты всего изображения (замер на 192 МП: пик RSS 903 → 419 МБ после отключения), выигрыш в размере ~5%.
- HEIC — только платформенными энкодерами: iOS `CGImageDestination` с `CGDataProvider`, читающим BandStore; Android `androidx.heifwriter` в buffer-режиме с ограничением ≤ 50 МП.
- Метаданные — собственный модуль `metaio` (EXIF APP1, XMP, ICC APP2; PNG eXIf/iTXt/iCCP; WebP через libwebpmux).

## Последствия

(+) Нет GPL/LGPL и патентных рисков HEVC в собственном коде.
(−) Свой `metaio` требует тестов и фаззинга; HEIC на Android зависит от устройства.

## Отклонённые альтернативы

- libheif + x265: GPL, патенты HEVC.
- libheif + kvazaar: LGPL, патенты.
- exiv2: GPL. libexif: LGPL, неудобно при статической линковке.
