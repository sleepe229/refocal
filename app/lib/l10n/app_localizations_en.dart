// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Refocal';

  @override
  String get homeTagline => 'Bring your photos back into focus.';

  @override
  String get homePrivacy => 'Everything runs on this phone. Photos never leave it.';

  @override
  String get homeModelMissing => 'The enhancement model is missing from this build.';

  @override
  String get homeChoosePhoto => 'Choose a photo';

  @override
  String get homeNotFinished => 'Not finished';

  @override
  String homeCore(String version) {
    return 'Core $version';
  }

  @override
  String homeCoreUnavailable(String error) {
    return 'Native core unavailable: $error';
  }

  @override
  String homeOpenFailed(String error) {
    return 'Could not open the photo: $error';
  }

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get aboutTooltip => 'About';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String get jobTitleFinished => 'Enhanced photo';

  @override
  String get jobTitlePaused => 'Paused enhancement';

  @override
  String jobReadyNotSaved(String scale) {
    return '$scale · ready, not saved';
  }

  @override
  String jobPausedAt(String scale, int percent) {
    return '$scale · paused at $percent%';
  }

  @override
  String jobOriginalGone(String scale) {
    return '$scale · the original is gone, cannot continue';
  }

  @override
  String get scaleX4 => '4×';

  @override
  String get scaleX2 => '2×';

  @override
  String get scaleFast2 => 'Fast 2×';

  @override
  String get scaleX1 => '1×';

  @override
  String get scaleX1Hint => '1×: same size, only noise and blur are cleaned up.';

  @override
  String get editorTitle => 'Enhance';

  @override
  String sizePx(int width, int height) {
    return '$width × $height px';
  }

  @override
  String get enhance => 'Enhance';

  @override
  String get aiDisclaimer => 'AI adds plausible detail that was not in the original photo.';

  @override
  String get stageWaiting => 'Waiting…';

  @override
  String get stageReading => 'Reading the photo…';

  @override
  String stageEnhancing(int percent) {
    return 'Enhancing $percent%';
  }

  @override
  String stageEnhancingEta(int percent, int seconds) {
    return 'Enhancing $percent% · ~$seconds s left';
  }

  @override
  String get stageFinishing => 'Finishing…';

  @override
  String get stageWorking => 'Working…';

  @override
  String get pause => 'Pause';

  @override
  String get cancel => 'Cancel';

  @override
  String get backgroundHint => 'You can leave the app: processing continues in the background.';

  @override
  String get pausedByTimeout =>
      'Paused: Android limits background work. Continue when you are ready.';

  @override
  String pausedAt(int percent) {
    return 'Paused at $percent%.';
  }

  @override
  String get continueAction => 'Continue';

  @override
  String get continueLater => 'Continue later';

  @override
  String noteSwitchedTo(String backend) {
    return 'Switched to $backend';
  }

  @override
  String get noteAlphaKept => 'Transparency is kept in PNG and WebP; in JPEG it becomes white';

  @override
  String get noteFirstFrame => 'Only the first frame of the animation is enhanced';

  @override
  String get strength => 'Strength';

  @override
  String strengthValue(int percent) {
    return '$percent%';
  }

  @override
  String get strengthNeedsOriginal =>
      'The original photo is gone: only 100% strength can be saved.';

  @override
  String get saveToGallery => 'Save to gallery';

  @override
  String get saveAsFile => 'Save as file…';

  @override
  String get savedToGallery => 'Saved to Pictures/Refocal';

  @override
  String get savedToFile => 'Saved';

  @override
  String saveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get saveAsTitle => 'Save as';

  @override
  String get tryAnotherScale => 'Try another scale';

  @override
  String get failCancelled => 'Cancelled.';

  @override
  String get failPaused => 'Paused.';

  @override
  String get failDiskFull => 'Not enough free storage for this size.';

  @override
  String get failInvalid =>
      'This photo could not be read: the format is not supported or the file is damaged.';

  @override
  String get failLimit => 'This photo is too large (the limit is 30000 px per side and 200 MP).';

  @override
  String get failOom => 'Not enough memory. Try Fast 2×.';

  @override
  String failOther(String status) {
    return 'Something went wrong ($status).';
  }

  @override
  String get back => 'Back';

  @override
  String get tooLargeTitle => 'This photo is too large for that scale';

  @override
  String get tooLargeBody => 'Choose a smaller output size.';

  @override
  String get notifEnhancing => 'Enhancing a photo';

  @override
  String get notifReady => 'Photo ready. Tap to open.';

  @override
  String get notifFailed => 'Enhancement failed. Tap to open.';

  @override
  String get notifTimedOut =>
      'Paused: Android\'s time limit for background work was reached. Tap to continue.';

  @override
  String get notifChannelName => 'Processing';

  @override
  String get notifChannelDescription => 'Progress of photos being enhanced';

  @override
  String get formatJpeg => 'JPEG';

  @override
  String get formatPng => 'PNG (lossless)';

  @override
  String get formatWebp => 'WebP';

  @override
  String get formatWebpLossless => 'WebP (lossless)';

  @override
  String get formatWebpTooLarge => 'WebP is limited to 50 MP (lossless: 24 MP).';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSavedPhotos => 'Saved photos';

  @override
  String get settingsFormat => 'Format';

  @override
  String get settingsQuality => 'Quality';

  @override
  String get settingsQualityHint =>
      'JPEG and WebP. Higher is larger and closer to the result on screen.';

  @override
  String get settingsMetadata => 'Metadata';

  @override
  String get settingsMetadataBody =>
      'Date, camera and color profile are kept. Camera serial numbers and the maker notes are always removed.';

  @override
  String get settingsKeepLocation => 'Keep location';

  @override
  String get settingsKeepLocationSub => 'Off: GPS coordinates are removed from the result.';

  @override
  String get settingsAiMarker => 'Mark as AI-enhanced';

  @override
  String get settingsAiMarkerSub =>
      'Writes the IPTC \"trained algorithmic media\" tag, which other apps can show.';

  @override
  String get markerOffTitle => 'Turn off the AI marker?';

  @override
  String get markerOffBody =>
      'Enhanced photos contain detail the AI invented. Without the marker, people who see the photo cannot tell it was changed.';

  @override
  String get markerKeep => 'Keep it';

  @override
  String get markerTurnOff => 'Turn off';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageName => 'English';

  @override
  String get settingsShowIntro => 'Show the introduction';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutAlpha => 'Early alpha. Expect rough edges: Android only, one photo at a time.';

  @override
  String get aboutPrivacy =>
      'All processing happens on this device. Refocal has no accounts, no ads and no telemetry; the network is used only to download optional models when you ask.';

  @override
  String get aboutAiWarning =>
      'AI enhancement adds plausible detail that was not in the original photo. Do not use results as evidence of what a scene or person looked like.';

  @override
  String get aboutCredits => 'Credits';

  @override
  String aboutSource(String url) {
    return 'Source code (Apache-2.0): $url';
  }

  @override
  String get aboutLicenses => 'Open-source licenses';

  @override
  String get compareLabel => 'Before and after comparison';

  @override
  String comparePercentOriginal(int percent) {
    return '$percent% original';
  }

  @override
  String get tagOriginal => 'Original';

  @override
  String get tagEnhanced => 'Enhanced';

  @override
  String get onbSkip => 'Skip';

  @override
  String get onbNext => 'Next';

  @override
  String get onbStart => 'Start';

  @override
  String get onb1Title => 'Everything stays on your phone';

  @override
  String get onb1Body =>
      'Photos are enhanced on this device. Nothing is uploaded, there are no accounts and no tracking.';

  @override
  String get onb2Title => 'AI can change details';

  @override
  String get onb2Body =>
      'The model adds detail that looks right but was not in the photo: text, faces and textures may differ from reality. Saved photos are marked as AI-enhanced.';

  @override
  String get onb3Title => 'Compare before you save';

  @override
  String get onb3Body =>
      'Drag the slider over the result to see the original, and lower the strength if the effect is too much. The original is never changed.';

  @override
  String get historyTitle => 'History';

  @override
  String get historyEmpty => 'Saved photos appear here with their settings and a small preview.';

  @override
  String get historyOff => 'History is off. Turn it on in Settings.';

  @override
  String get historyDeleteAll => 'Delete all';

  @override
  String get historyDeleteAllTitle => 'Delete the whole history?';

  @override
  String get historyDeleteAllBody =>
      'Previews and settings are deleted. Saved photos stay in the gallery.';

  @override
  String historyDeleteFailed(String error) {
    return 'Some files could not be deleted: $error';
  }

  @override
  String get historyEntryGone => 'This entry was deleted.';

  @override
  String get historyScale => 'Scale';

  @override
  String get historyOriginalSize => 'Original';

  @override
  String get historyResultSize => 'Result';

  @override
  String get historyModel => 'Model';

  @override
  String get historyBackend => 'Processed on';

  @override
  String get historyDuration => 'Time';

  @override
  String historySeconds(int seconds) {
    return '$seconds s';
  }

  @override
  String get historyProcessAgain => 'Process again with other settings';

  @override
  String get historyOriginalGone =>
      'The original is no longer on this device: history keeps only the settings and a small preview. Open the photo again to process it.';

  @override
  String get historyDeleteEntry => 'Delete from history';

  @override
  String historyNotRecorded(String error) {
    return 'Saved, but not added to the history: $error';
  }

  @override
  String get historyOffTitle => 'Turn off the history?';

  @override
  String get historyOffBody => 'The current history is deleted and new photos are not recorded.';

  @override
  String get historyOffConfirm => 'Turn off';

  @override
  String get settingsKeepHistory => 'Keep a history';

  @override
  String get settingsKeepHistorySub =>
      'Settings and a small preview of each saved photo, on this device only.';

  @override
  String settingsSaveFailed(String error) {
    return 'Could not save the setting: $error';
  }

  @override
  String get presetsTitle => 'Presets';

  @override
  String get presetsBuiltin => 'Built-in';

  @override
  String get presetsYours => 'Yours';

  @override
  String get presetsEmpty => 'Save one from the editor after enhancing a photo.';

  @override
  String get presetFast => 'Fast';

  @override
  String get presetQuality => 'Quality';

  @override
  String get presetRename => 'Rename';

  @override
  String get presetSaveAs => 'Save as preset';

  @override
  String get presetSaved => 'Preset saved';

  @override
  String get presetSave => 'Save';

  @override
  String presetSaveFailed(String error) {
    return 'Could not change the presets: $error';
  }

  @override
  String get presetModelMissing => 'This needs a model that is not installed.';

  @override
  String get presetName => 'Name';

  @override
  String presetNameTooLong(int max) {
    return 'At most $max characters';
  }

  @override
  String presetStrengthAfter(String strength) {
    return 'Strength $strength after enhancing';
  }

  @override
  String get reportTitle => 'Report a problem';

  @override
  String get reportEntry => 'Report a problem';

  @override
  String get reportEntrySub => 'View and share the app\'s log';

  @override
  String get reportIntro =>
      'This log helps find bugs. It contains app events and errors, never your photos, file names or locations. Nothing is sent until you share it; attach it to an issue or an e-mail.';

  @override
  String get reportEmpty => 'The log is empty.';

  @override
  String get reportShare => 'Share the log';

  @override
  String get reportShareTitle => 'Share the Refocal log';

  @override
  String get errorStorage => 'a file could not be read or written';

  @override
  String get errorSystem => 'the system refused the request';

  @override
  String get errorUnexpected => 'unexpected error (details are in the log)';

  @override
  String get homeChooseSeveral => 'Process several photos';

  @override
  String homeQueue(int count) {
    return 'Queue ($count)';
  }

  @override
  String pickPartial(int failed, String reason) {
    return '$failed of the photos could not be opened: $reason';
  }

  @override
  String get queueTitle => 'Queue';

  @override
  String get queueEmpty => 'The queue is empty. Choose several photos, or share them to Refocal.';

  @override
  String get queueStart => 'Start';

  @override
  String get queuePause => 'Pause';

  @override
  String get queueClearFinished => 'Clear finished';

  @override
  String get queueShowErrors => 'Only errors';

  @override
  String get queueStateQueued => 'Waiting';

  @override
  String queueStateRunning(int percent) {
    return 'Processing… $percent%';
  }

  @override
  String queueStatePaused(int percent) {
    return 'Paused at $percent%';
  }

  @override
  String get queueStateDone => 'Ready, not saved: tap to open';

  @override
  String get queueStateSaved => 'Saved to the gallery';

  @override
  String queueStateFailed(String reason) {
    return 'Failed: $reason';
  }

  @override
  String queueReport(int done, int failed) {
    return 'Done $done, failed $failed';
  }

  @override
  String get queueReorderHint => 'Drag to change the order.';

  @override
  String queueNotifPosition(int n, int total) {
    return 'Photo $n of $total';
  }

  @override
  String queueNotifDone(int done, int failed) {
    return 'Queue finished: done $done, failed $failed';
  }

  @override
  String batchTitle(int count) {
    return '$count photos';
  }

  @override
  String get batchPreset => 'Preset';

  @override
  String batchAutosave(String format) {
    return 'Save each result to the gallery ($format)';
  }

  @override
  String get batchAutosaveOff => 'Results wait in the queue until you save them.';

  @override
  String get batchAdd => 'Add to the queue';

  @override
  String get settingsBatchAutosave => 'Batch: save results automatically';

  @override
  String get settingsBatchAutosaveHint =>
      'Each result of a batch goes to Pictures/Refocal in the default format.';

  @override
  String queueActionFailed(String error) {
    return 'Could not change the queue: $error';
  }

  @override
  String get storageTitle => 'Storage';

  @override
  String get settingsStorage => 'Storage';

  @override
  String storageTotal(String size) {
    return 'Total: $size';
  }

  @override
  String storageMeasureFailed(String error) {
    return 'Could not measure the storage: $error';
  }

  @override
  String get storageClear => 'Clear';

  @override
  String storageClearTitle(String category) {
    return 'Clear: $category?';
  }

  @override
  String storageClearFailed(String error) {
    return 'Could not clear everything: $error';
  }

  @override
  String get storageNoUndo => 'This cannot be undone.';

  @override
  String get storageCopies => 'Copies of originals';

  @override
  String get storageCopiesHint =>
      'kept to process a history entry again; copies a paused job or the queue needs are not counted';

  @override
  String get storageCopiesClear =>
      'History entries can no longer be processed again. Paused jobs and the queue keep their copies.';

  @override
  String get storageUnfinished => 'Unfinished jobs';

  @override
  String get storageUnfinishedHint => 'paused or unsaved results of the editor';

  @override
  String get storageUnfinishedClear =>
      'Paused and unsaved results are deleted. The queue is not affected.';

  @override
  String get storageHistoryHint => 'previews of saved results';

  @override
  String get storageHistoryClear =>
      'The whole history is deleted. Saved photos stay in the gallery.';

  @override
  String get storageCache => 'Cache';

  @override
  String get storageCacheHint => 'temporary copies for saving and sharing';

  @override
  String get storageLogs => 'Log';

  @override
  String get storageLogsHint => 'for bug reports, never sent by itself';

  @override
  String get storageModels => 'Models';

  @override
  String get storageModelsHint => 'built into the app';

  @override
  String sizeKb(String n) {
    return '$n KB';
  }

  @override
  String sizeMb(String n) {
    return '$n MB';
  }

  @override
  String sizeGb(String n) {
    return '$n GB';
  }

  @override
  String get noteThermalWait => 'The phone is hot: waiting for it to cool down.';

  @override
  String get noteThermalThrottle => 'The phone is warm: processing more slowly.';

  @override
  String get compareShowOriginal => 'Show original';

  @override
  String get compareShowResult => 'Show result';

  @override
  String resultAlt(int width, int height) {
    return 'Result, $width×$height, enhanced by AI';
  }

  @override
  String get modelsTitle => 'Models';

  @override
  String get settingsModels => 'Models';

  @override
  String get modelsBuiltIn => 'Built in: Real-ESRGAN general (denoise 0.5)';

  @override
  String get modelsBuiltInHint => 'Always available, works offline.';

  @override
  String get modelsCheck => 'Check for models';

  @override
  String get modelsNotChecked => 'Tap \"Check for models\" to see what can be downloaded.';

  @override
  String get modelsPrivacy =>
      'Refocal connects to the internet only when you check for models or download one. Files are verified with a signature and a checksum before use.';

  @override
  String get modelsNonCommercial => 'non-commercial';

  @override
  String get modelsInstalled => 'installed';

  @override
  String modelsUpdate(String installedVersion, String availableVersion) {
    return 'installed $installedVersion, available $availableVersion';
  }

  @override
  String get modelsUpdateAction => 'Update';

  @override
  String get modelsDownload => 'Download';

  @override
  String get modelsDelete => 'Delete';

  @override
  String modelsDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get modelsErrorNetwork =>
      'Could not reach the model server. Check the connection and try again.';

  @override
  String get modelsErrorIntegrity => 'The download did not pass verification and was not used.';

  @override
  String get modelsErrorRollback => 'The server offered an older model list; it was not used.';

  @override
  String modelsLicenseTitle(String name) {
    return 'License: $name';
  }

  @override
  String get modelsLicenseIntro =>
      'This model is not free for every use. Read its license; download it only if you accept it.';

  @override
  String get modelsLicenseAccept => 'Accept and download';

  @override
  String get denoise => 'Denoise';

  @override
  String get denoiseNone => 'Off';

  @override
  String get denoiseStandard => 'Standard';

  @override
  String get denoiseStrong => 'Strong';

  @override
  String get presetPortrait => 'Portrait';

  @override
  String get presetOldPhoto => 'Old photo';

  @override
  String recipeFaces(int percent) {
    return 'faces $percent%';
  }

  @override
  String get faces => 'Restore faces';

  @override
  String get facesHint =>
      'Uses the face model on each face, then blends it with the enhanced photo.';

  @override
  String get facesStrength => 'Face strength';

  @override
  String get facesNeedPack =>
      'Face restoration needs the face model (about 177 MB, non-commercial license).';

  @override
  String get facesGetPack => 'Models';

  @override
  String get facesNoticeTitle => 'About face restoration';

  @override
  String get facesNoticeBody =>
      'The face model redraws faces from what it has learned. Faces can look sharper but also different from the real person, especially in old or small photos. Refocal blends the result with the original (50% by default) and marks saved photos as AI-edited.';

  @override
  String get facesNoticeOk => 'I understand';

  @override
  String stageFaces(int percent) {
    return 'Restoring faces… $percent%';
  }

  @override
  String noteFacesFound(int count) {
    return 'Faces found: $count';
  }

  @override
  String get regionAll => 'Whole photo';

  @override
  String get regionFaces => 'Only faces';

  @override
  String get tierTitle => 'Device class';

  @override
  String get tierAuto => 'Auto';

  @override
  String tierMeasured(String tier, String backend, int ms) {
    return '$tier by the speed test: $backend, $ms ms per tile';
  }

  @override
  String get tierGpu => 'graphics processor';

  @override
  String get tierCpu => 'processor';

  @override
  String get tierUnknown => 'Not measured: T0, the safe one';

  @override
  String get tierMeasuring => 'Measuring…';

  @override
  String get autoChip => 'Auto';

  @override
  String get autoAnalyzing => 'Looking at the photo…';

  @override
  String get autoFailed => 'Auto is unavailable: the photo could not be analysed';

  @override
  String autoFaces(int count) {
    return 'faces: $count';
  }

  @override
  String get autoFacesNotRestored => 'not restored on this device';

  @override
  String get autoFacesNeedPack => 'face model not installed';

  @override
  String get autoFacesOnly => 'only faces';

  @override
  String get autoDenoiseNone => 'no denoise';

  @override
  String get autoDenoiseStandard => 'denoise medium';

  @override
  String get autoDenoiseStrong => 'denoise strong';

  @override
  String get noteTileSmaller => 'Low on memory: processing in smaller pieces, slower';

  @override
  String noteFaceSkipped(int number) {
    return 'Reduced quality: face $number could not be restored';
  }

  @override
  String get noteFacesSkipped => 'Reduced quality: faces could not be restored';

  @override
  String get oomTitle => 'Not enough memory';

  @override
  String oomBody(String scale) {
    return 'Not enough memory for $scale. Process at a smaller size?';
  }

  @override
  String get modelsImport => 'Import a .rfpack file';

  @override
  String modelsImported(String name) {
    return 'Installed: $name';
  }

  @override
  String get modelsErrorNotAPack => 'Not a Refocal model pack, or the file is damaged';

  @override
  String get modelsErrorStorage => 'The file could not be read';

  @override
  String get faceOfferTitle => 'Face model for portraits';

  @override
  String get faceOfferBody =>
      'Restores faces in old and small photos. Downloaded separately: about 177 MB, for non-commercial use.';

  @override
  String get faceOfferOpen => 'Models';

  @override
  String get faceOfferLater => 'Not now';

  @override
  String get facesTapHint => 'Tap a face to leave it as it is';

  @override
  String faceToggle(int number) {
    return 'Face $number: restore';
  }

  @override
  String get fragmentTitle => 'Preview of a part';

  @override
  String get fragmentRunning => 'Enhancing a part of the photo…';

  @override
  String fragmentInfo(int width, int height, String seconds) {
    return 'Part $width × $height px in $seconds s';
  }

  @override
  String get fragmentEnhanceAll => 'Enhance the whole photo';

  @override
  String get fragmentAction => 'Preview a part';

  @override
  String get fragmentHint => 'Tap the photo to choose the part';

  @override
  String get close => 'Close';
}
