import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:refocal_ffi/refocal_ffi.dart';

import 'app_log.dart';
import 'database.dart';
import 'engine.dart';
import 'settings.dart';

/// Public keys of the model manifest (ADR-0011): A signs (release CI), B is kept offline for
/// rotation. The key lines of tools/models/keys/{A,B}.pub (test/models_test.dart compares).
const manifestKeys = [
  'RWTXEHeX54yoy8NfynPQ217mgMdvPM5Ug00TGXwiBywElKW+U0x7O5/6',
  'RWQgSPlu4nMko2oEi3BM8sVq1NS0d9yLy4MEtKQ3uTyDwrUPcZuhUWdA',
];

/// Where the signed manifest is published (GitHub Releases only for now; the pack files list
/// their own mirrors).
const manifestUrls = ['https://github.com/sleepe229/refocal/releases/download/models'];

/// File hashes and manifest signatures (ADR-0021: the native core in the app).
abstract interface class ModelVerifier {
  /// Throws [EnhException] unless [path] has [sha256Hex].
  Future<void> file(String path, String sha256Hex);

  /// Throws [EnhException] unless [sigPath] signs [msgPath] with one of [keys].
  void signature(String msgPath, String sigPath, List<String> keys);
}

/// Entries of an offline pack (.rfpack, SEC-INP-005: the core checks the archive).
abstract interface class PackUnpacker {
  /// Unpacks [entry] of [rfpack] to [dst]. Throws [EnhException] (invalid, limit, io).
  Future<void> extract(String rfpack, String entry, String dst, int maxBytes);
}

class NativePackUnpacker implements PackUnpacker {
  const NativePackUnpacker(this.native);
  final RefocalNative native;

  @override
  Future<void> extract(String rfpack, String entry, String dst, int maxBytes) =>
      native.rfpackExtract(rfpack, entry, dst, maxBytes);
}

class NativeModelVerifier implements ModelVerifier {
  const NativeModelVerifier(this.native);
  final RefocalNative native;

  @override
  Future<void> file(String path, String sha256Hex) => native.verifyFile(path, sha256Hex);

  @override
  void signature(String msgPath, String sigPath, List<String> keys) =>
      native.verifyMinisign(msgPath, sigPath, keys);
}

/// A pack download in progress (bytes of all its files).
class PackProgress {
  const PackProgress(this.done, this.total);
  final int done, total;
  double get fraction => total == 0 ? 0 : done / total;
}

/// What a download or install failed with, for the user (the details go to the log).
class ModelError implements Exception {
  const ModelError(this.kind, [this.cause]);
  final ModelErrorKind kind;
  final Object? cause;

  @override
  String toString() => 'ModelError(${kind.name}${cause == null ? '' : ': $cause'})';
}

enum ModelErrorKind {
  /// No mirror answered (offline, or the repository is not public yet).
  network,

  /// A file or the manifest did not match its hash or signature: not used.
  integrity,

  /// An older manifest than the one already accepted, or an offline pack older than the
  /// installed version (ADR-0011).
  rollback,

  /// An offline pack that is not one (a damaged or foreign file), or has no files for this
  /// device.
  notAPack,

  /// Not enough free space.
  storage,
}

