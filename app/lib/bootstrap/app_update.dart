import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';
import 'package:refocal_platform/refocal_platform.dart';

import 'app_log.dart';
import 'engine.dart';
import 'foreground.dart';
import 'https_fetch.dart';
import 'models.dart' show ModelVerifier, NativeModelVerifier;
import 'settings.dart';

/// The build flavor (`flutter build --flavor` defines it). Only `github` updates itself
/// (ADR-0027); in the others everything here stays idle and makes no network request.
const appFlavor = String.fromEnvironment('FLUTTER_APP_FLAVOR');
const selfUpdate = appFlavor == 'github';

/// Public keys of app-update.json: U signs in CI (app-update.yml), V is kept offline for
/// rotation. The key lines of tools/release/keys/{U,V}.pub (test/app_update_test.dart compares).
const appUpdateKeys = [
  'RWSeguUwFWmB9vA5dHXbNdGT334F43VEzdHKNKjMY1C5UeL4/9AAjR13',
  'RWT2XHRCpK93z/OdnuGplua+3g1wAoKTnmvGu2HN4C3sYrLWnVY8+NWC',
];

/// Where the signed feed is published: the `app-latest` release, rewritten on each release.
const appUpdateUrls = ['https://github.com/sleepe229/refocal/releases/download/app-latest'];
const appUpdateFile = 'app-update.json';

/// FR-UPD-001: the automatic check runs at most this often.
const appUpdateEvery = Duration(days: 7);

const _maxFeedBytes = 64 << 10, _maxSignatureBytes = 1 << 10;

/// The largest APK accepted (NFR-SIZE-001 is 30 MB; room for growth).
const _maxApkBytes = 200 << 20;

/// One release in app-update.json.
class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.urls,
    required this.size,
    required this.sha256,
    required this.minSdk,
    required this.notes,
  });

  final int versionCode;
  final String versionName;

  /// Mirrors of the `github` APK, all HTTPS.
  final List<String> urls;
  final int size;
  final String sha256;
  final int minSdk;

  /// "What's new" by language code ("en" always present).
  final Map<String, String> notes;

  String notesFor(String languageCode) => notes[languageCode] ?? notes['en']!;

  /// Validated once, here: anything else is a [FormatException].
  factory AppRelease.fromJson(Object? j) {
    if (j is! Map<String, Object?>) throw const FormatException('release');
    T field<T>(String k) => switch (j[k]) {
      final T v => v,
      _ => throw FormatException('release.$k'),
    };
    final urls = [for (final u in field<List<Object?>>('urls')) u is String ? u : ''];
    if (urls.isEmpty || urls.any((u) => Uri.tryParse(u)?.scheme != 'https')) {
      throw const FormatException('release.urls');
    }
    final sha = field<String>('sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) throw const FormatException('release.sha256');
    final notes = {
      for (final MapEntry(:key, :value) in field<Map<String, Object?>>('notes').entries)
        if (value is String) key: value,
    };
    if (!notes.containsKey('en')) throw const FormatException('release.notes');
    final r = AppRelease(
      versionCode: field<int>('version_code'),
      versionName: field<String>('version_name'),
      urls: urls,
      size: field<int>('size'),
      sha256: sha,
      minSdk: field<int>('min_sdk'),
      notes: notes,
    );
    if (r.versionCode <= 0 || r.size <= 0 || r.size > _maxApkBytes) {
      throw const FormatException('release.size');
    }
    return r;
  }
}

/// app-update.json: the latest stable release and, if newer, the latest pre-release.
class UpdateFeed {
  const UpdateFeed({this.stable, this.beta});
  final AppRelease? stable, beta;

  factory UpdateFeed.parse(String text) {
    final j = jsonDecode(text);
    if (j is! Map<String, Object?> || j['schema'] != 1) throw const FormatException('schema');
    AppRelease? opt(String k) => j[k] == null ? null : AppRelease.fromJson(j[k]);
    return UpdateFeed(stable: opt('stable'), beta: opt('beta'));
  }

  /// The release to offer on [channelBeta], if it is newer than [installed] and runs on
  /// [sdkInt].
  AppRelease? newer(int installed, int sdkInt, {required bool channelBeta}) {
    final candidates = [?stable, if (channelBeta) ?beta];
    AppRelease? best;
    for (final r in candidates) {
      if (r.versionCode > installed &&
          r.minSdk <= sdkInt &&
          (best == null || r.versionCode > best.versionCode)) {
        best = r;
      }
    }
    return best;
  }

