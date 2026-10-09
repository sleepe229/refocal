# ADR-0019: Background execution

- **Статус:** Accepted
- **Дата:** 2026-10-09

## Контекст

iOS запрещает GPU в фоне (на iOS 26 возможен краш); `BGContinuedProcessingTask` без GPU на iPhone; у Android FGS лимиты (API 35+: `mediaProcessing` 6 ч/24 ч, `onTimeout`).

## Решение

- **iOS:** на `willResignActive` → `enh_set_gpu_allowed(0)` → завершение текущего тайла под `beginBackgroundTask` (≤ 30 с) → checkpoint → выгрузка GPU-ресурсов; resume при `didBecomeActive`. GPU в фоне не используется никогда. R1.3: opt-in продолжение на ncnn CPU через `BGContinuedProcessingTask` (iOS 26).
- **Android:** foreground service типа `mediaProcessing`, запускаемый действием пользователя при непустой очереди; FlutterEngine кэширован в Application; `onTimeout` → пауза + checkpoint + уведомление «Продолжить».

## Последствия

(+) Нет крэшей, пакеты на Android идут в фоне. (−) На iOS пакет требует открытого приложения.

## Отклонённые альтернативы

- `BGProcessingTask`: откладывается до простоя, бесполезен для интерактива. - WorkManager без FGS: убивается.
