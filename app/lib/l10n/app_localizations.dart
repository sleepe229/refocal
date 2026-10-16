import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en'), Locale('ru')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Refocal'**
  String get appTitle;

  /// No description provided for @homeTagline.
  ///
  /// In en, this message translates to:
  /// **'Bring your photos back into focus.'**
  String get homeTagline;

  /// No description provided for @homePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Everything runs on this phone. Photos never leave it.'**
  String get homePrivacy;

  /// No description provided for @homeModelMissing.
  ///
  /// In en, this message translates to:
  /// **'The enhancement model is missing from this build.'**
  String get homeModelMissing;

  /// No description provided for @homeChoosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose a photo'**
  String get homeChoosePhoto;

  /// No description provided for @homeNotFinished.
  ///
  /// In en, this message translates to:
  /// **'Not finished'**
  String get homeNotFinished;

  /// No description provided for @homeCore.
  ///
  /// In en, this message translates to:
  /// **'Core {version}'**
  String homeCore(String version);

  /// No description provided for @homeCoreUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Native core unavailable: {error}'**
  String homeCoreUnavailable(String error);

  /// No description provided for @homeOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the photo: {error}'**
  String homeOpenFailed(String error);

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @aboutTooltip.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTooltip;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// No description provided for @jobTitleFinished.
  ///
  /// In en, this message translates to:
  /// **'Enhanced photo'**
  String get jobTitleFinished;

  /// No description provided for @jobTitlePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused enhancement'**
  String get jobTitlePaused;

  /// No description provided for @jobReadyNotSaved.
  ///
  /// In en, this message translates to:
  /// **'{scale} · ready, not saved'**
  String jobReadyNotSaved(String scale);

  /// No description provided for @jobPausedAt.
  ///
  /// In en, this message translates to:
  /// **'{scale} · paused at {percent}%'**
  String jobPausedAt(String scale, int percent);

  /// No description provided for @jobOriginalGone.
  ///
  /// In en, this message translates to:
  /// **'{scale} · the original is gone, cannot continue'**
  String jobOriginalGone(String scale);

  /// No description provided for @scaleX4.
  ///
  /// In en, this message translates to:
  /// **'4×'**
  String get scaleX4;

  /// No description provided for @scaleX2.
  ///
  /// In en, this message translates to:
  /// **'2×'**
  String get scaleX2;

  /// No description provided for @scaleFast2.
  ///
  /// In en, this message translates to:
  /// **'Fast 2×'**
  String get scaleFast2;

  /// No description provided for @scaleX1.
  ///
  /// In en, this message translates to:
  /// **'1×'**
  String get scaleX1;

  /// No description provided for @scaleX1Hint.
  ///
  /// In en, this message translates to:
  /// **'1×: same size, only noise and blur are cleaned up.'**
  String get scaleX1Hint;

  /// No description provided for @editorTitle.
  ///
  /// In en, this message translates to:
  /// **'Enhance'**
  String get editorTitle;

  /// No description provided for @sizePx.
  ///
  /// In en, this message translates to:
  /// **'{width} × {height} px'**
  String sizePx(int width, int height);

  /// No description provided for @enhance.
  ///
  /// In en, this message translates to:
  /// **'Enhance'**
  String get enhance;

  /// No description provided for @aiDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'AI adds plausible detail that was not in the original photo.'**
  String get aiDisclaimer;

  /// No description provided for @stageWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting…'**
  String get stageWaiting;

  /// No description provided for @stageReading.
  ///
  /// In en, this message translates to:
  /// **'Reading the photo…'**
  String get stageReading;

  /// No description provided for @stageEnhancing.
  ///
  /// In en, this message translates to:
  /// **'Enhancing {percent}%'**
  String stageEnhancing(int percent);

  /// No description provided for @stageEnhancingEta.
  ///
  /// In en, this message translates to:
  /// **'Enhancing {percent}% · ~{seconds} s left'**
  String stageEnhancingEta(int percent, int seconds);

  /// No description provided for @stageFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get stageFinishing;

  /// No description provided for @stageWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get stageWorking;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @backgroundHint.
  ///
  /// In en, this message translates to:
  /// **'You can leave the app: processing continues in the background.'**
  String get backgroundHint;

  /// No description provided for @pausedByTimeout.
  ///
  /// In en, this message translates to:
  /// **'Paused: Android limits background work. Continue when you are ready.'**
  String get pausedByTimeout;

  /// No description provided for @pausedAt.
  ///
  /// In en, this message translates to:
  /// **'Paused at {percent}%.'**
  String pausedAt(int percent);

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @continueLater.
  ///
  /// In en, this message translates to:
  /// **'Continue later'**
  String get continueLater;

  /// No description provided for @noteSwitchedTo.
  ///
  /// In en, this message translates to:
  /// **'Switched to {backend}'**
  String noteSwitchedTo(String backend);

  /// No description provided for @noteAlphaFlattened.
  ///
  /// In en, this message translates to:
  /// **'Transparent areas become white'**
  String get noteAlphaFlattened;

  /// No description provided for @noteFirstFrame.
  ///
  /// In en, this message translates to:
  /// **'Only the first frame of the animation is enhanced'**
  String get noteFirstFrame;

  /// No description provided for @strength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get strength;

  /// No description provided for @strengthValue.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String strengthValue(int percent);

  /// No description provided for @strengthNeedsOriginal.
  ///
  /// In en, this message translates to:
  /// **'The original photo is gone: only 100% strength can be saved.'**
  String get strengthNeedsOriginal;

  /// No description provided for @saveToGallery.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get saveToGallery;

  /// No description provided for @saveAsFile.
  ///
  /// In en, this message translates to:
  /// **'Save as file…'**
  String get saveAsFile;

  /// No description provided for @savedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Saved to Pictures/Refocal'**
  String get savedToGallery;

  /// No description provided for @savedToFile.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get savedToFile;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailed(String error);

  /// No description provided for @saveAsTitle.
  ///
  /// In en, this message translates to:
  /// **'Save as'**
  String get saveAsTitle;

  /// No description provided for @tryAnotherScale.
  ///
  /// In en, this message translates to:
  /// **'Try another scale'**
  String get tryAnotherScale;

  /// No description provided for @failCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled.'**
  String get failCancelled;

  /// No description provided for @failPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused.'**
  String get failPaused;

  /// No description provided for @failDiskFull.
  ///
  /// In en, this message translates to:
  /// **'Not enough free storage for this size.'**
  String get failDiskFull;

  /// No description provided for @failInvalid.
  ///
  /// In en, this message translates to:
  /// **'This photo could not be read: the format is not supported or the file is damaged.'**
  String get failInvalid;

  /// No description provided for @failLimit.
  ///
  /// In en, this message translates to:
  /// **'This photo is too large (the limit is 30000 px per side and 200 MP).'**
  String get failLimit;

  /// No description provided for @failOom.
  ///
  /// In en, this message translates to:
  /// **'Not enough memory. Try Fast 2×.'**
  String get failOom;

  /// No description provided for @failOther.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({status}).'**
  String failOther(String status);

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @tooLargeTitle.
  ///
  /// In en, this message translates to:
  /// **'This photo is too large for that scale'**
  String get tooLargeTitle;

  /// No description provided for @tooLargeBody.
  ///
  /// In en, this message translates to:
  /// **'Choose a smaller output size.'**
  String get tooLargeBody;

  /// No description provided for @notifEnhancing.
  ///
  /// In en, this message translates to:
  /// **'Enhancing a photo'**
  String get notifEnhancing;

  /// No description provided for @notifReady.
  ///
  /// In en, this message translates to:
  /// **'Photo ready. Tap to open.'**
  String get notifReady;

  /// No description provided for @notifFailed.
  ///
  /// In en, this message translates to:
  /// **'Enhancement failed. Tap to open.'**
  String get notifFailed;

  /// No description provided for @notifTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Paused: Android\'s time limit for background work was reached. Tap to continue.'**
  String get notifTimedOut;

  /// No description provided for @notifChannelName.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get notifChannelName;

  /// No description provided for @notifChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Progress of photos being enhanced'**
  String get notifChannelDescription;

  /// No description provided for @formatJpeg.
  ///
  /// In en, this message translates to:
  /// **'JPEG'**
  String get formatJpeg;

  /// No description provided for @formatPng.
  ///
  /// In en, this message translates to:
  /// **'PNG (lossless)'**
  String get formatPng;

  /// No description provided for @formatWebp.
  ///
  /// In en, this message translates to:
  /// **'WebP'**
  String get formatWebp;

  /// No description provided for @formatWebpLossless.
  ///
  /// In en, this message translates to:
  /// **'WebP (lossless)'**
  String get formatWebpLossless;

  /// No description provided for @formatWebpTooLarge.
  ///
  /// In en, this message translates to:
  /// **'WebP is limited to 50 MP (lossless: 24 MP).'**
  String get formatWebpTooLarge;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSavedPhotos.
  ///
  /// In en, this message translates to:
  /// **'Saved photos'**
  String get settingsSavedPhotos;

  /// No description provided for @settingsFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get settingsFormat;

  /// No description provided for @settingsQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get settingsQuality;

  /// No description provided for @settingsQualityHint.
  ///
  /// In en, this message translates to:
  /// **'JPEG and WebP. Higher is larger and closer to the result on screen.'**
  String get settingsQualityHint;

  /// No description provided for @settingsMetadata.
  ///
  /// In en, this message translates to:
  /// **'Metadata'**
  String get settingsMetadata;

  /// No description provided for @settingsMetadataBody.
  ///
  /// In en, this message translates to:
  /// **'Date, camera and color profile are kept. Camera serial numbers and the maker notes are always removed.'**
  String get settingsMetadataBody;

  /// No description provided for @settingsKeepLocation.
  ///
  /// In en, this message translates to:
  /// **'Keep location'**
  String get settingsKeepLocation;

  /// No description provided for @settingsKeepLocationSub.
  ///
  /// In en, this message translates to:
  /// **'Off: GPS coordinates are removed from the result.'**
  String get settingsKeepLocationSub;

  /// No description provided for @settingsAiMarker.
  ///
  /// In en, this message translates to:
  /// **'Mark as AI-enhanced'**
  String get settingsAiMarker;

  /// No description provided for @settingsAiMarkerSub.
  ///
  /// In en, this message translates to:
  /// **'Writes the IPTC \"trained algorithmic media\" tag, which other apps can show.'**
  String get settingsAiMarkerSub;

  /// No description provided for @markerOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off the AI marker?'**
  String get markerOffTitle;

  /// No description provided for @markerOffBody.
  ///
  /// In en, this message translates to:
  /// **'Enhanced photos contain detail the AI invented. Without the marker, people who see the photo cannot tell it was changed.'**
  String get markerOffBody;

  /// No description provided for @markerKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get markerKeep;

  /// No description provided for @markerTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get markerTurnOff;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// The name of this language, in itself.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;

  /// No description provided for @settingsShowIntro.
  ///
  /// In en, this message translates to:
  /// **'Show the introduction'**
  String get settingsShowIntro;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutAlpha.
  ///
  /// In en, this message translates to:
  /// **'Early alpha. Expect rough edges: Android only, one photo at a time.'**
  String get aboutAlpha;

  /// No description provided for @aboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'All processing happens on this device. Refocal has no accounts, no ads and no telemetry; the network is used only to download optional models when you ask.'**
  String get aboutPrivacy;

  /// No description provided for @aboutAiWarning.
  ///
  /// In en, this message translates to:
  /// **'AI enhancement adds plausible detail that was not in the original photo. Do not use results as evidence of what a scene or person looked like.'**
  String get aboutAiWarning;

  /// No description provided for @aboutCredits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get aboutCredits;

  /// No description provided for @aboutSource.
  ///
  /// In en, this message translates to:
  /// **'Source code (Apache-2.0): {url}'**
  String aboutSource(String url);

  /// No description provided for @aboutLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get aboutLicenses;

  /// No description provided for @compareLabel.
  ///
  /// In en, this message translates to:
  /// **'Before and after comparison'**
  String get compareLabel;

  /// No description provided for @comparePercentOriginal.
  ///
  /// In en, this message translates to:
  /// **'{percent}% original'**
  String comparePercentOriginal(int percent);

  /// No description provided for @tagOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get tagOriginal;

  /// No description provided for @tagEnhanced.
  ///
  /// In en, this message translates to:
  /// **'Enhanced'**
  String get tagEnhanced;

  /// No description provided for @onbSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onbSkip;

  /// No description provided for @onbNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onbNext;

  /// No description provided for @onbStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get onbStart;

  /// No description provided for @onb1Title.
  ///
  /// In en, this message translates to:
  /// **'Everything stays on your phone'**
  String get onb1Title;

  /// No description provided for @onb1Body.
  ///
  /// In en, this message translates to:
  /// **'Photos are enhanced on this device. Nothing is uploaded, there are no accounts and no tracking.'**
  String get onb1Body;

  /// No description provided for @onb2Title.
  ///
  /// In en, this message translates to:
  /// **'AI can change details'**
  String get onb2Title;

  /// No description provided for @onb2Body.
  ///
  /// In en, this message translates to:
  /// **'The model adds detail that looks right but was not in the photo: text, faces and textures may differ from reality. Saved photos are marked as AI-enhanced.'**
  String get onb2Body;

  /// No description provided for @onb3Title.
  ///
  /// In en, this message translates to:
  /// **'Compare before you save'**
  String get onb3Title;

  /// No description provided for @onb3Body.
  ///
  /// In en, this message translates to:
  /// **'Drag the slider over the result to see the original, and lower the strength if the effect is too much. The original is never changed.'**
  String get onb3Body;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'Saved photos appear here with their settings and a small preview.'**
  String get historyEmpty;

  /// No description provided for @historyOff.
  ///
  /// In en, this message translates to:
  /// **'History is off. Turn it on in Settings.'**
  String get historyOff;

  /// No description provided for @historyDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get historyDeleteAll;

  /// No description provided for @historyDeleteAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete the whole history?'**
  String get historyDeleteAllTitle;

  /// No description provided for @historyDeleteAllBody.
  ///
  /// In en, this message translates to:
  /// **'Previews and settings are deleted. Saved photos stay in the gallery.'**
  String get historyDeleteAllBody;

  /// No description provided for @historyDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Some files could not be deleted: {error}'**
  String historyDeleteFailed(String error);

  /// No description provided for @historyEntryGone.
  ///
  /// In en, this message translates to:
  /// **'This entry was deleted.'**
  String get historyEntryGone;

  /// No description provided for @historyScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get historyScale;

  /// No description provided for @historyOriginalSize.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get historyOriginalSize;

  /// No description provided for @historyResultSize.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get historyResultSize;

  /// No description provided for @historyModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get historyModel;

  /// No description provided for @historyBackend.
  ///
  /// In en, this message translates to:
  /// **'Processed on'**
  String get historyBackend;

  /// No description provided for @historyDuration.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get historyDuration;

  /// No description provided for @historySeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s'**
  String historySeconds(int seconds);

  /// No description provided for @historyProcessAgain.
  ///
  /// In en, this message translates to:
  /// **'Process again with other settings'**
  String get historyProcessAgain;

  /// No description provided for @historyOriginalGone.
  ///
  /// In en, this message translates to:
  /// **'The original is no longer on this device: history keeps only the settings and a small preview. Open the photo again to process it.'**
  String get historyOriginalGone;

  /// No description provided for @historyDeleteEntry.
  ///
  /// In en, this message translates to:
  /// **'Delete from history'**
  String get historyDeleteEntry;

  /// No description provided for @historyNotRecorded.
  ///
  /// In en, this message translates to:
  /// **'Saved, but not added to the history: {error}'**
  String historyNotRecorded(String error);

  /// No description provided for @historyOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off the history?'**
  String get historyOffTitle;

  /// No description provided for @historyOffBody.
  ///
  /// In en, this message translates to:
  /// **'The current history is deleted and new photos are not recorded.'**
  String get historyOffBody;

  /// No description provided for @historyOffConfirm.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get historyOffConfirm;

  /// No description provided for @settingsKeepHistory.
  ///
  /// In en, this message translates to:
  /// **'Keep a history'**
  String get settingsKeepHistory;

  /// No description provided for @settingsKeepHistorySub.
  ///
  /// In en, this message translates to:
  /// **'Settings and a small preview of each saved photo, on this device only.'**
  String get settingsKeepHistorySub;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the setting: {error}'**
  String settingsSaveFailed(String error);

  /// No description provided for @presetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get presetsTitle;

  /// No description provided for @presetsBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get presetsBuiltin;

  /// No description provided for @presetsYours.
  ///
  /// In en, this message translates to:
  /// **'Yours'**
  String get presetsYours;

  /// No description provided for @presetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Save one from the editor after enhancing a photo.'**
  String get presetsEmpty;

  /// No description provided for @presetFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get presetFast;

  /// No description provided for @presetQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get presetQuality;

  /// No description provided for @presetRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get presetRename;

  /// No description provided for @presetSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save as preset'**
  String get presetSaveAs;

  /// No description provided for @presetSaved.
  ///
  /// In en, this message translates to:
  /// **'Preset saved'**
  String get presetSaved;

  /// No description provided for @presetSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get presetSave;

  /// No description provided for @presetSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change the presets: {error}'**
  String presetSaveFailed(String error);

  /// No description provided for @presetModelMissing.
  ///
  /// In en, this message translates to:
  /// **'This needs a model that is not installed.'**
  String get presetModelMissing;

  /// No description provided for @presetName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get presetName;

  /// No description provided for @presetNameTooLong.
  ///
  /// In en, this message translates to:
  /// **'At most {max} characters'**
  String presetNameTooLong(int max);

  /// No description provided for @presetStrengthAfter.
  ///
  /// In en, this message translates to:
  /// **'Strength {strength} after enhancing'**
  String presetStrengthAfter(String strength);

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get reportTitle;

  /// No description provided for @reportEntry.
  ///
  /// In en, this message translates to:
  /// **'Report a problem'**
  String get reportEntry;

  /// No description provided for @reportEntrySub.
  ///
  /// In en, this message translates to:
  /// **'View and share the app\'s log'**
  String get reportEntrySub;

  /// No description provided for @reportIntro.
  ///
  /// In en, this message translates to:
  /// **'This log helps find bugs. It contains app events and errors, never your photos, file names or locations. Nothing is sent until you share it; attach it to an issue or an e-mail.'**
  String get reportIntro;

  /// No description provided for @reportEmpty.
  ///
  /// In en, this message translates to:
  /// **'The log is empty.'**
  String get reportEmpty;

  /// No description provided for @reportShare.
  ///
  /// In en, this message translates to:
  /// **'Share the log'**
  String get reportShare;

  /// No description provided for @reportShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share the Refocal log'**
  String get reportShareTitle;

  /// Reason inserted into an error message ({error}).
  ///
  /// In en, this message translates to:
  /// **'a file could not be read or written'**
  String get errorStorage;

  /// Reason inserted into an error message ({error}).
  ///
  /// In en, this message translates to:
  /// **'the system refused the request'**
  String get errorSystem;

  /// Reason inserted into an error message ({error}).
  ///
  /// In en, this message translates to:
  /// **'unexpected error (details are in the log)'**
  String get errorUnexpected;

  /// No description provided for @homeChooseSeveral.
  ///
  /// In en, this message translates to:
  /// **'Process several photos'**
  String get homeChooseSeveral;

  /// No description provided for @homeQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue ({count})'**
  String homeQueue(int count);

  /// No description provided for @pickPartial.
  ///
  /// In en, this message translates to:
  /// **'{failed} of the photos could not be opened: {reason}'**
  String pickPartial(int failed, String reason);

  /// No description provided for @queueTitle.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get queueTitle;

  /// No description provided for @queueEmpty.
  ///
  /// In en, this message translates to:
  /// **'The queue is empty. Choose several photos, or share them to Refocal.'**
  String get queueEmpty;

  /// No description provided for @queueStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get queueStart;

  /// No description provided for @queuePause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get queuePause;

  /// No description provided for @queueClearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get queueClearFinished;

  /// No description provided for @queueShowErrors.
  ///
  /// In en, this message translates to:
  /// **'Only errors'**
  String get queueShowErrors;

  /// No description provided for @queueStateQueued.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get queueStateQueued;

  /// No description provided for @queueStateRunning.
  ///
  /// In en, this message translates to:
  /// **'Processing… {percent}%'**
  String queueStateRunning(int percent);

  /// No description provided for @queueStatePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused at {percent}%'**
  String queueStatePaused(int percent);

  /// No description provided for @queueStateDone.
  ///
  /// In en, this message translates to:
  /// **'Ready, not saved: tap to open'**
  String get queueStateDone;

  /// No description provided for @queueStateSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to the gallery'**
  String get queueStateSaved;

  /// No description provided for @queueStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed: {reason}'**
  String queueStateFailed(String reason);

  /// No description provided for @queueReport.
  ///
  /// In en, this message translates to:
  /// **'Done {done}, failed {failed}'**
  String queueReport(int done, int failed);

  /// No description provided for @queueReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to change the order.'**
  String get queueReorderHint;

  /// No description provided for @queueNotifPosition.
  ///
  /// In en, this message translates to:
  /// **'Photo {n} of {total}'**
  String queueNotifPosition(int n, int total);

  /// No description provided for @queueNotifDone.
  ///
  /// In en, this message translates to:
  /// **'Queue finished: done {done}, failed {failed}'**
  String queueNotifDone(int done, int failed);

  /// No description provided for @batchTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} photos'**
  String batchTitle(int count);

  /// No description provided for @batchPreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get batchPreset;

  /// No description provided for @batchAutosave.
  ///
  /// In en, this message translates to:
  /// **'Save each result to the gallery ({format})'**
  String batchAutosave(String format);

  /// No description provided for @batchAutosaveOff.
  ///
  /// In en, this message translates to:
  /// **'Results wait in the queue until you save them.'**
  String get batchAutosaveOff;

  /// No description provided for @batchAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to the queue'**
  String get batchAdd;

  /// No description provided for @settingsBatchAutosave.
  ///
  /// In en, this message translates to:
  /// **'Batch: save results automatically'**
  String get settingsBatchAutosave;

  /// No description provided for @settingsBatchAutosaveHint.
  ///
  /// In en, this message translates to:
  /// **'Each result of a batch goes to Pictures/Refocal in the default format.'**
  String get settingsBatchAutosaveHint;

  /// No description provided for @queueActionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change the queue: {error}'**
  String queueActionFailed(String error);

  /// No description provided for @storageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageTitle;

  /// No description provided for @settingsStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsStorage;

  /// No description provided for @storageTotal.
  ///
  /// In en, this message translates to:
  /// **'Total: {size}'**
  String storageTotal(String size);

  /// No description provided for @storageMeasureFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not measure the storage: {error}'**
  String storageMeasureFailed(String error);

  /// No description provided for @storageClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get storageClear;

  /// No description provided for @storageClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear: {category}?'**
  String storageClearTitle(String category);

  /// No description provided for @storageClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not clear everything: {error}'**
  String storageClearFailed(String error);

  /// No description provided for @storageNoUndo.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get storageNoUndo;

  /// No description provided for @storageCopies.
  ///
  /// In en, this message translates to:
  /// **'Copies of originals'**
  String get storageCopies;

  /// No description provided for @storageCopiesHint.
  ///
  /// In en, this message translates to:
  /// **'kept to process a history entry again; copies a paused job or the queue needs are not counted'**
  String get storageCopiesHint;

  /// No description provided for @storageCopiesClear.
  ///
  /// In en, this message translates to:
  /// **'History entries can no longer be processed again. Paused jobs and the queue keep their copies.'**
  String get storageCopiesClear;

  /// No description provided for @storageUnfinished.
  ///
  /// In en, this message translates to:
  /// **'Unfinished jobs'**
  String get storageUnfinished;

  /// No description provided for @storageUnfinishedHint.
  ///
  /// In en, this message translates to:
  /// **'paused or unsaved results of the editor'**
  String get storageUnfinishedHint;

  /// No description provided for @storageUnfinishedClear.
  ///
  /// In en, this message translates to:
  /// **'Paused and unsaved results are deleted. The queue is not affected.'**
  String get storageUnfinishedClear;

  /// No description provided for @storageHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'previews of saved results'**
  String get storageHistoryHint;

  /// No description provided for @storageHistoryClear.
  ///
  /// In en, this message translates to:
  /// **'The whole history is deleted. Saved photos stay in the gallery.'**
  String get storageHistoryClear;

  /// No description provided for @storageCache.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get storageCache;

  /// No description provided for @storageCacheHint.
  ///
  /// In en, this message translates to:
  /// **'temporary copies for saving and sharing'**
  String get storageCacheHint;

  /// No description provided for @storageLogs.
  ///
  /// In en, this message translates to:
  /// **'Log'**
  String get storageLogs;

  /// No description provided for @storageLogsHint.
  ///
  /// In en, this message translates to:
  /// **'for bug reports, never sent by itself'**
  String get storageLogsHint;

  /// No description provided for @storageModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get storageModels;

  /// No description provided for @storageModelsHint.
  ///
  /// In en, this message translates to:
  /// **'built into the app'**
  String get storageModelsHint;

  /// No description provided for @sizeKb.
  ///
  /// In en, this message translates to:
  /// **'{n} KB'**
  String sizeKb(String n);

  /// No description provided for @sizeMb.
  ///
  /// In en, this message translates to:
  /// **'{n} MB'**
  String sizeMb(String n);

  /// No description provided for @sizeGb.
  ///
  /// In en, this message translates to:
  /// **'{n} GB'**
  String sizeGb(String n);

  /// No description provided for @noteThermalWait.
  ///
  /// In en, this message translates to:
  /// **'The phone is hot: waiting for it to cool down.'**
  String get noteThermalWait;

  /// No description provided for @noteThermalThrottle.
  ///
  /// In en, this message translates to:
  /// **'The phone is warm: processing more slowly.'**
  String get noteThermalThrottle;

  /// No description provided for @compareShowOriginal.
  ///
  /// In en, this message translates to:
  /// **'Show original'**
  String get compareShowOriginal;

  /// No description provided for @compareShowResult.
  ///
  /// In en, this message translates to:
  /// **'Show result'**
  String get compareShowResult;

  /// No description provided for @resultAlt.
  ///
  /// In en, this message translates to:
  /// **'Result, {width}×{height}, enhanced by AI'**
  String resultAlt(int width, int height);

  /// No description provided for @modelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get modelsTitle;

  /// No description provided for @settingsModels.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get settingsModels;

  /// No description provided for @modelsBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built in: Real-ESRGAN general (denoise 0.5)'**
  String get modelsBuiltIn;

  /// No description provided for @modelsBuiltInHint.
  ///
  /// In en, this message translates to:
  /// **'Always available, works offline.'**
  String get modelsBuiltInHint;

  /// No description provided for @modelsCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for models'**
  String get modelsCheck;

  /// No description provided for @modelsNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Check for models\" to see what can be downloaded.'**
  String get modelsNotChecked;

  /// No description provided for @modelsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Refocal connects to the internet only when you check for models or download one. Files are verified with a signature and a checksum before use.'**
  String get modelsPrivacy;

  /// No description provided for @modelsNonCommercial.
  ///
  /// In en, this message translates to:
  /// **'non-commercial'**
  String get modelsNonCommercial;

  /// No description provided for @modelsInstalled.
  ///
  /// In en, this message translates to:
  /// **'installed'**
  String get modelsInstalled;

  /// No description provided for @modelsUpdate.
  ///
  /// In en, this message translates to:
  /// **'installed {installedVersion}, available {availableVersion}'**
  String modelsUpdate(String installedVersion, String availableVersion);

  /// No description provided for @modelsUpdateAction.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get modelsUpdateAction;

  /// No description provided for @modelsDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get modelsDownload;

  /// No description provided for @modelsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get modelsDelete;

  /// No description provided for @modelsDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String modelsDownloading(int percent);

  /// No description provided for @modelsErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the model server. Check the connection and try again.'**
  String get modelsErrorNetwork;

  /// No description provided for @modelsErrorIntegrity.
  ///
  /// In en, this message translates to:
  /// **'The download did not pass verification and was not used.'**
  String get modelsErrorIntegrity;

  /// No description provided for @modelsErrorRollback.
  ///
  /// In en, this message translates to:
  /// **'The server offered an older model list; it was not used.'**
  String get modelsErrorRollback;

  /// No description provided for @modelsLicenseTitle.
  ///
  /// In en, this message translates to:
  /// **'License: {name}'**
  String modelsLicenseTitle(String name);

  /// No description provided for @modelsLicenseIntro.
  ///
  /// In en, this message translates to:
  /// **'This model is not free for every use. Read its license; download it only if you accept it.'**
  String get modelsLicenseIntro;

  /// No description provided for @modelsLicenseAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept and download'**
  String get modelsLicenseAccept;

  /// No description provided for @denoise.
  ///
  /// In en, this message translates to:
  /// **'Denoise'**
  String get denoise;

  /// No description provided for @denoiseNone.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get denoiseNone;

  /// No description provided for @denoiseStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get denoiseStandard;

  /// No description provided for @denoiseStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get denoiseStrong;

  /// No description provided for @presetPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get presetPortrait;

  /// No description provided for @presetOldPhoto.
  ///
  /// In en, this message translates to:
  /// **'Old photo'**
  String get presetOldPhoto;

  /// No description provided for @recipeFaces.
  ///
  /// In en, this message translates to:
  /// **'faces {percent}%'**
  String recipeFaces(int percent);

  /// No description provided for @faces.
  ///
  /// In en, this message translates to:
  /// **'Restore faces'**
  String get faces;

  /// No description provided for @facesHint.
  ///
  /// In en, this message translates to:
  /// **'Uses the face model on each face, then blends it with the enhanced photo.'**
  String get facesHint;

  /// No description provided for @facesStrength.
  ///
  /// In en, this message translates to:
  /// **'Face strength'**
  String get facesStrength;

  /// No description provided for @facesNeedPack.
  ///
  /// In en, this message translates to:
  /// **'Face restoration needs the face model (about 177 MB, non-commercial license).'**
  String get facesNeedPack;

  /// No description provided for @facesGetPack.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get facesGetPack;

  /// No description provided for @facesNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'About face restoration'**
  String get facesNoticeTitle;

  /// No description provided for @facesNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'The face model redraws faces from what it has learned. Faces can look sharper but also different from the real person, especially in old or small photos. Refocal blends the result with the original (50% by default) and marks saved photos as AI-edited.'**
  String get facesNoticeBody;

  /// No description provided for @facesNoticeOk.
  ///
  /// In en, this message translates to:
  /// **'I understand'**
  String get facesNoticeOk;

  /// No description provided for @stageFaces.
  ///
  /// In en, this message translates to:
  /// **'Restoring faces… {percent}%'**
  String stageFaces(int percent);

  /// No description provided for @noteFacesFound.
  ///
  /// In en, this message translates to:
  /// **'Faces found: {count}'**
  String noteFacesFound(int count);

  /// No description provided for @regionAll.
  ///
  /// In en, this message translates to:
  /// **'Whole photo'**
  String get regionAll;

  /// No description provided for @regionFaces.
  ///
  /// In en, this message translates to:
  /// **'Only faces'**
  String get regionFaces;

  /// No description provided for @tierTitle.
  ///
  /// In en, this message translates to:
  /// **'Device class'**
  String get tierTitle;

  /// No description provided for @tierAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get tierAuto;

  /// No description provided for @tierMeasured.
  ///
  /// In en, this message translates to:
  /// **'{tier} by the speed test: {backend}, {ms} ms per tile'**
  String tierMeasured(String tier, String backend, int ms);

  /// No description provided for @tierGpu.
  ///
  /// In en, this message translates to:
  /// **'graphics processor'**
  String get tierGpu;

  /// No description provided for @tierCpu.
  ///
  /// In en, this message translates to:
  /// **'processor'**
  String get tierCpu;

  /// No description provided for @tierUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not measured: T0, the safe one'**
  String get tierUnknown;

  /// No description provided for @tierMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring…'**
  String get tierMeasuring;

  /// No description provided for @autoChip.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get autoChip;

  /// No description provided for @autoAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Looking at the photo…'**
  String get autoAnalyzing;

  /// No description provided for @autoFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto is unavailable: the photo could not be analysed'**
  String get autoFailed;

  /// No description provided for @autoFaces.
  ///
  /// In en, this message translates to:
  /// **'faces: {count}'**
  String autoFaces(int count);

  /// No description provided for @autoFacesNotRestored.
  ///
  /// In en, this message translates to:
  /// **'not restored on this device'**
  String get autoFacesNotRestored;

  /// No description provided for @autoFacesNeedPack.
  ///
  /// In en, this message translates to:
  /// **'face model not installed'**
  String get autoFacesNeedPack;

  /// No description provided for @autoFacesOnly.
  ///
  /// In en, this message translates to:
  /// **'only faces'**
  String get autoFacesOnly;

  /// No description provided for @autoDenoiseNone.
  ///
  /// In en, this message translates to:
  /// **'no denoise'**
  String get autoDenoiseNone;

  /// No description provided for @autoDenoiseStandard.
  ///
  /// In en, this message translates to:
  /// **'denoise medium'**
  String get autoDenoiseStandard;

  /// No description provided for @autoDenoiseStrong.
  ///
  /// In en, this message translates to:
  /// **'denoise strong'**
  String get autoDenoiseStrong;

  /// No description provided for @noteTileSmaller.
  ///
  /// In en, this message translates to:
  /// **'Low on memory: processing in smaller pieces, slower'**
  String get noteTileSmaller;

  /// No description provided for @noteFaceSkipped.
  ///
  /// In en, this message translates to:
  /// **'Reduced quality: face {number} could not be restored'**
  String noteFaceSkipped(int number);

  /// No description provided for @noteFacesSkipped.
  ///
  /// In en, this message translates to:
  /// **'Reduced quality: faces could not be restored'**
  String get noteFacesSkipped;

  /// No description provided for @oomTitle.
  ///
  /// In en, this message translates to:
  /// **'Not enough memory'**
  String get oomTitle;

  /// No description provided for @oomBody.
  ///
  /// In en, this message translates to:
  /// **'Not enough memory for {scale}. Process at a smaller size?'**
  String oomBody(String scale);

  /// No description provided for @modelsImport.
  ///
  /// In en, this message translates to:
  /// **'Import a .rfpack file'**
  String get modelsImport;

  /// No description provided for @modelsImported.
  ///
  /// In en, this message translates to:
  /// **'Installed: {name}'**
  String modelsImported(String name);

  /// No description provided for @modelsErrorNotAPack.
  ///
  /// In en, this message translates to:
  /// **'Not a Refocal model pack, or the file is damaged'**
  String get modelsErrorNotAPack;

  /// No description provided for @modelsErrorStorage.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read'**
  String get modelsErrorStorage;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
