// Prints what a crawler gets from a Flutter web build, before and after.
//
//   dart run example/what_a_crawler_sees.dart
//
// A crawler does not run your app. It reads the HTML the server returned, and
// for a Flutter web build that is a bootstrap script and an empty body. This
// walks the two files and counts what is actually in each, so the difference
// is a number rather than a claim.
import 'dart:io';

void main() {
  // A real build if there is one, and the committed fixtures if there is not.
  //
  // The fallback is the point rather than a convenience: someone deciding
  // whether this tool is worth installing should be able to see what it does
  // before running a Flutter build, and these two files are the same two the
  // package's own test asserts against.
  var before = File('example/build/web/index.html');
  var after = File('example/build/prerendered/index.html');
  var source = 'your build';

  if (!before.existsSync() || !after.existsSync()) {
    before = File('example/web/index.html');
    after = File('example/expected_output/index.html');
    source = 'the committed fixtures';
  }

  if (!before.existsSync() || !after.existsSync()) {
    // Only reachable outside a checkout, so it says where it looked.
    stderr.writeln(
      'Nothing to read. Run this from the package root, or build the '
      'example first:\n'
      '  cd example && flutter build web\n'
      '  cd example && dart run ../bin/flutter_prerender.dart '
      '-c flutter_prerender.yaml',
    );
    exit(69); // EX_UNAVAILABLE
  }

  final a = _Page(before.readAsStringSync());
  final b = _Page(after.readAsStringSync());

  stdout
    ..writeln('what a crawler reads, before and after prerendering')
    ..writeln('  (reading $source)')
    ..writeln('')
    ..writeln('                      flutter build web    prerendered')
    ..writeln('  ${'-' * 56}')
    ..writeln(_row('words in <body>', '${a.words}', '${b.words}'))
    ..writeln(_row('<title>', a.title, b.title))
    ..writeln(_row('meta description', a.description, b.description))
    ..writeln(_row('og:title', a.has('og:title'), b.has('og:title')))
    ..writeln(
      _row(
        'JSON-LD',
        a.has('application/ld+json'),
        b.has('application/ld+json'),
      ),
    )
    ..writeln('')
    ..writeln('The app is identical in a browser. The difference is what is')
    ..writeln('there before any JavaScript runs, which is all a crawler gets.');
}

String _row(String label, String a, String b) =>
    '  ${label.padRight(20)}  ${a.padRight(19)}  $b';

/// The handful of things a crawler looks at, pulled out of a page.
class _Page {
  _Page(this._html);

  final String _html;

  /// Words of visible text, which is the number that matters: a Flutter build
  /// ships an empty body and every word arrives later from JavaScript.
  int get words {
    final body = RegExp(
      r'<body[^>]*>(.*?)</body>',
      dotAll: true,
    ).firstMatch(_html)?.group(1);
    if (body == null) return 0;
    final withoutScripts = body.replaceAll(
      RegExp(r'<script.*?</script>', dotAll: true),
      ' ',
    );
    final text = withoutScripts.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return text.split(RegExp(r'\s+')).where((w) => w.trim().isNotEmpty).length;
  }

  String get title {
    final t = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(_html);
    final value = t?.group(1)?.trim() ?? '';
    if (value.isEmpty) return 'none';
    return value.length > 17 ? '${value.substring(0, 16)}…' : value;
  }

  String get description {
    final m = RegExp(
      r'<meta[^>]+name="description"[^>]+content="([^"]*)"',
    ).firstMatch(_html);
    final value = m?.group(1)?.trim() ?? '';
    return value.isEmpty ? 'none' : '${value.length} chars';
  }

  String has(String needle) => _html.contains(needle) ? 'yes' : 'no';
}
