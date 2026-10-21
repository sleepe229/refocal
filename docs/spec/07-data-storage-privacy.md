# 07. Данные, хранилище, приватность

## 1. Принципы

- Данные пользователя никогда не покидают устройство без явного действия.
- Минимизация: храним рецепты, а не копии фото; временные файлы удаляются.
- Пользователь видит, что хранится, и может всё удалить.

## 2. Инвентарь данных

| Данные | Где | Срок хранения | Удаление | Покидает устройство? |
|---|---|---|---|---|
| Копии входных фото | `AppSupport/inbox/` | До экспорта; квота 1 ГБ / 7 дней (LRU); дольше — при «Хранить для повторной обработки» | Авто, «Очистить», удаление записи истории | Нет |
| Промежуточные данные джоба (полосы, лица, пирамида, checkpoint) | `AppSupport/jobs/<id>/` | До экспорта/удаления; принудительно > 7 дней | Авто, «Очистить» | Нет |
| Превью истории (≤ 512 px, JPEG без метаданных) | `AppSupport/history/` (не `Cache/`: кэш очищается системой, а запись остаётся) | Пока есть запись истории | Удаление записи / истории; «сироты» — при старте | Нет |
| Рецепты, история, очередь | SQLite `AppSupport/db.sqlite`, без бэкапа | Бессрочно (пока пользователь не удалит); очередь — 7 дней | UI | Нет |
| Настройки, пользовательские пресеты | SQLite `prefs.sqlite` в каталоге с бэкапом (PRIV-DATA-005) | Бессрочно | UI | Только бэкап платформы (Google / iCloud) |
| Установленные модели | `AppSupport/models/` | Пока установлен пак | UI «Удалить» | — |
| Согласия с лицензиями | SQLite `consents` | Бессрочно | Удаление пака | Нет |
| Кэш бенчмарка, тир | SQLite `benchmark_cache` | До изменения ключа | Сброс в настройках | Нет |
| Локальный blocklist (sentinel) | SQLite / файл | Бессрочно | Сброс в настройках | Нет |
| Логи | `AppSupport/logs/` (≤ 5 МБ, ротация) | Ротация | «Очистить логи» | Только при экспорте пользователем |
| Результаты | Галерея пользователя (MediaStore / Photos) | Управляет пользователь | Системная галерея | Только при «Поделиться» |

## 3. Схема БД (drift)

```sql
assets(id TEXT PK, sha256 TEXT UNIQUE, inbox_path TEXT, width INT, height INT,
       mime TEXT, created_at INT, keep BOOL)
recipes(id TEXT PK, schema INT, json TEXT, created_at INT)
history(id TEXT PK, asset_id TEXT FK, recipe_id TEXT FK, result_uri TEXT,
        preview_path TEXT, width INT, height INT, model_ids TEXT, backend TEXT,
        duration_ms INT, created_at INT)
queue_jobs(id TEXT PK, asset_id TEXT FK, recipe_id TEXT FK, state TEXT,
           position INT, job_dir TEXT, progress REAL, error_code TEXT,
           created_at INT, updated_at INT)
presets(id TEXT PK, name TEXT, builtin BOOL, recipe_json TEXT, created_at INT)
model_packs(id TEXT, version TEXT, category TEXT, path TEXT, size INT,
            sha256 TEXT, license_spdx TEXT, installed_at INT, PRIMARY KEY(id))
consents(pack_id TEXT, pack_version TEXT, license_sha256 TEXT, accepted_at INT,
         PRIMARY KEY(pack_id, license_sha256))
benchmark_cache(key TEXT PK, json TEXT, created_at INT)  -- key: app_ver|model_ver|driver_ver|gpu_device_id|os_build|gate_version; json: отчёт refocal-probe/1
gpu_blocklist_local(key TEXT PK, reason TEXT, hits INT, created_at INT)
manifest_state(id INT PK CHECK(id=1), serial INT, fetched_at INT, json TEXT)
settings(key TEXT PK, value TEXT)
```

Целевая схема; таблицы появляются вместе с функциями, каждая — миграцией (ADR-0009, поправки 0.0.4). `settings` и `presets` с 0.0.4 живут в отдельной `prefs.sqlite` (бэкап, PRIV-DATA-005); остальное — в `db.sqlite`. Схема v2 `db.sqlite`: `assets` с размером, допускающим NULL (фото в очереди ещё не прочитано), `queue_jobs` с `job_id` вместо `job_dir` и состояниями `queued|running|paused|done|saved|failed`. Схема v1 (0.0.4): `settings`, `assets(id, inbox_path UNIQUE, width, height, created_at)` — `sha256`, `mime`, `keep` придут с дедупликацией inbox и опцией «Хранить для повторной обработки»; `recipes`; `history` с дополнительным `job_id` (удаление BandStore, FR-HIST-004) и `preview_path` в `AppSupport/history/`, `model_ids` — JSON-список; `presets(id, name, recipe_json, created_at)` — только пользовательские, встроенные (FR-PRE-001) задаются в коде вместе с нужными им моделями. Пути — относительно AppSupport, время — Unix-миллисекунды.

