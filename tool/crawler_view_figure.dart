// Draws what a crawler gets, before and after.
//
//   dart run tool/crawler_view_figure.dart
//
// The README's claim is that a Flutter web build hands a crawler an empty
// document. That is easy to say and easy to disbelieve, because the page looks
// fine in a browser -- the canvas paints, the text is right there. What a bot
// sees is the HTML before any of that runs.
//
// Both sides are read from files in the repository rather than described:
// `example/web/index.html` is the shell `flutter build web` produces, and
// `example/expected_output/index.html` is what this tool wrote and what the
// example's own test asserts against. If either changes, the figure changes.
import 'dart:io';

const bg = '#14161C';
const panel = '#1b1f28';
const ink = '#d8dee9';
const dim = '#8b93a3';
const edge = '#39414f';
const empty = '#ff8f6b';
const filled = '#8ee0a1';

typedef Seen = ({
  int words,
  int headings,
  int links,
  String title,
  List<String> lines,
});

/// Reads a page the way a crawler reads it: markup out, text in.
Seen crawl(String path) {
  final html = File(path).readAsStringSync();
  final body = RegExp(
    r'<body[^>]*>(.*?)</body>',
    dotAll: true,
  ).firstMatch(html);
  var text = body?.group(1) ?? '';
  text = text.replaceAll(RegExp(r'<script.*?</script>', dotAll: true), '');
  text = text.replaceAll(RegExp('<[^>]+>'), ' ');
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final title =
      RegExp(
        r'<title>(.*?)</title>',
        dotAll: true,
      ).firstMatch(html)?.group(1)?.trim() ??
      '';
  return (
    words: words.length,
    headings: RegExp('<h[12]', caseSensitive: false).allMatches(html).length,
    links: RegExp('<a [^>]*href', caseSensitive: false).allMatches(html).length,
    title: title,
    lines: _wrap(words, 44).take(6).toList(),
  );
}

List<String> _wrap(List<String> words, int width) {
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (current.length + word.length + 1 > width) {
      lines.add(current);
      current = word;
    } else {
      current = current.isEmpty ? word : '$current $word';
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines;
}

String escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String panelSvg(double x, String heading, Seen seen, String accent) {
  const w = 360.0, top = 74.0, h = 250.0;
  final b = StringBuffer()
    ..writeln(
      '  <text x="$x" y="34" fill="$ink" font-size="14" '
      'font-family="Menlo, monospace">$heading</text>',
    )
    ..writeln(
      '  <text x="$x" y="54" fill="$accent" font-size="12" '
      'font-family="Menlo, monospace">'
      '${seen.words} words · ${seen.headings} headings · '
      '${seen.links} links</text>',
    )
    ..writeln(
      '  <rect x="$x" y="$top" width="$w" height="$h" fill="$panel" '
      'stroke="$edge" stroke-width="1.2" rx="4"/>',
    )
    ..writeln(
      '  <text x="${x + 14}" y="${top + 26}" fill="$dim" '
      'font-size="10.5" font-family="Menlo, monospace">'
      '&lt;title&gt; ${escape(seen.title.length > 40 ? "${seen.title.substring(0, 40)}…" : seen.title)}</text>',
    )
    ..writeln(
      '  <line x1="${x + 14}" y1="${top + 38}" x2="${x + w - 14}" '
      'y2="${top + 38}" stroke="$edge" stroke-width="1"/>',
    );

  if (seen.words == 0) {
    b
      ..writeln(
        '  <text x="${x + w / 2}" y="${top + 130}" fill="$accent" '
        'font-size="13" font-family="Menlo, monospace" '
        'text-anchor="middle">nothing to read</text>',
      )
      ..writeln(
        '  <text x="${x + w / 2}" y="${top + 152}" fill="$dim" '
        'font-size="11" font-family="Menlo, monospace" '
        'text-anchor="middle">the body holds one script tag</text>',
      );
  } else {
    var y = top + 62;
    for (final line in seen.lines) {
      b.writeln(
        '  <text x="${x + 14}" y="$y" fill="$ink" font-size="11" '
        'font-family="Menlo, monospace">${escape(line)}</text>',
      );
      y += 17;
    }
    b.writeln(
      '  <text x="${x + 14}" y="${y + 8}" fill="$dim" font-size="10.5" '
      'font-family="Menlo, monospace">…</text>',
    );
  }
  return b.toString();
}

void main() {
  final before = crawl('example/web/index.html');
  final after = crawl('example/expected_output/index.html');

  const left = 40.0, gap = 44.0, panelW = 360.0;
  final width = left * 2 + panelW * 2 + gap;
  const height = 384.0;

  final svg = StringBuffer()
    ..writeln(
      '<svg xmlns="http://www.w3.org/2000/svg" '
      'width="${width.toStringAsFixed(0)}" height="${height.toInt()}" '
      'viewBox="0 0 ${width.toStringAsFixed(0)} ${height.toInt()}">',
    )
    ..writeln('  <rect width="100%" height="100%" fill="$bg"/>')
    ..write(panelSvg(left, 'what a crawler fetches today', before, empty))
    ..write(
      panelSvg(left + panelW + gap, 'after flutter_prerender', after, filled),
    )
    ..writeln(
      '  <text x="${width / 2}" y="366" fill="$dim" font-size="11" '
      'font-family="Menlo, monospace" text-anchor="middle">'
      'both panels are read from files in this repository: the shell '
      '`flutter build web` writes, and the page this tool writes</text>',
    )
    ..writeln('</svg>');

  File('doc/crawler-view.svg').writeAsStringSync(svg.toString());
  stdout
    ..writeln('wrote doc/crawler-view.svg')
    ..writeln(
      '  before: ${before.words} words, ${before.headings} headings, '
      '${before.links} links',
    )
    ..writeln(
      '  after:  ${after.words} words, ${after.headings} headings, '
      '${after.links} links',
    )
    ..writeln(
      'render: rsvg-convert -z 2 doc/crawler-view.svg '
      '-o doc/crawler-view.png',
    );
}
