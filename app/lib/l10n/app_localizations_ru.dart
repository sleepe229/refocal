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
}