/// The model manager (ADR-0011, 04 §6): fetches and verifies the signed manifest, downloads
/// pack files with HTTP Range resume across mirrors, checks each against its SHA-256 and moves
/// the pack into place atomically. Network only on the user's action (ADR-0020).
class ModelManager {
  ModelManager({
    required this.repo,
    required this.verifier,
    required this.unpacker,
    required this.supportDir,
    required this.tmpDir,
    HttpClient? http,
    ModelPlatform? platform,
    this.manifestBase = manifestUrls,
  }) : platform = platform ?? ModelPlatform.current(),
       _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 20));

  final ModelRepository repo;
  final ModelVerifier verifier;
  final PackUnpacker unpacker;
  final String supportDir, tmpDir;

  /// The manifest's location (one URL per mirror).
  final List<String> manifestBase;
  final ModelPlatform platform;
  final HttpClient _http;

  String get modelsDir => '$supportDir/models';
  String dirOf(String packId) => '$modelsDir/$packId';

  /// Downloads the manifest and its signature, verifies the signature before parsing, and
  /// stores it (rollback check). Throws [ModelError].
  Future<Manifest> refresh() async {
    await Directory(tmpDir).create(recursive: true);
    final json = File('$tmpDir/manifest.json'), sig = File('$tmpDir/manifest.json.minisig');
    try {
      await _fetchAny([for (final u in manifestBase) '$u/manifest.json'], json, _maxManifestBytes);
      await _fetchAny(
        [for (final u in manifestBase) '$u/manifest.json.minisig'],
        sig,
        _maxSignatureBytes,
      );
      try {
        verifier.signature(json.path, sig.path, manifestKeys);
      } on EnhException catch (e) {
        AppLog.warn('manifest signature: ${e.status.name}');
        throw const ModelError(ModelErrorKind.integrity);
      }
      final m = await repo.accept(await json.readAsString());
      AppLog.info('manifest serial ${m.serial}, ${m.packs.length} packs');
      return m;
    } on ManifestRollback catch (e) {
      AppLog.warn('manifest rollback: $e');
      throw ModelError(ModelErrorKind.rollback, e);
    } on FormatException catch (e) {
      AppLog.warn('manifest format: ${e.message}');
      throw ModelError(ModelErrorKind.integrity, e);
    } finally {
      for (final f in [json, sig]) {
        if (await f.exists()) await f.delete();
      }
    }
  }

  /// The files of [pack] this device runs (Android: ncnn).
  List<PackFile> filesFor(PackInfo pack) => pack.filesFor(platform.name, platform.backend);

  /// Downloads and installs [pack]. A license that needs acceptance must have a consent
  /// already ([ModelRepository.recordConsent]). Partial files stay for resuming; [cancel]
  /// stops at the next chunk. Throws [ModelError].
  Future<void> install(
    PackInfo pack, {
    void Function(PackProgress)? onProgress,
    bool Function()? cancel,
  }) async {
    if (pack.license.requiresAcceptance && !await repo.hasConsent(pack)) {
      throw StateError('${pack.id}: license not accepted');
    }
    final files = filesFor(pack);
    if (files.isEmpty) throw StateError('${pack.id} has no files for ${platform.name}');
    final staging = Directory('$modelsDir/.${pack.id}.partial');
    await staging.create(recursive: true);
    final total = files.fold(0, (n, f) => n + f.size);
    var before = 0;
    for (final f in files) {
      final dst = File('${staging.path}/${f.path}');
      if (!await _verified(dst, f)) {
        final part = File('${dst.path}.part');
        await _download(f, part, (n) => onProgress?.call(PackProgress(before + n, total)), cancel);
        if (!await _verified(part, f)) {
          await part.delete();
          throw const ModelError(ModelErrorKind.integrity);
        }
        await part.rename(dst.path);
      }
      before += f.size;
      onProgress?.call(PackProgress(before, total));
    }
    await _activate(pack, files, staging);
  }

  /// Opens an offline pack (.rfpack, ADR-0011, 04 §6): the core checks the archive and
  /// unpacks only its manifest and signature; the signature is verified before the manifest
  /// is parsed, as for the network one. The pack's own manifest has exactly one pack; it never
  /// replaces the accepted network manifest. Throws [ModelError].
  Future<OfflinePack> openOffline(String rfpack) async {
    final dir = Directory('$tmpDir/rfpack');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final json = '${dir.path}/manifest.json', sig = '$json.minisig';
    final license = '${dir.path}/license.txt';
    try {
      await _unpack(rfpack, 'manifest.json', json, _maxManifestBytes);
      await _unpack(rfpack, 'manifest.json.minisig', sig, _maxSignatureBytes);
      try {
        verifier.signature(json, sig, manifestKeys);
      } on EnhException catch (e) {
        AppLog.warn('rfpack signature: ${e.status.name}');
        throw const ModelError(ModelErrorKind.integrity);
      }
      final Manifest m;
      try {
        m = Manifest.parse(await File(json).readAsString());
      } on FormatException catch (e) {
        AppLog.warn('rfpack manifest: ${e.message}');
        throw ModelError(ModelErrorKind.integrity, e);
      }
      if (m.packs.length != 1) throw const ModelError(ModelErrorKind.notAPack);
      final pack = m.packs.single;
      if (filesFor(pack).isEmpty) throw const ModelError(ModelErrorKind.notAPack);
      final installed = (await repo.installed()).where((p) => p.id == pack.id).firstOrNull;
      if (installed != null && _semver(installed.version) > _semver(pack.version)) {
        throw ModelError(ModelErrorKind.rollback, '${pack.id} ${installed.version} installed');
      }
      // The license text the consent is for (ADR-0022), checked against the manifest.
      await _unpack(rfpack, 'license.txt', license, _maxLicenseBytes);
      try {
        await verifier.file(license, pack.license.textSha256);
      } on EnhException {
        throw const ModelError(ModelErrorKind.integrity);
      }
      AppLog.info('rfpack ${pack.id}@${pack.version}: signature ok');
      return OfflinePack(rfpack, pack, await File(license).readAsString());
    } finally {
      await dir.delete(recursive: true);
    }
  }

  /// Installs an opened offline pack: each file is unpacked (at most its manifest size) and
  /// checked against its SHA-256, then the pack moves into place as a downloaded one does.
  /// Throws [ModelError].
  Future<void> installOffline(OfflinePack p, {void Function(PackProgress)? onProgress}) async {
    final pack = p.pack;
    if (pack.license.requiresAcceptance && !await repo.hasConsent(pack)) {
      throw StateError('${pack.id}: license not accepted');
    }
    final files = filesFor(pack);
    // Not the download's staging directory: a partial download of the pack stays resumable.
    final staging = Directory('$modelsDir/.${pack.id}.rfpack');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      final total = files.fold(0, (n, f) => n + f.size);
      var done = 0;
      for (final f in files) {
        final dst = File('${staging.path}/${f.path}');
        await _unpack(p.path, f.path, dst.path, f.size);
        if (!await _verified(dst, f)) throw const ModelError(ModelErrorKind.integrity);
        done += f.size;
        onProgress?.call(PackProgress(done, total));
      }
      await _activate(pack, files, staging);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static const _maxManifestBytes = 1 << 20, _maxSignatureBytes = 4096;
  static const _maxLicenseBytes = 1 << 20;

  Future<void> _unpack(String rfpack, String entry, String dst, int maxBytes) async {
    try {
      await unpacker.extract(rfpack, entry, dst, maxBytes);
    } on EnhException catch (e) {
      AppLog.warn('rfpack $entry: ${e.status.name}');
      throw switch (e.status) {
        EnhStatus.io => ModelError(ModelErrorKind.storage, e),
        _ => ModelError(ModelErrorKind.notAPack, e),
      };
    }
  }

  static int _semver(String v) => v.split('.').map(int.parse).fold(0, (n, p) => n * 100000 + p);

  /// The pack replaces an older version in one rename; the old one is deleted afterwards.
  Future<void> _activate(PackInfo pack, List<PackFile> files, Directory staging) async {
    final target = Directory(dirOf(pack.id)), old = Directory('${target.path}.old');
    if (await old.exists()) await old.delete(recursive: true);
    if (await target.exists()) await target.rename(old.path);
    await staging.rename(target.path);
    if (await old.exists()) await old.delete(recursive: true);
    await repo.recordInstalled(pack, files, 'models/${pack.id}');
    AppLog.info('pack ${pack.id}@${pack.version} installed');
  }

  /// Deletes an installed pack.
  Future<void> remove(String packId) async {
    final path = await repo.removeInstalled(packId);
    final d = Directory(path == null ? dirOf(packId) : '$supportDir/$path');
    if (await d.exists()) await d.delete(recursive: true);
    AppLog.info('pack $packId removed');
  }

  /// Downloads the license text of [pack] and checks it against the manifest (what a consent
  /// is given for, ADR-0022). Throws [ModelError].
  Future<String> licenseText(PackInfo pack) async {
    await Directory(tmpDir).create(recursive: true);
    final f = File('$tmpDir/license-${pack.id}.txt');
    try {
      await _fetchAny([pack.license.url], f, _maxLicenseBytes);
      try {
        await verifier.file(f.path, pack.license.textSha256);
      } on EnhException {
        throw const ModelError(ModelErrorKind.integrity);
      }
      return await f.readAsString();
    } finally {
      if (await f.exists()) await f.delete();
    }
  }

  Future<bool> _verified(File f, PackFile spec) async {
    if (!await f.exists() || await f.length() != spec.size) return false;
    try {
      await verifier.file(f.path, spec.sha256);
      return true;
    } on EnhException {
      return false;
    }
  }

  /// Appends to [part] from where it stopped (HTTP Range), trying the mirrors in order.
  Future<void> _download(
    PackFile f,
    File part,
    void Function(int) onBytes,
    bool Function()? cancel,
  ) async {
    Object? last;
    for (final url in f.urls) {
      try {
        await _fetch(url, part, resume: true, expected: f.size, onBytes: onBytes, cancel: cancel);
        return;
      } on ModelError {
        rethrow;
      } on DownloadCancelled {
        rethrow;
      } on Exception catch (e) {
        AppLog.warn('mirror failed: ${Uri.parse(url).host}');
        last = e;
      }
    }
    throw ModelError(ModelErrorKind.network, last);
  }

  Future<void> _fetchAny(List<String> urls, File dst, int maxBytes) async {
    Object? last;
    for (final url in urls) {
      try {
        if (await dst.exists()) await dst.delete();
        await _fetch(url, dst, resume: false, expected: maxBytes);
        return;
      } on Exception catch (e) {
        last = e;
      }
    }
    throw ModelError(ModelErrorKind.network, last);
  }

  /// GET [uri] (from [from] bytes on, if > 0), following at most 5 redirects itself: every hop
  /// must be HTTPS too (PRIV-NET-004); dart:io would follow one to http://.
  Future<HttpClientResponse> _get(Uri start, int from) async {
    var uri = start;
    for (var hop = 0; ; ++hop) {
      if (uri.scheme != 'https') throw HttpException('https only', uri: uri);
      final req = await _http.getUrl(uri);
      req.followRedirects = false;
      if (from > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-');
      final res = await req.close();
      if (!res.isRedirect) return res;
      final location = res.headers.value(HttpHeaders.locationHeader);
      await res.drain<void>();
      if (location == null || hop >= 5) throw HttpException('bad redirect', uri: uri);
      uri = uri.resolve(location);
    }
  }

  Future<void> _fetch(
    String url,
    File dst, {
    required bool resume,
    int? expected,
    void Function(int)? onBytes,
    bool Function()? cancel,
  }) async {
    var have = resume && await dst.exists() ? await dst.length() : 0;
    if (expected != null && have > expected) {
      await dst.delete();
      have = 0;
    }
    final res = await _get(Uri.parse(url), have);
    final uri = Uri.parse(url);
    if (res.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      await res.drain<void>();
      return; // already complete; the hash decides
    }
    if (res.statusCode != HttpStatus.ok && res.statusCode != HttpStatus.partialContent) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: uri);
    }
    final append = res.statusCode == HttpStatus.partialContent && have > 0;
    if (!append) have = 0;
    final sink = dst.openWrite(mode: append ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in res) {
        if (cancel?.call() ?? false) throw const DownloadCancelled();
        have += chunk.length;
        // The hash decides in the end; this only keeps a bad mirror from filling the disk.
        if (expected != null && have > expected) {
          throw HttpException('more than $expected bytes', uri: uri);
        }
        sink.add(chunk);
        onBytes?.call(have);
      }
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 28) throw ModelError(ModelErrorKind.storage, e);
      rethrow;
    } finally {
      await sink.close();
    }
  }
}