  /// The release with [versionCode], for its "What's new".
  AppRelease? byCode(int versionCode) =>
      [?stable, ?beta].where((r) => r.versionCode == versionCode).firstOrNull;
}

/// Fetches and verifies the feed and the APK (ADR-0027). Files live in [dir]: the last
/// verified feed and at most one verified APK.
class AppUpdater {
  AppUpdater({
    required this.dir,
    required this.verifier,
    HttpsFetcher? fetcher,
    this.base = appUpdateUrls,
    this.keys = appUpdateKeys,
  }) : _fetcher = fetcher ?? HttpsFetcher();

  final String dir;
  final ModelVerifier verifier;
  final List<String> base, keys;
  final HttpsFetcher _fetcher;

  File get _feed => File('$dir/$appUpdateFile');
  File apkOf(AppRelease r) => File('$dir/refocal-${r.versionCode}.apk');

  /// The feed verified last time, if any.
  Future<UpdateFeed?> cached() async {
    try {
      return UpdateFeed.parse(await _feed.readAsString());
    } on Object {
      return null;
    }
  }

  /// Downloads app-update.json and its signature, checks the signature before parsing, and
  /// keeps it. Throws on any failure.
  Future<UpdateFeed> fetch() async {
    await Directory(dir).create(recursive: true);
    final json = File('$dir/$appUpdateFile.new'), sig = File('$dir/$appUpdateFile.minisig');
    try {
      await _any([for (final u in base) '$u/$appUpdateFile'], json, _maxFeedBytes);
      await _any([for (final u in base) '$u/$appUpdateFile.minisig'], sig, _maxSignatureBytes);
      verifier.signature(json.path, sig.path, keys);
      final feed = UpdateFeed.parse(await json.readAsString());
      await json.rename(_feed.path);
      return feed;
    } finally {
      for (final f in [json, sig]) {
        if (await f.exists()) await f.delete();
      }
    }
  }

  /// The APK of [r] in [dir], downloaded (resumed) unless already there, size and SHA-256
  /// checked. Older APKs are removed.
  Future<File> download(
    AppRelease r, {
    void Function(double)? onProgress,
    bool Function()? cancel,
  }) async {
    await Directory(dir).create(recursive: true);
    final apk = apkOf(r);
    await for (final f in Directory(dir).list()) {
      if (f is File && f.path.endsWith('.apk') && f.path != apk.path) await f.delete();
    }
    if (await _ok(apk, r)) return apk;
    final part = File('${apk.path}.part');
    Object? last;
    for (final url in r.urls) {
      try {
        await _fetcher.fetch(
          url,
          part,
          resume: true,
          expected: r.size,
          onBytes: (n) => onProgress?.call(n / r.size),
          cancel: cancel,
        );
        if (await _ok(part, r)) return await part.rename(apk.path);
        await part.delete(); // a bad mirror: start over from the next one
      } on DownloadCancelled {
        rethrow;
      } on Exception catch (e) {
        AppLog.warn('app update mirror failed: ${Uri.parse(url).host}');
        last = e;
      }
    }
    throw last ?? const FileSystemException('app update: no mirror had the file');
  }

  /// The verified APK of [r], if it is already downloaded.
  Future<File?> downloaded(AppRelease r) async => await _ok(apkOf(r), r) ? apkOf(r) : null;

  Future<bool> _ok(File f, AppRelease r) async {
    if (!await f.exists() || await f.length() != r.size) return false;
    try {
      await verifier.file(f.path, r.sha256);
      return true;
    } on EnhException {
      return false;
    }
  }

  Future<void> _any(List<String> urls, File dst, int maxBytes) async {
    Object? last;
    for (final url in urls) {
      try {
        if (await dst.exists()) await dst.delete();
        await _fetcher.fetch(url, dst, resume: false, expected: maxBytes);
        return;
      } on Exception catch (e) {
        last = e;
      }
    }
    throw last ?? const FileSystemException('app update: no mirror');
  }
}

/// What the update card shows.
sealed class AppUpdateState {
  const AppUpdateState();
}

/// Nothing to offer (or a build without self-update).
class UpdateNone extends AppUpdateState {
  const UpdateNone({this.checking = false});

