# 12. Open source: governance и лицензирование

## 1. Лицензия проекта

- Код, документация, дизайн-ассеты проекта — **Apache-2.0**; файл `NOTICE` с атрибуциями.
- Выбор обоснован: permissive, патентный грант, совместим с App Store (в отличие от GPL/AGPL), допускает включение в F-Droid.
- Модели сторонних авторов имеют **собственные** лицензии и не перелицензируются (см. §3).

## 2. Политика лицензий зависимостей

| Категория | Лицензии | Использование |
|---|---|---|
| Разрешены | Apache-2.0, MIT, BSD-2/3, ISC, zlib, IJG, libpng, BSL-1.0, CC0, Unlicense | Свободно |
| С ограничениями | MPL-2.0 (file-level copyleft) | Допустимо без модификации файлов либо с публикацией изменений |
| Запрещены | GPL-2/3, AGPL, LGPL (при статической линковке; на iOS — вся LGPL), SSPL, лицензии с NC/ND для кода | Нельзя |
| Проприетарные SDK | Firebase, GMS, ML Kit, Crashlytics, рекламные SDK | Нельзя ни в одном флейворе |

| ID | Требование | Приоритет | Релиз |
|---|---|---|---|
| OPS-LIC-001 | License check в CI (TEST-COMP-004) блокирует PR при нарушении политики | Must | R0.1 |
| OPS-LIC-002 | Каждая новая native-зависимость — через ADR или PR с обоснованием и записью в `NOTICE` | Must | R0.1 |
| OPS-LIC-003 | Код из GPL-проектов (например, SuperImage) **не копируется**; допускается только изучение идей | Must | R0.1 |

## 3. Лицензии моделей

| Модель | Лицензия | В приложении | В основном репозитории | Требует согласия |
|---|---|---|---|---|
| YuNet | MIT | Да | Да (конвертированные веса) | Нет |
| realesr-general-x4v3 (+DNI-уровни) | BSD-3 | Да | Да | Нет |
| RealESRGAN x4plus, anime_6B | BSD-3 | Нет (пак) | Нет (HF/Releases) | Нет |
| GFPGAN 1.4 | Apache-2.0 + NC-компоненты, данные FFHQ BY-NC-SA | Нет (пак) | Нет | **Да** |
| CodeFormer | S-Lab License 1.0 (NC) | Нет (пак) | Нет | **Да** |
| FBCNN | Apache-2.0 | Нет (пак) | Нет | Нет |
| BOPBTL scratch detector | MIT | Нет (пак) | Нет | Нет |
| BiSeNet (CelebAMask-HQ) | MIT код, данные NC | Нет (пак) | Нет | **Да** |
| DDColor | Apache-2.0 код, веса — уточнить | Решение после S9 | — | — |

- Тексты лицензий моделей поставляются с паком, показываются при согласии и в «Лицензиях» (COMP-LIC-001).
- Хостинг NC-весов: зеркало сконвертированных весов в организации `refocal` (Hugging Face + GitHub Releases) с полным текстом лицензии, атрибуцией и ссылкой на upstream; публикация — только после положительного вывода S9 (Q-04).
- Донаты: GitHub Sponsors + Liberapay, «поддержка разработки открытого кода», без платных функций и без привязки к NC-моделям; подключаются после вывода S9 (Q-10).

## 4. MODELS.md

Для каждой модели (ML-REG-001):

```markdown
## face.gfpgan-1.4 @ 1.0.0
- Upstream: TencentARC/GFPGAN, release v1.3.0, file GFPGANv1.4.pth, SHA-256: …
- Paper: Wang et al., "Towards Real-World Blind Face Restoration with Generative Facial Prior", CVPR 2021
- License: … (полный текст: licenses/gfpgan.txt); commercial use: no
- Conversion: `make pack ID=face.gfpgan-1.4` (commit …); ONNX opset 17; pnnx …; coremltools …
- Precision: fp16 (mixed: demod in fp32)
- Eval (golden v3): PSNR vs fp32 36.1 dB, LPIPS 0.012, ArcFace 0.97
- Bias (ML-BIAS-001): ArcFace by Monk scale groups: …
- Known limitations: frontal bias; may alter identity at high strength; not for faces > 512 px
```

## 5. Документы сообщества

| Файл | Содержание |
|---|---|
| `README.md` | Что это, скриншоты, установка (Play/App Store/F-Droid/GitHub), приватность, ограничения, ссылки |
| `CONTRIBUTING.md` | Сборка, структура, стиль, Conventional Commits, DCO, как добавить модель, **запрещённые функции** (§6) |
| `CODE_OF_CONDUCT.md` | Contributor Covenant 2.1 |
| `SECURITY.md` | См. [09 §4](09-security.md#4-политика-раскрытия-уязвимостей) |
| `PRIVACY.md` | Политика приватности |
| `MODELS.md` | §4 |
| `GOVERNANCE.md` | Роли, принятие решений, как стать мейнтейнером |
| `.github/ISSUE_TEMPLATE/` | `bug.yml` (устройство, ОС, версия, режим, модель, бэкенд, лог), `bad-result.yml` (фото — только с отметкой согласия на публичность), `feature.yml`, `perf-report.yml` (JSON бенчмарка), `translation.yml` |
| `.github/PULL_REQUEST_TEMPLATE.md` | Чек-лист: тесты, лицензии, MODELS.md, скриншоты UI, a11y |

## 6. Запрещённые функции (политика проекта)

PR, добавляющие следующие возможности, отклоняются:

- face swap, перенос лица с другого фото;
- «раздевание», генерация наготы, сексуализированный контент;
- изменение формы тела, бьютификация, «похудение», изменение возраста/расы/пола;
- отключение AI-маркировки **по умолчанию** (опция пользователя остаётся);
- телеметрия, трекинг, рекламные SDK, сбор данных без opt-in;
- облачная обработка как обязательная часть.

Обоснование — [15](15-ethics-responsible-ai.md).

## 7. Governance

| ID | Требование | Приоритет | Релиз |
|---|---|---|---|
| OPS-GOV-001 | DCO (`Signed-off-by`) для всех коммитов; проверка DCO-ботом | Must | R0.1 |
| OPS-GOV-002 | Роли: maintainer (merge, релизы), reviewer, хранитель ключей (≥ 2 человека); перечислены в `GOVERNANCE.md` | Must | R0.5 |
| OPS-GOV-003 | Решения по архитектуре — через ADR; спорные — lazy consensus мейнтейнеров (72 ч) | Should | R0.3 |
| OPS-GOV-004 | Метки `good first issue`, `help wanted`; документированный онбординг контрибьютора | Should | R0.5 |
| OPS-GOV-005 | Bus factor ≥ 2 для релизов и ключей до 1.0 | Must | R1.0 |

## 8. Товарные знаки и бренд

- Название проекта — **Refocal** ([appendix/brand.md](appendix/brand.md)); перед публикацией в сторах — формальная проверка товарных знаков.
- «Remini», «Samsung», «Google Photos» упоминаются только в сравнительных материалах, без логотипов и без утверждений о превосходстве, которые нельзя подтвердить.
- Иконка и название — под Apache-2.0 / CC-BY-4.0 (решение мейнтейнеров); форки должны менять название и иконку при публикации в сторах (рекомендация в README).