/// A verified offline pack (.rfpack), ready to install once its license is accepted.
class OfflinePack {
  const OfflinePack(this.path, this.pack, this.licenseText);
  final String path;
  final PackInfo pack;

  /// Checked against the manifest's SHA-256: what a consent is given for (ADR-0022).
  final String licenseText;
}

/// [ModelManager.install] was cancelled; the partial file stays for resuming.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// Which pack files this device takes.
class ModelPlatform {
  const ModelPlatform(this.name, this.backend);

  /// Android: ncnn; iOS: Core ML (04 §6).
  factory ModelPlatform.current() => Platform.isIOS
      ? const ModelPlatform('ios', 'coreml')
      : const ModelPlatform('android', 'ncnn');

  final String name, backend;
}

final modelManagerProvider = FutureProvider<ModelManager>((ref) async {
  final engine = await ref.watch(engineProvider.future);
  return ModelManager(
    repo: ModelRepository(await ref.watch(databaseProvider.future)),
    verifier: NativeModelVerifier(engine.native),
    unpacker: NativePackUnpacker(engine.native),
    supportDir: engine.dirs.support,
    tmpDir: '${engine.dirs.cache}/models',
  );
});

/// Installed packs (ids → version).
final installedPacksProvider = StreamProvider<List<InstalledPack>>((ref) async* {
  final repo = (await ref.watch(modelManagerProvider.future)).repo;
  yield* repo.watchInstalled();
});

