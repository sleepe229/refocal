import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:refocal/bootstrap/foreground.dart';
import 'package:refocal_platform/refocal_platform.dart';

class FakeApi implements RefocalPlatformApi {
  final calls = <String>[];
  bool refuseStart = false;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Future<void> startProcessing(ProcessingTexts texts) async {
    if (refuseStart) throw PlatformException(code: 'ForegroundServiceStartNotAllowedException');
    calls.add('start');
  }

  @override
  Future<void> updateProcessing(String text, int percent) async => calls.add('update $text');

  @override
  Future<void> stopProcessing(String? finishedText) async => calls.add('stop $finishedText');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  ProcessingTexts texts() => ProcessingTexts(
    title: 't',
    pause: 'p',
    cancel: 'c',
    timedOut: 'o',
    channelName: 'n',
    channelDescription: 'd',
  );

  test('the service runs while anyone holds it; the last one stops it', () async {
    final api = FakeApi();
    final fg = ForegroundWork(api, texts);
    final editor = Object(), queue = Object();
    await fg.acquire(queue);
    await fg.acquire(editor);
    await fg.update(editor, '10%', 10);
    await fg.release(editor, 'Photo ready'); // the queue still runs: no stop, no text
    await fg.update(queue, '1 of 2', 50);
    await fg.update(editor, 'late', 99); // released: ignored
    await fg.release(queue, 'Queue finished');
    await fg.release(queue, 'twice'); // ignored
    expect(api.calls, ['start', 'update 10%', 'update 1 of 2', 'stop Queue finished']);
  });

  test('a refused start does not stop processing', () async {
    final api = FakeApi()..refuseStart = true;
    final fg = ForegroundWork(api, texts);
    final h = Object();
    await fg.acquire(h);
    await fg.update(h, '5%', 5);
    await fg.release(h, null);
    expect(api.calls, ['update 5%', 'stop null']);
  });
}