  /// "Check now" is running.
  final bool checking;
}

/// Found on a metered network: downloaded only when the user asks.
class UpdateFound extends AppUpdateState {
  const UpdateFound(this.release);
  final AppRelease release;
}

class UpdateDownloading extends AppUpdateState {
  const UpdateDownloading(this.release, this.fraction);
  final AppRelease release;
  final double fraction;
}

/// Downloaded and verified: "Update".
class UpdateReady extends AppUpdateState {
  const UpdateReady(this.release, this.apk, {this.waiting = false, this.needsPermission = false});
  final AppRelease release;
  final String apk;

  /// The user tapped "Update" while something processes: it installs when that ends.
  final bool waiting;

  /// Android asked the user to allow installs from Refocal first.
  final bool needsPermission;
}

class UpdateInstalling extends AppUpdateState {
  const UpdateInstalling(this.release);
  final AppRelease release;
}

/// The last attempt failed; the next check (or a tap) tries again.
class UpdateFailed extends AppUpdateState {
  const UpdateFailed(this.release);
  final AppRelease? release;
}

/// Platform side of the updater, so tests can stand in for Android.
abstract interface class UpdatePlatform {
  Future<int> installedVersionCode();
  Future<int> sdkInt();
  Future<bool> unmetered();
  Future<bool> canInstall();
  Future<void> openInstallSettings();
  Future<String> install(String apkPath);
}

class AndroidUpdatePlatform implements UpdatePlatform {
  AndroidUpdatePlatform([AppUpdateApi? api]) : _api = api ?? AppUpdateApi();
  final AppUpdateApi _api;

  @override
  Future<int> installedVersionCode() => _api.installedVersionCode();
  @override
  Future<int> sdkInt() => _api.sdkInt();
  @override
  Future<bool> unmetered() => _api.unmetered();
  @override
  Future<bool> canInstall() => _api.canInstall();
  @override
  Future<void> openInstallSettings() => _api.openInstallSettings();
  @override
  Future<String> install(String apkPath) => _api.install(apkPath);
}

final updatePlatformProvider = Provider<UpdatePlatform>((_) => AndroidUpdatePlatform());

/// Emulator tests of the whole update (tools/emulator, SCENARIO=update; profile builds only,
/// ignored in release): a feed at this base, served with a self-signed certificate and signed
/// with this key.
const _testBase = String.fromEnvironment('REFOCAL_UPDATE_TEST_BASE');
const _testKey = String.fromEnvironment('REFOCAL_UPDATE_TEST_KEY');

final appUpdaterProvider = FutureProvider<AppUpdater>((ref) async {
  final engine = await ref.watch(engineProvider.future);
  final dir = '${engine.dirs.support}/update', verifier = NativeModelVerifier(engine.native);
  if (!kReleaseMode && _testBase.isNotEmpty) {
    final host = Uri.parse(_testBase).host;
    return AppUpdater(
      dir: dir,
      verifier: verifier,
      base: const [_testBase],
      keys: const [_testKey],
      fetcher: HttpsFetcher(HttpClient()..badCertificateCallback = (_, h, _) => h == host),
    );
  }
  return AppUpdater(dir: dir, verifier: verifier);
});

/// The app update (FR-UPD-001…005, ADR-0027). With the update check on (FR-SET-005), it looks
/// at most once a week on an unmetered network and downloads there in the background; on a
/// metered one it only says that an update exists. Installing is the user's tap.
class AppUpdateController extends Notifier<AppUpdateState> {
  @override
  AppUpdateState build() {
    if (selfUpdate) unawaited(_resume());
    return const UpdateNone();
  }

  bool _busy = false;

  UpdatePlatform get _platform => ref.read(updatePlatformProvider);