/// Models the device has now: the bundled SR model, the bundled face detector once installed,
/// and installed packs.
final availableModelsProvider = Provider<Set<String>>((ref) {
  final installed = ref.watch(installedPacksProvider).value ?? const <InstalledPack>[];
  final detector = ref.watch(engineProvider).value?.detectorReady ?? false;
  return {bundledSrModel, if (detector) bundledDetector, for (final p in installed) p.id};
});

/// FR-MODEL-008: installed packs the manifest has a newer version of, that [appVersion] can use.
List<PackInfo> packUpdates(Manifest m, List<InstalledPack> installed, {String? appVersion}) {
  List<int> v(String s) => s.split('.').map(int.parse).toList();
  bool newer(String a, String b) {
    final (x, y) = (v(a), v(b));
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] > y[i];
    }
    return false;
  }

  return [
    for (final i in installed)
      if (m.pack(i.id) case final p?
          when newer(p.version, i.version) && (appVersion == null || p.supportedBy(appVersion)))
        p,
  ];
}

/// FR-SET-005: with the check on, the manifest is fetched at most once a day (else the one
/// already verified is used); the packs with an update come back. Off: nothing, no network.
final packUpdatesProvider = FutureProvider<List<PackInfo>>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  if (!settings.packUpdateCheck) return const [];
  final manager = await ref.watch(modelManagerProvider.future);
  final installed = await manager.repo.installed();
  if (installed.isEmpty) return const [];
  var m = await manager.repo.current();
  final last = settings.packUpdateCheckedAt;
  if (last == null || DateTime.now().difference(last) > const Duration(days: 1)) {
    try {
      m = await manager.refresh();
      AppLog.info('pack update check: serial ${m.serial}');
    } on ModelError catch (e) {
      AppLog.warn('pack update check: ${e.kind.name}'); // tried again tomorrow
    }
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(packUpdateCheckedAt: DateTime.now));
  }
  final appVersion = (await ref.watch(engineProvider.future)).version;
  return m == null ? const [] : packUpdates(m, installed, appVersion: appVersion);
});

