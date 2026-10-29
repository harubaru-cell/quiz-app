import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs the production browser adapters with synthetic data in a new Chrome
/// profile and a temporary loopback origin. No Flutter SDK changes are needed.
Future<void> main() async {
  final output = Directory('build/backup-browser-probe').absolute;
  await output.create(recursive: true);
  final javascript = File('${output.path}/probe.js');
  final compilation = await Process.run(Platform.resolvedExecutable, [
    'compile',
    'js',
    '-O1',
    '-o',
    javascript.path,
    'tool/backup_browser_probe.dart'
  ]).timeout(const Duration(seconds: 90));
  if (compilation.exitCode != 0) {
    stderr.write(compilation.stderr);
    stdout.write(compilation.stdout);
    exitCode = compilation.exitCode;
    return;
  }
  final chromePath = Platform.environment['CHROME_EXECUTABLE'] ??
      'C:/Program Files/Google/Chrome/Application/chrome.exe';
  final profile = Directory(
      '${output.path}/profile-${DateTime.now().microsecondsSinceEpoch}');
  await profile.create();
  final result = Completer<Map<String, dynamic>>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final subscription = server.listen((request) async {
    try {
      if (request.uri.path == '/result' && request.method == 'POST') {
        final data = jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
        request.response.write('ok');
        await request.response.close();
        if (!result.isCompleted) result.complete(data);
      } else if (request.uri.path == '/probe.js') {
        request.response.headers.contentType =
            ContentType('text', 'javascript');
        await request.response.addStream(javascript.openRead());
        await request.response.close();
      } else if (request.uri.path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
            '<!doctype html><meta charset="utf-8"><body>Running synthetic backup probe'
            '<script defer src="/probe.js"></script></body>');
        await request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (error, stack) {
      if (!result.isCompleted) result.completeError(error, stack);
      await request.response.close();
    }
  });
  Process? chrome;
  var browserErrors = '';
  try {
    chrome = await Process.start(chromePath, [
      '--headless=new',
      '--disable-gpu',
      '--no-first-run',
      '--no-default-browser-check',
      '--user-data-dir=${profile.path}',
      'http://127.0.0.1:${server.port}/',
    ]);
    unawaited(chrome.stdout.drain<void>());
    unawaited(chrome.stderr.transform(utf8.decoder).forEach((chunk) {
      browserErrors = '$browserErrors$chunk';
      if (browserErrors.length > 4000) {
        browserErrors = browserErrors.substring(browserErrors.length - 4000);
      }
    }));
    final report = await result.future.timeout(const Duration(seconds: 45));
    stdout.writeln('NATIVE_BACKUP_BROWSER_PROBE ${jsonEncode(report)}');
    if (report['passed'] != true) exitCode = 1;
  } catch (error) {
    stderr.writeln('Browser probe failed: $error\n$browserErrors');
    exitCode = 1;
  } finally {
    chrome?.kill();
    if (chrome != null) {
      await chrome.exitCode.timeout(const Duration(seconds: 10));
    }
    await subscription.cancel();
    await server.close(force: true);
  }
}
