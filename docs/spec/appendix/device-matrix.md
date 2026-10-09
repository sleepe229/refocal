# Приложение A. Матрица устройств

Минимальный эталонный набор — 6 устройств (★). Остальные — расширенная матрица (device farm / сообщество). Конкретные модели могут заменяться эквивалентами по SoC/GPU/RAM.

## Android

| ★ | Устройство | SoC | GPU | RAM | Android | Тир | Зачем |
|---|---|---|---|---|---|---|---|
| ★ | Samsung Galaxy S23 / S24 | Snapdragon 8 Gen 2 / Gen 3 | Adreno 740/750 | 8 ГБ | 14–16 | T2 | Флагман Qualcomm, будущий NPU-тир |
| ★ | Samsung Galaxy A54 | Exynos 1380 | Mali-G68 | 6 ГБ | 14–15 | T1 | Массовый средний Mali |
| ★ | Redmi 9A / Galaxy A14 | Helio G25 / G80 / Exynos 850 | PowerVR GE8320 / Mali-G52 | 3–4 ГБ | 10–14 | T0 | Нижняя граница, проблемные драйверы |
| | Google Pixel 8 Pro | Tensor G3 | Mali-G715 | 12 ГБ | 15–16 | T2 | Чистый Android, новый Mali |
| | Pixel 6a | Tensor | Mali-G78 | 6 ГБ | 14–16 | T1 | Средний Google |
| | Redmi Note 12 Pro | Dimensity 1080 | Mali-G68 | 6–8 ГБ | 13–14 | T1 | MediaTek |
| | Galaxy S24 (Exynos) | Exynos 2400 | Xclipse 940 (AMD) | 8 ГБ | 14–16 | T2 | AMD-GPU |
| | Xiaomi 14 / OnePlus 12 | Snapdragon 8 Gen 3 | Adreno 750 | 12 ГБ | 14–16 | T2 | Тепловой троттлинг |
| | Galaxy Tab S9 / Pixel Fold | SD 8 Gen 2 / Tensor G2 | — | 8–12 ГБ | 14–16 | T2 | Большие экраны, foldable |
| | AOSP-эмулятор без GMS | x86_64 | SwiftShader | — | 10, 14, 16 | T0 | fdroid-флейвор, CI |

## iOS

| ★ | Устройство | Чип | RAM | iOS | Тир | Зачем |
|---|---|---|---|---|---|---|
| ★ | iPhone 15 Pro | A17 Pro | 8 ГБ | 18, 26 | T2 | Флагман, ANE |
| ★ | iPhone 12 | A14 | 4 ГБ | 16–18 | T1 | Нижняя граница T1 |
| ★ | iPhone XR / SE 2 | A12 / A13 | 3 ГБ | 16–17 | T0 | Минимальная iOS, jetsam |
| | iPhone 13 mini | A15 | 4 ГБ | 17–26 | T1 | — |
| | iPhone 16 | A18 | 8 ГБ | 18–26 | T2 | — |
| | iPad (A16) / iPad Air M2 | A16 / M2 | 6–8 ГБ | 17–26 | T2 | Планшет (Q-02) |

## Покрытие

- GPU-вендоры: Adreno, Mali (старые и новые), PowerVR, Xclipse, Apple.
- Версии ОС: Android 10 (min), 14, 15, 16; iOS 16 (min), 18, 26.
- RAM: 3, 4, 6, 8, 12 ГБ.
