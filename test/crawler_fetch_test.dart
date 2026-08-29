import 'dart:convert';
import 'dart:io';

import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

/// Runs the committed producer: `tool/measure_crawler_fetch.dart`.
Future<ProcessResult> _measure({
  required String plain,
  required String prerendered,
}) {
  return Process.run('dart', [
    'run',
    'tool/measure_crawler_fetch.dart',
    '--plain',
    plain,
    '--prerendered',
    prerendered,
  ]);
}

void main() {
  const h1 = 'Quintessential Ethiopian Yirgacheffe';
  const paragraph =
      'We roast marmoset-grade arabica beans in small batches every '
      'Tuesday. Our flagship blend carries notes of bergamot, persimmon '
      'and a faint whisper of petrichor.';
  const title = 'Zebrafish Coffee Roasters: Ethiopian Yirgacheffe';
  const description =
      'Small-batch, carbon-neutral arabica roasted every Tuesday in Munich.';

  test('exits 0 on the committed example fixtures', () async {
    final result = await _measure(
      plain: 'example/web',
      prerendered: 'example/expected_output',
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final out = result.stdout.toString();
    expect(out, contains('h1 in raw HTML'));
    expect(out, contains('HTML bytes'));
    expect(
      out,
      contains(
        'This does not prove ranking improved, it does not prove traffic '
        'improved',
      ),
    );
  });

  test('exits 1 when the prerendered page is the empty shell', () async {
    final result = await _measure(
      plain: 'example/web',
      prerendered: 'example/web',
    );
    expect(result.exitCode, 1);
    expect(result.stderr.toString(), contains('prerendered HTML is missing'));
  });

  test('exits 69 when either directory has no index.html', () async {
    final missing = Directory.systemTemp.createTempSync('fp_crawler_none_');
    addTearDown(() => missing.deleteSync(recursive: true));
    final result = await _measure(
      plain: missing.path,
      prerendered: 'example/expected_output',
    );
    expect(result.exitCode, 69);
  });

  test(
    'GET / of the flutter shell has no example heading or body copy',
    () async {
      final html = await _httpGetIndex('example/web');
      expect(html.contains(h1), isFalse);
      expect(html.contains(paragraph), isFalse);
      expect(html.contains(title), isFalse);
      expect(html.contains(description), isFalse);
    },
  );

  test(
    'GET / of the prerendered fixture contains the example content',
    () async {
      final html = await _httpGetIndex('example/expected_output');
      expect(html, contains(h1));
      expect(html, contains(paragraph));
      expect(html, contains('<title>$title</title>'));
      expect(html, contains(description));
      expect(html, contains('<h1>$h1</h1>'));
    },
  );
}

/// Serves [dir] and returns the body of GET `/`, the way a crawler fetches it.
Future<String> _httpGetIndex(String dir) async {
  final server = await StaticServer.start(dir);
  final client = HttpClient();
  try {
    final request = await client.getUrl(server.baseUri);
    final response = await request.close();
    expect(response.statusCode, HttpStatus.ok);
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close(force: true);
    await server.close();
  }
}
