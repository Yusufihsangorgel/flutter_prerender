// Serves the example's flutter build web output and the prerendered output,
// fetches each index.html over HTTP, and prints what a crawler that does
// not run JavaScript would read. Exits 1 if the prerendered document is
// missing the heading, body copy, title, or meta description.
//
//   dart run tool/measure_crawler_fetch.dart
//
// Defaults:
//   --plain example/build/web
//   --prerendered example/build/prerendered
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Text the example app paints, and the title/description its prerender
/// config writes. Must match `example/lib/main.dart` and
/// `example/flutter_prerender.yaml`.
const _h1 = 'Quintessential Ethiopian Yirgacheffe';
const _paragraph =
    'We roast marmoset-grade arabica beans in small batches every '
    'Tuesday. Our flagship blend carries notes of bergamot, persimmon '
    'and a faint whisper of petrichor.';
const _title = 'Zebrafish Coffee Roasters: Ethiopian Yirgacheffe';
const _description =
    'Small-batch, carbon-neutral arabica roasted every Tuesday in Munich.';

Future<void> main(List<String> args) async {
  var plainDir = 'example/build/web';
  var prerenderedDir = 'example/build/prerendered';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--plain' && i + 1 < args.length) {
      plainDir = args[++i];
    } else if (arg == '--prerendered' && i + 1 < args.length) {
      prerenderedDir = args[++i];
    } else if (arg == '--help' || arg == '-h') {
      stdout.writeln(
        'Usage: dart run tool/measure_crawler_fetch.dart '
        '[--plain DIR] [--prerendered DIR]',
      );
      return;
    } else {
      stderr.writeln('Unknown argument: $arg');
      exitCode = 64;
      return;
    }
  }

  if (!File(p.join(plainDir, 'index.html')).existsSync() ||
      !File(p.join(prerenderedDir, 'index.html')).existsSync()) {
    stderr.writeln(
      'Nothing to fetch. Build the example, prerender it, then rerun:\n'
      '  cd example && flutter build web\n'
      '  dart run flutter_prerender '
      '--config example/flutter_prerender.yaml '
      '--build-dir example/build/web '
      '--out example/build/prerendered\n'
      '  dart run tool/measure_crawler_fetch.dart',
    );
    exitCode = 69;
    return;
  }

  final _Page plain;
  final _Page prerendered;
  try {
    plain = await _fetchServedIndex(plainDir);
    prerendered = await _fetchServedIndex(prerenderedDir);
  } on HttpException catch (e) {
    stderr.writeln(e.message);
    exitCode = 1;
    return;
  }

  stdout
    ..writeln('what a crawler reads over HTTP, no JavaScript')
    ..writeln('  plain:       $plainDir')
    ..writeln('  prerendered: $prerenderedDir')
    ..writeln('')
    ..writeln('                      flutter build web    prerendered')
    ..writeln('  ${'-' * 56}')
    ..writeln(
      _row('HTML bytes', '${plain.byteSize}', '${prerendered.byteSize}'),
    )
    ..writeln(
      _row(
        'h1 in raw HTML',
        plain.contains(_h1) ? 'yes' : 'no',
        prerendered.contains(_h1) ? 'yes' : 'no',
      ),
    )
    ..writeln(
      _row(
        'paragraph in HTML',
        plain.contains(_paragraph) ? 'yes' : 'no',
        prerendered.contains(_paragraph) ? 'yes' : 'no',
      ),
    )
    ..writeln(
      _row(
        'example title',
        plain.contains(_title) ? 'yes' : 'no',
        prerendered.contains(_title) ? 'yes' : 'no',
      ),
    )
    ..writeln(
      _row(
        'example description',
        plain.contains(_description) ? 'yes' : 'no',
        prerendered.contains(_description) ? 'yes' : 'no',
      ),
    )
    ..writeln(
      _row(
        'words before JS',
        '${plain.contentWordCount}',
        '${prerendered.contentWordCount}',
      ),
    )
    ..writeln('')
    ..writeln('  <title>')
    ..writeln('    flutter build web  ${_cell(plain.title)}')
    ..writeln('    prerendered        ${_cell(prerendered.title)}')
    ..writeln('  meta description')
    ..writeln('    flutter build web  ${_cell(plain.metaDescription)}')
    ..writeln('    prerendered        ${_cell(prerendered.metaDescription)}')
    ..writeln('')
    ..writeln(
      'This does not prove ranking improved, it does not prove traffic '
      'improved, and Google\'s crawler does execute JavaScript in many '
      'cases, so the plain build is not necessarily invisible to it. The '
      'measured claim is about what is in the HTML at fetch time and about '
      'crawlers that do not execute scripts.',
    );

  final missing = <String>[];
  if (!prerendered.contains(_h1)) missing.add('h1 text');
  if (!prerendered.contains(_paragraph)) missing.add('paragraph body');
  if (!prerendered.contains(_title)) missing.add('title');
  if (!prerendered.contains(_description)) missing.add('meta description');
  if (prerendered.contentWordCount == 0) missing.add('content words');
  if (missing.isNotEmpty) {
    stderr.writeln('prerendered HTML is missing: ${missing.join(', ')}');
    exitCode = 1;
  }
}

/// Serves [dir] on loopback, GETs `/`, and returns the response body.
Future<_Page> _fetchServedIndex(String dir) async {
  final index = File(p.join(dir, 'index.html'));
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final response = request.response;
    if (!index.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.headers.contentType = ContentType.html;
    await response.addStream(index.openRead());
    await response.close();
  });
  final client = HttpClient();
  try {
    final uri = Uri.parse('http://127.0.0.1:${server.port}/');
    final request = await client.getUrl(uri);
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GET $uri returned ${response.statusCode}', uri: uri);
    }
    return _Page(builder.takeBytes());
  } finally {
    client.close(force: true);
    await server.close(force: true);
  }
}

/// One fetched HTML document, inspected without running JavaScript.
class _Page {
  _Page(List<int> bodyBytes)
    : bodyBytes = Uint8List.fromList(bodyBytes),
      html = utf8.decode(bodyBytes);

  final Uint8List bodyBytes;
  final String html;

  int get byteSize => bodyBytes.length;

  bool contains(String text) => html.contains(text);

  String? get title {
    final match = RegExp(
      r'<title>(.*?)</title>',
      dotAll: true,
    ).firstMatch(html);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? get metaDescription {
    final match = RegExp(
      r'<meta\s[^>]*name="description"[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return null;
    final content = RegExp('content="([^"]*)"').firstMatch(match.group(0)!);
    final value = content?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Words in `<body>` after stripping `<script>` elements and tags.
  int get contentWordCount {
    final body = RegExp(
      r'<body[^>]*>(.*?)</body>',
      dotAll: true,
    ).firstMatch(html)?.group(1);
    if (body == null) return 0;
    final withoutScripts = body.replaceAll(
      RegExp(r'<script.*?</script>', dotAll: true),
      ' ',
    );
    final text = withoutScripts.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return text.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).length;
  }
}

String _row(String label, String a, String b) =>
    '  ${label.padRight(20)}  ${a.padRight(19)}  $b';

String _cell(String? value) {
  if (value == null || value.isEmpty) return 'none';
  return value;
}