  /// At start: a verified APK from an earlier run is offered at once; then the weekly check.
  Future<void> _resume() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      final updater = await ref.read(appUpdaterProvider.future);
      final installed = await _platform.installedVersionCode();
      final sdk = await _platform.sdkInt();
      final feed = await updater.cached();
      final r = feed?.newer(installed, sdk, channelBeta: settings.betaUpdates);
      final apk = r == null ? null : await updater.downloaded(r);
      if (r != null && apk != null) state = UpdateReady(r, apk.path);
      await autoCheck();
    } on PlatformException catch (e) {
      AppLog.warn('app update: ${e.code}');
    }
  }

  /// The weekly background check (opt-in, unmetered only).
  Future<void> autoCheck() async {
    final settings = await ref.read(settingsProvider.future);
    if (!settings.packUpdateCheck || state is! UpdateNone && state is! UpdateFailed) return;
    final last = settings.appUpdateCheckedAt;
    if (last != null && DateTime.now().difference(last) < appUpdateEvery) return;
    if (!await _platform.unmetered()) return;
    await _check(download: true);
  }

  /// "Check now" in About: a user action, so any network will do.
  Future<void> checkNow() => _check(download: true, user: true);

  /// Downloads the update found on a metered network (the user asked).
  Future<void> download() async {
    if (state case UpdateFound(:final release) || UpdateFailed(:final release?)) {
      await _download(release);
    }
  }

  Future<void> _check({required bool download, bool user = false}) async {
    if (_busy) return;
    _busy = true;
    if (user) state = const UpdateNone(checking: true);
    try {
      final settings = await ref.read(settingsProvider.future);
      final updater = await ref.read(appUpdaterProvider.future);
      final feed = await updater.fetch();
      await ref
          .read(settingsProvider.notifier)
          .change((s) => s.copyWith(appUpdateCheckedAt: DateTime.now));
      final r = feed.newer(
        await _platform.installedVersionCode(),
        await _platform.sdkInt(),
        channelBeta: settings.betaUpdates,
      );
      AppLog.info('app update check: ${r?.versionName ?? 'up to date'}');
      if (r == null) {
        state = const UpdateNone();
      } else if (await updater.downloaded(r) case final apk?) {
        state = UpdateReady(r, apk.path);
      } else if (download && (user || await _platform.unmetered())) {
        _busy = false;
        await _download(r);
      } else {
        state = UpdateFound(r);
      }
    } on Exception catch (e) {
      AppLog.warn('app update check failed: ${e.runtimeType}');
      state = user ? const UpdateFailed(null) : const UpdateNone();
    } finally {
      _busy = false;
    }
  }

  Future<void> _download(AppRelease r) async {
    if (_busy) return;
    _busy = true;
    state = UpdateDownloading(r, 0);
    try {
      final updater = await ref.read(appUpdaterProvider.future);
      final apk = await updater.download(r, onProgress: (f) => state = UpdateDownloading(r, f));
      state = UpdateReady(r, apk.path);
    } on Exception catch (e) {
      AppLog.warn('app update download failed: ${e.runtimeType}');
      state = UpdateFailed(r);
    } finally {
      _busy = false;
    }
  }

  /// "Update": waits until nothing processes (FR-UPD-004), asks Android for the install
  /// permission if it is missing, then installs. The app is replaced on success.
  Future<void> install() async {
    final ready = state;
    if (ready is! UpdateReady) return;
    final work = ref.read(foregroundWorkProvider);
    if (work.busy) {
      state = UpdateReady(ready.release, ready.apk, waiting: true);
      await work.idle();
    }
    if (!await _platform.canInstall()) {
      state = UpdateReady(ready.release, ready.apk, needsPermission: true);
      await _platform.openInstallSettings();
      return; // the user comes back and taps again
    }
    state = UpdateInstalling(ready.release);
    try {
      // "pending_user": Android shows its own dialog; tapping again is possible if dismissed.
      await _platform.install(ready.apk);
      state = UpdateReady(ready.release, ready.apk);
    } on PlatformException catch (e) {
      AppLog.warn('app update install failed: ${e.code}');
      state = UpdateFailed(ready.release);
    }
  }

  /// The "What's new" of the version now installed, once after an update; null otherwise.
  /// The first run of the app only records the version.
  Future<AppRelease?> takeWhatsNew() async {
    if (!selfUpdate) return null;
    try {
      final installed = await _platform.installedVersionCode();
      final settings = await ref.read(settingsProvider.future);
      final seen = settings.seenVersionCode;
      if (seen == installed) return null;
      await ref
          .read(settingsProvider.notifier)
          .change((s) => s.copyWith(seenVersionCode: () => installed));
      if (seen == null || seen > installed) return null;
      return (await (await ref.read(appUpdaterProvider.future)).cached())?.byCode(installed);
    } on PlatformException {
      return null;
    }
  }
}

final appUpdateProvider = NotifierProvider<AppUpdateController, AppUpdateState>(
  AppUpdateController.new,
);
