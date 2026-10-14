# ADR-0009: Persistence: drift (SQLite)

- **Статус:** Accepted
- **Дата:** 2026-10-09

## Контекст

История, очередь, пресеты, паки, согласия, кэш бенчмарка, настройки — нужны транзакции, миграции, запросы.

## Решение

drift (SQLite) с версионированными миграциями и тестами миграций. Файлы — в `AppSupport/` (models, jobs, inbox) и `Cache/`.

## Поправка (2026-10-14, 0.0.4)

Реализация (0.0.2–0.0.3 жили на `settings.json`, теперь закрыто):

- **SQLite собирается из исходников.** `package:sqlite3` 3.x подключает библиотеку build hook'ом (`sqlite3_flutter_libs` — EOL); по умолчанию hook скачивает готовые бинарники с GitHub, что противоречит COMP-FDR-001. Поэтому в `native/third_party/sqlite` лежит amalgamation (версия = та, что встраивает `package:sqlite3`, README с SHA3-256 sqlite.org), а корневой `pubspec.yaml` задаёт `hooks: user_defines: sqlite3: source: source`. Hook компилирует её NDK-тулчейном в `libsqlite3.so` (на хосте для тестов — `clang`). `drift_flutter`/`path_provider` не нужны: каталоги даёт `refocal_platform` (`AppDirs`).
- **Где:** `AppSupport/db.sqlite` (Android — `noBackupFilesDir`, как и прежний JSON; бэкап настроек по PRIV-DATA-005 — отдельный вопрос), открывается в фоновом изоляте (`NativeDatabase.createInBackground`), `PRAGMA foreign_keys = ON`.
- **Код:** таблицы и репозитории — в `packages/refocal_core` (03 §2.1, чистый Dart, тесты `dart test`); провайдеры — в `app/lib/bootstrap`. Сгенерированный `database.g.dart`, дампы схем `drift_schemas/refocal/drift_schema_vN.json` и `test/drift/refocal/generated/` коммитятся; обновление — `dart run build_runner build && dart run drift_dev make-migrations` в `packages/refocal_core`.
- **Миграции (PRIV-DATA-001, TEST-DB-001):** схема 07 §3 растёт по мере появления функций, каждая версия — дамп и `stepByStep`-шаг; `migration_test.dart` проверяет все пары версий `SchemaVerifier`'ом, совпадение текущего кода с последним дампом и отказ открывать БД более новой версии (после установки старого APK данные не портятся). v1: `settings`, `assets`, `recipes`, `history`, `presets`; `queue_jobs` добавит очередь миграцией v2 (ссылки на `assets`/`recipes` уже есть; очистка «сирот» в `HistoryRepository` должна учесть и её).
- **Отличия от 07 §3** (07 обновлён): пути хранятся относительно AppSupport (контейнер iOS меняет путь при обновлении), время — Unix-миллисекунды; `assets` без `sha256`/`mime`/`keep` до дедупликации inbox (FR-IMP-004) и опции «Хранить для повторной обработки»; в `history` есть `job_id` (FR-HIST-004 удаляет BandStore); встроенные пресеты (FR-PRE-001) — в коде приложения рядом с моделями, которые им нужны, в `presets` только пользовательские, без `builtin`; превью истории — в `AppSupport/history/`, а не в `Cache/previews/`: система может очистить кэш, пока запись жива.
- **Настройки:** `settings(key, value)` строками, проверка значений — в одном месте (`Settings.fromStore`). `settings.json` импортируется один раз (version 1 → онбординг пройден) и удаляется; запись настроек сериализована, состояние меняется только после записи.

## Последствия

(+) Надёжно, типобезопасно, тестируемо. (−) Кодогенерация. (−) Размер APK: `libsqlite3.so` и Dart-код drift (оценка R13 — +2…2.5 МБ, замер — при сборке 0.0.4).

## Отклонённые альтернативы

- Isar/Hive: заброшены/нестабильны. shared_preferences как основное хранилище: нет структуры.
