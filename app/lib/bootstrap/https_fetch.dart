import 'dart:async';
import 'dart:io';

/// HTTPS downloads for the model manager and the app updater: Range resume, a size cap and
/// no redirect to anything but HTTPS (PRIV-NET-004). The caller checks the hash.
class HttpsFetcher {
  HttpsFetcher([HttpClient? http])
    : _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 20));

  final HttpClient _http;

  /// GET [uri] (from [from] bytes on, if > 0), following at most 5 redirects itself: every hop
  /// must be HTTPS too; dart:io would follow one to http://.
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

  /// Writes [url] to [dst]; with [resume], appends to what [dst] already has. More than
  /// [expected] bytes is an error. Throws [StorageFull] when the disk is full and
  /// [DownloadCancelled] when [cancel] says so.
  Future<void> fetch(
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
      if (e.osError?.errorCode == 28) throw StorageFull(e);
      rethrow;
    } finally {
      await sink.close();
    }
  }
}

/// A download was cancelled; the partial file stays for resuming.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// No space left on the device (ENOSPC).
class StorageFull implements Exception {
  const StorageFull(this.cause);
  final FileSystemException cause;
}
