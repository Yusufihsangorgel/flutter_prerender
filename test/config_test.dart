import 'package:flutter_prerender/flutter_prerender.dart';
import 'package:test/test.dart';

void main() {
  test('empty document yields defaults', () {
    final config = PrerenderConfig.fromYaml('');
    expect(config.buildDir, 'build/web');
    expect(config.outDir, 'build/prerendered');
    expect(config.generateSitemap, isTrue);
    expect(config.parityCheck, isTrue);
    expect(config.routes, isEmpty);
  });

  test('parses a full config with routes and defaults', () {
    const yaml = '''
buildDir: web
out: out/pre
baseUrl: https://coffee.example.com
lang: en
parity:
  enabled: true
  threshold: 0.85
  failOn: true
defaults:
  ogType: website
  image: https://coffee.example.com/og.png
routes:
  - path: /
    title: Home
    description: Welcome
  - /about
''';
    final config = PrerenderConfig.fromYaml(yaml);
    expect(config.buildDir, 'web');
    expect(config.outDir, 'out/pre');
    expect(config.baseUrl, 'https://coffee.example.com');
    expect(config.parityThreshold, 0.85);
    expect(config.failOnParity, isTrue);
    expect(config.defaults.ogType, 'website');
    expect(config.routes, hasLength(2));
    expect(config.routes.first.path, '/');
    expect(config.routes.first.meta.title, 'Home');
    expect(config.routes[1].path, '/about');
  });

  test('route meta merges over document defaults', () {
    const yaml = '''
defaults:
  description: default description
  image: https://x.com/default.png
routes:
  - path: /
    title: Home
''';
    final config = PrerenderConfig.fromYaml(yaml);
    final merged = config.routes.first.meta.merge(config.defaults);
    expect(merged.title, 'Home');
    expect(merged.description, 'default description');
    expect(merged.image, 'https://x.com/default.png');
  });

  test('parses nested JSON-LD into a plain map', () {
    const yaml = '''
routes:
  - path: /
    jsonLd:
      "@context": https://schema.org
      "@type": Organization
      name: Coffee
''';
    final config = PrerenderConfig.fromYaml(yaml);
    final jsonLd = config.routes.first.meta.jsonLd;
    expect(jsonLd, isNotNull);
    expect(jsonLd!['@type'], 'Organization');
    expect(jsonLd['name'], 'Coffee');
  });

  test('throws ConfigException on a non-mapping root', () {
    expect(
      () => PrerenderConfig.fromYaml('- just\n- a\n- list'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('throws ConfigException when a field has the wrong type', () {
    expect(
      () => PrerenderConfig.fromYaml('buildDir: [not, a, string]'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('parity accepts a boolean shorthand', () {
    final config = PrerenderConfig.fromYaml('parity: false');
    expect(config.parityCheck, isFalse);
  });

  test('parity mapping still configures threshold and failOn', () {
    final config = PrerenderConfig.fromYaml(
      'parity:\n  enabled: true\n  threshold: 0.7',
    );
    expect(config.parityCheck, isTrue);
    expect(config.parityThreshold, 0.7);
  });

  test('rejects a parity value that is neither bool nor mapping', () {
    expect(
      () => PrerenderConfig.fromYaml('parity: 3'),
      throwsA(isA<ConfigException>()),
    );
  });

  test('failOnEmpty parses from the config', () {
    expect(PrerenderConfig.fromYaml('failOnEmpty: true').failOnEmpty, isTrue);
    expect(const PrerenderConfig().failOnEmpty, isFalse);
  });

  test('copyWith overrides only the provided fields', () {
    const base = PrerenderConfig(buildDir: 'a', outDir: 'b', waitMs: 1000);
    final updated = base.copyWith(buildDir: 'c', failOnParity: true);
    expect(updated.buildDir, 'c');
    expect(updated.outDir, 'b');
    expect(updated.waitMs, 1000);
    expect(updated.failOnParity, isTrue);
  });
}