| ID | Требование | Приоритет | Релиз | Критерий | Трассировка |
|---|---|---|---|---|---|
| PRIV-DATA-001 | Миграции БД версионированы, каждая покрыта тестом (drift `SchemaVerifier`) | Must | R0.3 | TEST-DB-001 | ADR-0009 |
| PRIV-DATA-002 | История хранит рецепт и превью ≤ 512 px, не копии фото (кроме опции «Хранить») | Must | R0.3 | ≤ 50 МБ на 1000 записей | FR-HIST-002 |
| PRIV-DATA-003 | Экран «Хранилище»: размер по категориям, очистка каждой | Must | R0.3 | — | FR-SET-004 |
| PRIV-DATA-004 | Удаление записи истории удаляет все связанные файлы | Must | R0.3 | Тест: нет «сирот» в inbox/jobs/previews | TEST-INT-006 |
| PRIV-DATA-005 | Файлы приложения исключены из облачного бэкапа (iOS `isExcludedFromBackup` для inbox/jobs/models; Android `dataExtractionRules`), кроме БД настроек/пресетов | Should | R0.3 | Ревью конфигурации | — |
| PRIV-DATA-006 | Удаление приложения удаляет все данные (только внутреннее хранилище) | Must | R0.1 | — | — |

## 4. Метаданные изображений

| ID | Требование | Приоритет | Релиз | Трассировка |
|---|---|---|---|---|
| PRIV-META-001 | GPS удаляется из результата по умолчанию (и при share, и при сохранении); опция «Сохранять геолокацию при сохранении в галерею» | Must | R0.3 | FR-META-003, ADR-0018 |
| PRIV-META-002 | MakerNotes и серийные номера камеры (`BodySerialNumber`, `LensSerialNumber`) удаляются | Should | R0.3 | — |
| PRIV-META-003 | Имя исходного файла не попадает в результат и в отчёты | Must | R0.3 | — |

## 5. Логи

| ID | Требование | Приоритет | Релиз |
|---|---|---|---|
| PRIV-LOG-001 | Лог не содержит путей к фото, URI, имён файлов, GPS, EXIF; идентификаторы — хэши | Must | R0.3 |
| PRIV-LOG-002 | Ротация ≤ 5 МБ; уровни ERROR/WARN/INFO; DEBUG только в debug-сборках | Must | R0.3 |
| PRIV-LOG-003 | Экспорт лога — только по действию пользователя через share sheet с предпросмотром содержимого | Must | R0.3 |
| PRIV-LOG-004 | Перехват ошибок: `FlutterError.onError`, `PlatformDispatcher.onError`, native — коды и сигналы в лог при следующем запуске | Must | R0.3 |

## 6. Сетевые вызовы (полный список)

| ID | Вызов | Когда | Данные, уходящие с устройства | Согласие |
|---|---|---|---|---|
| NET-1 | GET `manifest.json` + `.minisig` (HF / GitHub) | Открытие экрана «Модели» или скачивание пака | IP, User-Agent (без идентификаторов) | Действие пользователя |
| NET-2 | GET файлов пака (HF / GitHub, Range) | Нажатие «Скачать» | IP, User-Agent | Действие пользователя (+ лицензия) |
| NET-3 | GET `manifest.json` для проверки обновлений | Раз в 7 дней | IP, User-Agent | Opt-in, по умолчанию **выкл.** |
| NET-6 | GET `app-update.json` + `.minisig` (GitHub Releases / Pages), только сборка `github` | Раз в 7 дней по безлимитной сети; «Проверить сейчас» | IP, User-Agent | Opt-in (тот же переключатель, что NET-3), по умолчанию **выкл.**; кнопка — действие пользователя |
| NET-7 | GET APK новой версии (GitHub Releases, Range) | После NET-6, если есть новая версия | IP, User-Agent | Как NET-6 |
| ~~NET-4~~ | ~~Отчёты о падениях~~ — не реализуется в 1.x (ADR-0020, Q-09); диагностика — экспорт локального лога пользователем | — | — | — |
| NET-5 | Открытие URL GitHub issue в браузере | «Сообщить о проблеме» | Предзаполненный текст (устройство, ОС, параметры), без фото | Действие пользователя, предпросмотр текста |

| ID | Требование | Приоритет | Релиз | Трассировка |
|---|---|---|---|---|
| PRIV-NET-001 | Без действия пользователя приложение не выполняет сетевых запросов | Must | R0.1 | TEST-COMP-003 |
| PRIV-NET-002 | User-Agent не содержит уникальных идентификаторов; никаких cookies, рекламных ID, fingerprinting | Must | R0.2 | ревью |
| PRIV-NET-003 | Отчёт «плохой результат» не содержит фото, путей и метаданных по умолчанию; пользователь видит текст до отправки | Must | R0.5 | FR-REP-002 |
| PRIV-NET-004 | Только HTTPS; HTTP запрещён (Android `cleartextTrafficPermitted=false`, iOS ATS по умолчанию) | Must | R0.2 | SEC-NET-001 |

## 7. Политика приватности

Текст — [appendix/privacy-policy.md](appendix/privacy-policy.md). Публикуется в репозитории (`PRIVACY.md`), на сайте проекта и в сторах.

## 8. Декларации сторов

| Стор | Декларация |
|---|---|
| Google Play Data Safety | «Данные не собираются», «Данные не передаются» |
| App Store Privacy Nutrition Label | «Data Not Collected» |
| F-Droid | Без анти-фич Tracking (сетевые вызовы только по действию пользователя), отметка об опциональной загрузке NC-моделей в описании |