/// The face pack the app uses (FR-FACE-002: GFPGAN 1.4 by default).
const defaultFacePack = 'face.gfpgan-1.4';

/// CodeFormer (FR-FACE-005): optional, with a fidelity control (ADR-0024).
const codeformerPack = 'face.codeformer';

/// Face packs in the order the editor offers them.
const facePacks = [defaultFacePack, codeformerPack];

/// S9: the JPEG cleanup pack (FBCNN restore graph, T2).
const jpegPack = 'jpeg.fbcnn';

/// Whether [r] can run with [available] models (faces need the detector as well).
bool canRun(Recipe r, Set<String> available) =>
    available.contains(r.srModel) &&
    (r.faceModel == null ||
        (available.contains(r.faceModel) && available.contains(bundledDetector)));

/// The Models screen's state: the manifest shown (the last verified one until the user asks
/// for a newer), and downloads in progress (they go on while the app runs).
class ModelsState {
  const ModelsState({this.manifest, this.downloads = const {}, this.checking = false});
  final Manifest? manifest;
  final Map<String, PackProgress> downloads;
  final bool checking;

  ModelsState copyWith({
    Manifest? manifest,
    Map<String, PackProgress>? downloads,
    bool? checking,
  }) => ModelsState(
    manifest: manifest ?? this.manifest,
    downloads: downloads ?? this.downloads,
    checking: checking ?? this.checking,
  );
}

