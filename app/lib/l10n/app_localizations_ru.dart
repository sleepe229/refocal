// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Refocal';

  @override
  String get homeTagline => 'Верните фото резкость.';

  @override
  String get homePrivacy => 'Всё работает на этом телефоне. Фото никуда не отправляются.';

  @override
  String get homeModelMissing => 'В этой сборке нет модели улучшения.';

  @override
  String get homeChoosePhoto => 'Выбрать фото';

  @override
  String get homeNotFinished => 'Не завершено';

  @override
  String homeCore(String version) {
    return 'Ядро $version';
  }

  @override
  String homeCoreUnavailable(String error) {
    return 'Нативное ядро недоступно: $error';
  }

  @override
  String homeOpenFailed(String error) {
    return 'Не удалось открыть фото: $error';
  }

  @override
  String get settingsTooltip => 'Настройки';

  @override
  String get aboutTooltip => 'О приложении';

  @override
  String get deleteTooltip => 'Удалить';

  @override
  String get jobTitleFinished => 'Улучшенное фото';

  @override
  String get jobTitlePaused => 'Улучшение на паузе';

  @override
  String jobReadyNotSaved(String scale) {
    return '$scale · готово, не сохранено';
  }

  @override
  String jobPausedAt(String scale, int percent) {
    return '$scale · пауза на $percent%';
  }

  @override
  String jobOriginalGone(String scale) {
    return '$scale · оригинал удалён, продолжить нельзя';
  }

  @override
  String get scaleX4 => '4×';

  @override
  String get scaleX2 => '2×';

  @override
  String get scaleFast2 => 'Быстрый 2×';

  @override
  String get scaleX1 => '1×';

  @override
  String get scaleX1Hint => '1×: размер тот же, убираются только шум и размытие.';

  @override
  String get editorTitle => 'Улучшение';

  @override
  String sizePx(int width, int height) {
    return '$width × $height пикс.';
  }

  @override
  String get enhance => 'Улучшить';

  @override
  String get aiDisclaimer =>
      'ИИ добавляет правдоподобные детали, которых не было на исходном фото.';

  @override
  String get stageWaiting => 'Ожидание…';

  @override
  String get stageReading => 'Чтение фото…';

  @override
  String stageEnhancing(int percent) {
    return 'Улучшение $percent%';
  }

  @override
  String stageEnhancingEta(int percent, int seconds) {
    return 'Улучшение $percent% · осталось ~$seconds с';
  }

  @override
  String get stageFinishing => 'Завершение…';

  @override
  String get stageWorking => 'Обработка…';

  @override
  String get pause => 'Пауза';

  @override
  String get cancel => 'Отмена';

  @override
  String get backgroundHint => 'Можно выйти из приложения: обработка продолжится в фоне.';

  @override
  String get pausedByTimeout =>
      'Пауза: Android ограничивает работу в фоне. Продолжите, когда будете готовы.';

  @override
  String pausedAt(int percent) {
    return 'Пауза на $percent%.';
  }

  @override
  String get continueAction => 'Продолжить';

  @override
  String get continueLater => 'Продолжить позже';

  @override
  String noteSwitchedTo(String backend) {
    return 'Переключено на $backend';
  }

  @override
  String get noteAlphaFlattened => 'Прозрачные области станут белыми';

  @override
  String get noteFirstFrame => 'Улучшается только первый кадр анимации';

  @override
  String get strength => 'Сила';

  @override
  String strengthValue(int percent) {
    return '$percent%';
  }

  @override
  String get strengthNeedsOriginal => 'Оригинал удалён: сохранить можно только с силой 100%.';

  @override
  String get saveToGallery => 'Сохранить в галерею';

  @override
  String get saveAsFile => 'Сохранить в файл…';

  @override
  String get savedToGallery => 'Сохранено в Pictures/Refocal';

  @override
  String get savedToFile => 'Сохранено';

  @override
  String saveFailed(String error) {
    return 'Не удалось сохранить: $error';
  }

  @override
  String get saveAsTitle => 'Сохранить как';

  @override
  String get tryAnotherScale => 'Другой масштаб';

  @override
  String get failCancelled => 'Отменено.';

  @override
  String get failPaused => 'На паузе.';

  @override
  String get failDiskFull => 'Недостаточно свободного места для такого размера.';

  @override
  String get failInvalid =>
      'Не удалось прочитать фото: формат не поддерживается или файл повреждён.';

  @override
  String get failLimit => 'Фото слишком большое (предел — 30000 пикс. по стороне и 200 Мп).';

  @override
  String get failOom => 'Не хватает памяти. Попробуйте «Быстрый 2×».';

  @override
  String failOther(String status) {
    return 'Что-то пошло не так ($status).';
  }

  @override
  String get back => 'Назад';

  @override
  String get tooLargeTitle => 'Фото слишком большое для этого масштаба';

  @override
  String get tooLargeBody => 'Выберите меньший размер результата.';

  @override
  String get notifEnhancing => 'Улучшение фото';

  @override
  String get notifReady => 'Фото готово. Нажмите, чтобы открыть.';

  @override
  String get notifFailed => 'Улучшение не удалось. Нажмите, чтобы открыть.';

  @override
  String get notifTimedOut =>
      'Пауза: Android ограничил время работы в фоне. Нажмите, чтобы продолжить.';

  @override
  String get notifChannelName => 'Обработка';

  @override
  String get notifChannelDescription => 'Ход улучшения фото';

  @override
  String get formatJpeg => 'JPEG';

  @override
  String get formatPng => 'PNG (без потерь)';

  @override
  String get formatWebp => 'WebP';

  @override
  String get formatWebpLossless => 'WebP (без потерь)';

  @override
  String get formatWebpTooLarge => 'WebP ограничен 50 Мп (без потерь — 24 Мп).';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSavedPhotos => 'Сохранённые фото';

  @override
  String get settingsFormat => 'Формат';

  @override
  String get settingsQuality => 'Качество';

  @override
  String get settingsQualityHint =>
      'Для JPEG и WebP. Выше — больше файл и ближе к результату на экране.';

  @override
  String get settingsMetadata => 'Метаданные';

  @override
  String get settingsMetadataBody =>
      'Дата, камера и цветовой профиль сохраняются. Серийные номера и служебные заметки камеры всегда удаляются.';

  @override
  String get settingsKeepLocation => 'Сохранять геопозицию';

  @override
  String get settingsKeepLocationSub => 'Выкл.: координаты GPS удаляются из результата.';

  @override
  String get settingsAiMarker => 'Отмечать как улучшенное ИИ';

  @override
  String get settingsAiMarkerSub =>
      'Записывает тег IPTC «trained algorithmic media», который могут показывать другие приложения.';

  @override
  String get markerOffTitle => 'Отключить отметку ИИ?';

  @override
  String get markerOffBody =>
      'Улучшенные фото содержат детали, придуманные ИИ. Без отметки зрители не узнают, что фото изменено.';

  @override
  String get markerKeep => 'Оставить';

  @override
  String get markerTurnOff => 'Отключить';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get languageSystem => 'Системный';

  @override
  String get languageName => 'Русский';

  @override
  String get settingsShowIntro => 'Показать вступление';

  @override
  String get aboutTitle => 'О приложении';

  @override
  String get aboutAlpha => 'Ранняя альфа. Возможны недочёты: только Android, одно фото за раз.';

  @override
  String get aboutPrivacy =>
      'Вся обработка происходит на устройстве. В Refocal нет аккаунтов, рекламы и телеметрии; сеть используется только для загрузки дополнительных моделей по вашему запросу.';

  @override
  String get aboutAiWarning =>
      'Улучшение ИИ добавляет правдоподобные детали, которых не было на исходном фото. Не используйте результаты как доказательство того, как выглядели место или человек.';

  @override
  String get aboutCredits => 'Благодарности';

  @override
  String aboutSource(String url) {
    return 'Исходный код (Apache-2.0): $url';
  }

  @override
  String get aboutLicenses => 'Лицензии открытого ПО';

  @override
  String get compareLabel => 'Сравнение до и после';

  @override
  String comparePercentOriginal(int percent) {
    return '$percent% оригинала';
  }

  @override
  String get tagOriginal => 'Оригинал';

  @override
  String get tagEnhanced => 'Улучшено';

  @override
  String get onbSkip => 'Пропустить';

  @override
  String get onbNext => 'Далее';

  @override
  String get onbStart => 'Начать';

  @override
  String get onb1Title => 'Всё остаётся на телефоне';

  @override
  String get onb1Body =>
      'Фото улучшаются на этом устройстве. Ничего не загружается, нет аккаунтов и слежки.';

  @override
  String get onb2Title => 'ИИ может менять детали';

  @override
  String get onb2Body =>
      'Модель добавляет детали, которые выглядят правдоподобно, но которых не было на фото: текст, лица и текстуры могут отличаться от реальности. Сохранённые фото отмечаются как улучшенные ИИ.';

  @override
  String get onb3Title => 'Сравните перед сохранением';

  @override
  String get onb3Body =>
      'Двигайте ползунок по результату, чтобы увидеть оригинал, и уменьшите силу, если эффект слишком сильный. Оригинал никогда не меняется.';

  @override
  String get historyTitle => 'История';

  @override
  String get historyEmpty => 'Здесь появятся сохранённые фото: их настройки и маленькое превью.';

  @override
  String get historyOff => 'История выключена. Включить её можно в настройках.';

  @override
  String get historyDeleteAll => 'Удалить всё';

  @override
  String get historyDeleteAllTitle => 'Удалить всю историю?';

  @override
  String get historyDeleteAllBody =>
      'Превью и настройки удаляются. Сохранённые фото остаются в галерее.';

  @override
  String historyDeleteFailed(String error) {
    return 'Не все файлы удалось удалить: $error';
  }

  @override
  String get historyEntryGone => 'Запись удалена.';

  @override
  String get historyScale => 'Масштаб';

  @override
  String get historyOriginalSize => 'Оригинал';

  @override
  String get historyResultSize => 'Результат';

  @override
  String get historyModel => 'Модель';

  @override
  String get historyBackend => 'Обработано на';

  @override
  String get historyDuration => 'Время';

  @override
  String historySeconds(int seconds) {
    return '$seconds с';
  }

  @override
  String get historyProcessAgain => 'Обработать ещё раз с другими настройками';

  @override
  String get historyOriginalGone =>
      'Оригинала больше нет на устройстве: история хранит только настройки и маленькое превью. Чтобы обработать фото, откройте его заново.';

  @override
  String get historyDeleteEntry => 'Удалить из истории';

  @override
  String historyNotRecorded(String error) {
    return 'Сохранено, но не добавлено в историю: $error';
  }

  @override
  String get historyOffTitle => 'Выключить историю?';

  @override
  String get historyOffBody => 'Текущая история удаляется, новые фото не записываются.';

  @override
  String get historyOffConfirm => 'Выключить';

  @override
  String get settingsKeepHistory => 'Вести историю';

  @override
  String get settingsKeepHistorySub =>
      'Настройки и маленькое превью каждого сохранённого фото, только на этом устройстве.';

  @override
  String settingsSaveFailed(String error) {
    return 'Не удалось сохранить настройку: $error';
  }

  @override
  String get presetsTitle => 'Пресеты';

  @override
  String get presetsBuiltin => 'Встроенные';

  @override
  String get presetsYours => 'Ваши';

  @override
  String get presetsEmpty => 'Сохраните пресет в редакторе после обработки фото.';

  @override
  String get presetFast => 'Быстро';

  @override
  String get presetQuality => 'Качество';

  @override
  String get presetRename => 'Переименовать';

  @override
  String get presetSaveAs => 'Сохранить как пресет';

  @override
  String get presetSaved => 'Пресет сохранён';

  @override
  String get presetSave => 'Сохранить';

  @override
  String presetSaveFailed(String error) {
    return 'Не удалось изменить пресеты: $error';
  }

  @override
  String get presetModelMissing => 'Для этого нужна модель, которая не установлена.';

  @override
  String get presetName => 'Название';

  @override
  String presetNameTooLong(int max) {
    return 'Не больше $max символов';
  }

  @override
  String presetStrengthAfter(String strength) {
    return 'Сила эффекта после обработки: $strength';
  }

  @override
  String get reportTitle => 'Сообщить о проблеме';

  @override
  String get reportEntry => 'Сообщить о проблеме';

  @override
  String get reportEntrySub => 'Посмотреть и отправить журнал приложения';

  @override
  String get reportIntro =>
      'Журнал помогает найти ошибки. В нём события и ошибки приложения — никогда ваши фото, имена файлов или геопозиция. Ничего не отправляется, пока вы сами не поделитесь им: приложите к issue или письму.';

  @override
  String get reportEmpty => 'Журнал пуст.';

  @override
  String get reportShare => 'Поделиться журналом';

  @override
  String get reportShareTitle => 'Журнал Refocal';

  @override
  String get errorStorage => 'не удалось прочитать или записать файл';

  @override
  String get errorSystem => 'система отклонила запрос';

  @override
  String get errorUnexpected => 'непредвиденная ошибка (подробности в журнале)';

  @override
  String get homeChooseSeveral => 'Обработать несколько фото';

  @override
  String homeQueue(int count) {
    return 'Очередь ($count)';
  }

  @override
  String pickPartial(int failed, String reason) {
    return 'Не удалось открыть фото: $failed. Причина: $reason';
  }

  @override
  String get queueTitle => 'Очередь';

  @override
  String get queueEmpty => 'Очередь пуста. Выберите несколько фото или поделитесь ими с Refocal.';

  @override
  String get queueStart => 'Запустить';

  @override
  String get queuePause => 'Пауза';

  @override
  String get queueClearFinished => 'Убрать завершённые';

  @override
  String get queueShowErrors => 'Только ошибки';

  @override
  String get queueStateQueued => 'Ожидает';

  @override
  String queueStateRunning(int percent) {
    return 'Обработка… $percent%';
  }

  @override
  String queueStatePaused(int percent) {
    return 'Пауза на $percent%';
  }

  @override
  String get queueStateDone => 'Готово, не сохранено: нажмите, чтобы открыть';

  @override
  String get queueStateSaved => 'Сохранено в галерею';

  @override
  String queueStateFailed(String reason) {
    return 'Ошибка: $reason';
  }

  @override
  String queueReport(int done, int failed) {
    return 'Готово $done, ошибок $failed';
  }

  @override
  String get queueReorderHint => 'Перетащите, чтобы изменить порядок.';

  @override
  String queueNotifPosition(int n, int total) {
    return 'Фото $n из $total';
  }

  @override
  String queueNotifDone(int done, int failed) {
    return 'Очередь завершена: готово $done, ошибок $failed';
  }

  @override
  String batchTitle(int count) {
    return 'Фото: $count';
  }

  @override
  String get batchPreset => 'Пресет';

  @override
  String batchAutosave(String format) {
    return 'Сохранять каждый результат в галерею ($format)';
  }

  @override
  String get batchAutosaveOff => 'Результаты ждут в очереди, пока вы их не сохраните.';

  @override
  String get batchAdd => 'Добавить в очередь';

  @override
  String get settingsBatchAutosave => 'Пакет: сохранять результаты автоматически';

  @override
  String get settingsBatchAutosaveHint =>
      'Каждый результат пакета попадает в Pictures/Refocal в формате по умолчанию.';

  @override
  String queueActionFailed(String error) {
    return 'Не удалось изменить очередь: $error';
  }

  @override
  String get storageTitle => 'Хранилище';

  @override
  String get settingsStorage => 'Хранилище';

  @override
  String storageTotal(String size) {
    return 'Всего: $size';
  }

  @override
  String storageMeasureFailed(String error) {
    return 'Не удалось посчитать место: $error';
  }

  @override
  String get storageClear => 'Очистить';

  @override
  String storageClearTitle(String category) {
    return 'Очистить: $category?';
  }

  @override
  String storageClearFailed(String error) {
    return 'Не всё удалось очистить: $error';
  }

  @override
  String get storageNoUndo => 'Это нельзя отменить.';

  @override
  String get storageCopies => 'Копии оригиналов';

  @override
  String get storageCopiesHint =>
      'нужны, чтобы обработать запись истории ещё раз; копии для приостановленных фото и очереди не считаются';

  @override
  String get storageCopiesClear =>
      'Записи истории больше нельзя будет обработать заново. Приостановленные фото и очередь свои копии сохранят.';

  @override
  String get storageUnfinished => 'Незавершённые';

  @override
  String get storageUnfinishedHint => 'приостановленные и несохранённые результаты редактора';

  @override
  String get storageUnfinishedClear =>
      'Приостановленные и несохранённые результаты будут удалены. Очередь не затрагивается.';

  @override
  String get storageHistoryHint => 'превью сохранённых результатов';

  @override
  String get storageHistoryClear =>
      'Вся история будет удалена. Сохранённые фото останутся в галерее.';

  @override
  String get storageCache => 'Кэш';

  @override
  String get storageCacheHint => 'временные копии для сохранения и отправки';

  @override
  String get storageLogs => 'Журнал';

  @override
  String get storageLogsHint => 'для отчётов об ошибках, сам никуда не отправляется';

  @override
  String get storageModels => 'Модели';

  @override
  String get storageModelsHint => 'встроены в приложение';

  @override
  String sizeKb(String n) {
    return '$n КБ';
  }

  @override
  String sizeMb(String n) {
    return '$n МБ';
  }

  @override
  String sizeGb(String n) {
    return '$n ГБ';
  }

  @override
  String get noteThermalWait => 'Телефон перегрелся: ждём, пока остынет.';

  @override
  String get noteThermalThrottle => 'Телефон нагрелся: обработка идёт медленнее.';

  @override
  String get compareShowOriginal => 'Показать оригинал';

  @override
  String get compareShowResult => 'Показать результат';

  @override
  String resultAlt(int width, int height) {
    return 'Результат, $width×$height, улучшено ИИ';
  }

  @override
  String get modelsTitle => 'Модели';

  @override
  String get settingsModels => 'Модели';

  @override
  String get modelsBuiltIn => 'Встроенная: Real-ESRGAN general (денойз 0.5)';

  @override
  String get modelsBuiltInHint => 'Доступна всегда, работает без сети.';

  @override
  String get modelsCheck => 'Проверить модели';

  @override
  String get modelsNotChecked => 'Нажмите «Проверить модели», чтобы увидеть, что можно скачать.';

  @override
  String get modelsPrivacy =>
      'Refocal выходит в интернет, только когда вы проверяете или скачиваете модели. Файлы проверяются подписью и контрольной суммой перед использованием.';

  @override
  String get modelsNonCommercial => 'некоммерческая';

  @override
  String get modelsInstalled => 'установлена';

  @override
  String modelsUpdate(String installedVersion, String availableVersion) {
    return 'установлена $installedVersion, доступна $availableVersion';
  }

  @override
  String get modelsUpdateAction => 'Обновить';

  @override
  String get modelsDownload => 'Скачать';

  @override
  String get modelsDelete => 'Удалить';

  @override
  String modelsDownloading(int percent) {
    return 'Загрузка… $percent%';
  }

  @override
  String get modelsErrorNetwork => 'Сервер моделей недоступен. Проверьте соединение и повторите.';

  @override
  String get modelsErrorIntegrity => 'Загрузка не прошла проверку и не используется.';

  @override
  String get modelsErrorRollback =>
      'Сервер прислал более старый список моделей; он не используется.';

  @override
  String modelsLicenseTitle(String name) {
    return 'Лицензия: $name';
  }

  @override
  String get modelsLicenseIntro =>
      'Эта модель свободна не для любого использования. Прочитайте лицензию и скачивайте, только если согласны.';

  @override
  String get modelsLicenseAccept => 'Принять и скачать';

  @override
  String get denoise => 'Шумоподавление';

  @override
  String get denoiseNone => 'Выкл.';

  @override
  String get denoiseStandard => 'Обычное';

  @override
  String get denoiseStrong => 'Сильное';

  @override
  String get presetPortrait => 'Портрет';

  @override
  String get presetOldPhoto => 'Старое фото';

  @override
  String recipeFaces(int percent) {
    return 'лица $percent%';
  }

  @override
  String get faces => 'Восстанавливать лица';

  @override
  String get facesHint => 'Каждое лицо обрабатывается моделью лиц и смешивается с улучшенным фото.';

  @override
  String get facesStrength => 'Сила для лиц';

  @override
  String get facesNeedPack =>
      'Для восстановления лиц нужна модель лиц (около 177 МБ, некоммерческая лицензия).';

  @override
  String get facesGetPack => 'Модели';

  @override
  String get facesNoticeTitle => 'О восстановлении лиц';

  @override
  String get facesNoticeBody =>
      'Модель лиц перерисовывает лица по тому, чему она научилась. Лица могут стать чётче, но и не совсем похожими на человека — особенно на старых и мелких фото. Refocal смешивает результат с оригиналом (по умолчанию 50%) и помечает сохранённые фото как обработанные ИИ.';

  @override
  String get facesNoticeOk => 'Понятно';

  @override
  String stageFaces(int percent) {
    return 'Восстановление лиц… $percent%';
  }

  @override
  String noteFacesFound(int count) {
    return 'Найдено лиц: $count';
  }

  @override
  String get regionAll => 'Всё фото';

  @override
  String get regionFaces => 'Только лица';

  @override
  String get tierTitle => 'Класс устройства';

  @override
  String get tierAuto => 'Авто';

  @override
  String tierMeasured(String tier, String backend, int ms) {
    return '$tier по тесту скорости: $backend, $ms мс на тайл';
  }

  @override
  String get tierGpu => 'графический процессор';

  @override
  String get tierCpu => 'процессор';

  @override
  String get tierUnknown => 'Не измерен: T0, самый осторожный';

  @override
  String get tierMeasuring => 'Измеряем…';

  @override
  String get autoChip => 'Авто';

  @override
  String get autoAnalyzing => 'Смотрим на фото…';

  @override
  String get autoFailed => 'Авто недоступно: не удалось проанализировать фото';

  @override
  String autoFaces(int count) {
    return 'лиц: $count';
  }

  @override
  String get autoFacesNotRestored => 'на этом устройстве не восстанавливаются';

  @override
  String get autoFacesNeedPack => 'модель лиц не установлена';

  @override
  String get autoFacesOnly => 'только лица';

  @override
  String get autoDenoiseNone => 'без денойза';

  @override
  String get autoDenoiseStandard => 'денойз средний';

  @override
  String get autoDenoiseStrong => 'денойз сильный';

  @override
  String get noteTileSmaller => 'Мало памяти: обрабатываем мелкими частями, медленнее';

  @override
  String noteFaceSkipped(int number) {
    return 'Снижено качество обработки: лицо $number не удалось восстановить';
  }

  @override
  String get noteFacesSkipped => 'Снижено качество обработки: лица не удалось восстановить';

  @override
  String get oomTitle => 'Недостаточно памяти';

  @override
  String oomBody(String scale) {
    return 'Недостаточно памяти для $scale. Обработать в меньшем масштабе?';
  }

  @override
  String get modelsImport => 'Импортировать файл .rfpack';

  @override
  String modelsImported(String name) {
    return 'Установлено: $name';
  }

  @override
  String get modelsErrorNotAPack => 'Это не пакет моделей Refocal, или файл повреждён';

  @override
  String get modelsErrorStorage => 'Не удалось прочитать файл';
}
