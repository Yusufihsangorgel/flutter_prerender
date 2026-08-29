import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The files under `doc/hosting/` are the copy-paste configs the serving
/// guide cites. Invalid JSON there is a broken instruction, not a style
/// issue: someone will deploy it.
void main() {
  final hosting = Directory('doc/hosting');
  final jsonFiles =
      hosting
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('every hosted JSON file parses', () {
    expect(jsonFiles, isNotEmpty);
    for (final file in jsonFiles) {
      expect(
        () => jsonDecode(file.readAsStringSync()),
        returnsNormally,
        reason: file.path,
      );
    }
  });

  test('Firebase overlay is a path rewrite, not a function', () {
    final config =
        jsonDecode(
              File(
                'doc/hosting/firebase/overlay/firebase.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final hostingConfig = config['hosting'] as Map<String, dynamic>;
    expect(hostingConfig['public'], 'deploy');
    expect(hostingConfig['trailingSlash'], false);
    final rewrites = hostingConfig['rewrites'] as List<dynamic>;
    expect(rewrites, hasLength(1));
    final rule = rewrites.single as Map<String, dynamic>;
    expect(rule['source'], '**');
    expect(rule['destination'], '/index.html');
    expect(rule.containsKey('function'), isFalse);
  });

  test('Firebase bot routing sends missing paths to a named function', () {
    final config =
        jsonDecode(
              File(
                'doc/hosting/firebase/bot-routing/firebase.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final rule =
        ((config['hosting'] as Map<String, dynamic>)['rewrites']
                    as List<dynamic>)
                .single
            as Map<String, dynamic>;
    expect(rule['source'], '**');
    expect(rule.containsKey('destination'), isFalse);
    final function = rule['function'] as Map<String, dynamic>;
    expect(function['functionId'], 'servePrerender');
    expect(function['region'], 'us-central1');
    expect(function['pinTag'], true);
  });

  test('Cloudflare _routes.json excludes static assets from Functions', () {
    final routes =
        jsonDecode(
              File(
                'doc/hosting/cloudflare/bot-routing/_routes.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(routes['version'], 1);
    expect(routes['include'], ['/*']);
    final exclude = (routes['exclude'] as List<dynamic>).cast<String>();
    expect(exclude, contains('/assets/*'));
    expect(exclude, contains('/*.wasm'));
    expect(exclude, contains('/__prerendered/*'));
  });

  test('the serving guide names both topologies and the cloaking line', () {
    final guide = File('doc/serving.md').readAsStringSync();
    expect(guide, contains('Firebase Hosting'));
    expect(guide, contains('Netlify'));
    expect(guide, contains('Cloudflare Pages'));
    expect(guide, contains('dynamic rendering'));
    expect(guide, contains('cloaking'));
    expect(guide, contains('trailingSlash'));
    expect(guide, contains('Netlify-Agent-Category'));
    expect(guide, contains('env.ASSETS.fetch'));
    // Redirects on Pages are always followed; a catch-all would hide
    // prerendered files. The guide has to say that or the overlay is wrong.
    expect(guide, contains('always followed'));
  });

  test('bot-routing JS files share the crawler regex and prettyDir', () {
    final files = [
      'doc/hosting/firebase/bot-routing/functions/index.js',
      'doc/hosting/netlify/bot-routing/netlify/edge-functions/prerender-bots.js',
      'doc/hosting/cloudflare/bot-routing/functions/_middleware.js',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source, contains('googlebot|google-inspectiontool|bingbot'));
      expect(source, contains('function prettyDir'));
      expect(source, contains('/__prerendered'), reason: path);
    }
  });

  test('Netlify overlay is a 200 rewrite to index.html', () {
    final toml = File(
      'doc/hosting/netlify/overlay/netlify.toml',
    ).readAsStringSync();
    expect(toml, contains('publish = "deploy"'));
    expect(toml, contains('from = "/*"'));
    expect(toml, contains('to = "/index.html"'));
    expect(toml, contains('status = 200'));
    expect(toml, isNot(contains('edge_functions')));
  });

  test('copy-paste files sit where the guide links them', () {
    const expected = [
      'doc/hosting/firebase/overlay/firebase.json',
      'doc/hosting/firebase/bot-routing/firebase.json',
      'doc/hosting/firebase/bot-routing/functions/index.js',
      'doc/hosting/netlify/overlay/netlify.toml',
      'doc/hosting/netlify/bot-routing/netlify.toml',
      'doc/hosting/netlify/bot-routing/netlify/edge-functions/prerender-bots.js',
      'doc/hosting/cloudflare/bot-routing/_redirects',
      'doc/hosting/cloudflare/bot-routing/_routes.json',
      'doc/hosting/cloudflare/bot-routing/functions/_middleware.js',
    ];
    final guide = File('doc/serving.md').readAsStringSync();
    for (final path in expected) {
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(guide, contains(p.posix.joinAll(p.split(path))), reason: path);
    }
  });
}
