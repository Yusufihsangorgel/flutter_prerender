import 'dart:io';

import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('contentTypeFor', () {
    test('maps common web extensions', () {
      expect(contentTypeFor('a.html'), startsWith('text/html'));
      expect(contentTypeFor('main.dart.js'), startsWith('text/javascript'));
      expect(contentTypeFor('canvaskit.wasm'), 'application/wasm');
      expect(contentTypeFor('x.json'), startsWith('application/json'));
    });

    test('defaults to octet-stream for unknown extensions', () {
      expect(contentTypeFor('mystery.xyz'), 'application/octet-stream');
    });
  });

  group('resolveWithinRoot', () {
    test('resolves an in-tree path', () {
      final resolved = resolveWithinRoot('/srv/web', '/main.dart.js');
      expect(resolved, p.normalize('/srv/web/main.dart.js'));
    });

    test('rejects traversal outside the root', () {
      expect(resolveWithinRoot('/srv/web', '/../../etc/passwd'), isNull);
    });
  });

  group('StaticServer', () {
    late Directory dir;
    late StaticServer server;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('fp_static_');
      File(p.join(dir.path, 'index.html')).writeAsStringSync('<h1>Home</h1>');
      File(
        p.join(dir.path, 'main.dart.js'),
      ).writeAsStringSync('console.log(1)');
      server = await StaticServer.start(dir.path);
    });

    tearDown(() async {
      await server.close();
      dir.deleteSync(recursive: true);
    });

    Future<HttpClientResponse> get(String path) async {
      final client = HttpClient();
      final request = await client.getUrl(server.baseUri.resolve(path));
      final response = await request.close();
      return response;
    }

    test('serves an existing asset with its content type', () async {
      final response = await get('/main.dart.js');
      expect(response.statusCode, 200);
      expect(
        response.headers.contentType.toString(),
        startsWith('text/javascript'),
      );
    });

    test('falls back to index.html for unknown routes', () async {
      final response = await get('/beans/kenya');
      expect(response.statusCode, 200);
      final body = await response.transform(systemEncoding.decoder).join();
      expect(body, contains('<h1>Home</h1>'));
    });
  });
}