class ModelsController extends AsyncNotifier<ModelsState> {
  final _cancelled = <String>{};

  @override
  Future<ModelsState> build() async {
    final manager = await ref.watch(modelManagerProvider.future);
    return ModelsState(manifest: await manager.repo.current());
  }

  ModelsState get _s => state.value ?? const ModelsState();

  /// Fetches the manifest (the user's action, ADR-0020). Throws [ModelError].
  Future<void> refresh() async {
    final manager = await ref.read(modelManagerProvider.future);
    state = AsyncData(_s.copyWith(checking: true));
    try {
      state = AsyncData(_s.copyWith(manifest: await manager.refresh(), checking: false));
    } finally {
      if (_s.checking) state = AsyncData(_s.copyWith(checking: false));
    }
  }

  /// Throws [ModelError] (not on cancel).
  Future<void> install(PackInfo pack) async {
    final manager = await ref.read(modelManagerProvider.future);
    _cancelled.remove(pack.id);
    void progress(PackProgress p) =>
        state = AsyncData(_s.copyWith(downloads: {..._s.downloads, pack.id: p}));
    progress(const PackProgress(0, 0));
    try {
      await manager.install(pack, onProgress: progress, cancel: () => _cancelled.contains(pack.id));
    } on DownloadCancelled {
      AppLog.info('pack ${pack.id}: download cancelled');
    } finally {
      state = AsyncData(_s.copyWith(downloads: {..._s.downloads}..remove(pack.id)));
    }
  }

  /// Installs an opened offline pack (FR-MODEL-006), with progress like a download. Throws
  /// [ModelError].
  Future<void> installOffline(OfflinePack p) async {
    final manager = await ref.read(modelManagerProvider.future);
    void progress(PackProgress x) =>
        state = AsyncData(_s.copyWith(downloads: {..._s.downloads, p.pack.id: x}));
    progress(const PackProgress(0, 0));
    try {
      await manager.installOffline(p, onProgress: progress);
    } finally {
      state = AsyncData(_s.copyWith(downloads: {..._s.downloads}..remove(p.pack.id)));
    }
  }

  void cancel(String packId) => _cancelled.add(packId);

  Future<void> remove(String packId) async =>
      (await ref.read(modelManagerProvider.future)).remove(packId);
}

final modelsProvider = AsyncNotifierProvider<ModelsController, ModelsState>(ModelsController.new);
