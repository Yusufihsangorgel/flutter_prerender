import 'package:args/args.dart';
import 'package:flutter_prerender/src/cli.dart';
import 'package:test/test.dart';

/// The flag and option names are this tool's public contract.
///
/// Everything else here is a Dart API that a compiler complains about when it
/// moves. These are strings in somebody's CI file, and renaming one breaks
/// every pipeline that uses it while looking like a patch. Nothing named
/// `buildParser` in the suite before this, so the whole surface could have
/// drifted a word at a time without a single test going red.
///
/// Adding to these lists is fine. Removing from them, or renaming, is a major.
void main() {
  const options = {
    'base-url',
    'build-dir',
    'chrome',
    'config',
    'max-pages',
    'out',
    'parity-threshold',
    'port',
    'routes',
    'wait',
  };
  const flags = {
    'app-script',
    'crawl',
    'dry-run',
    'fail-on-empty',
    'fail-on-parity',
    'help',
    'parity',
    'robots',
    'sitemap',
    'verbose',
    'version',
  };
  const abbreviations = {
    'b': 'build-dir',
    'c': 'config',
    'h': 'help',
    'o': 'out',
    'r': 'routes',
    'v': 'verbose',
  };

  group('the command line', () {
    test('takes exactly the options it took before', () {
      final parser = buildParser();
      final actual = {
        for (final e in parser.options.entries)
          if (!e.value.isFlag) e.key,
      };
      expect(actual, options);
    });

    test('takes exactly the flags it took before', () {
      final parser = buildParser();
      final actual = {
        for (final e in parser.options.entries)
          if (e.value.isFlag) e.key,
      };
      expect(actual, flags);
    });

    test('short forms still point at the same long ones', () {
      // `-o` moving to another option is worse than it disappearing: a script
      // keeps running and writes somewhere else.
      final parser = buildParser();
      final actual = {
        for (final e in parser.options.entries)
          if (e.value.abbr != null) e.value.abbr!: e.key,
      };
      expect(actual, abbreviations);
    });
  });

  group('parsing', () {
    test('a long and a short form give the same result', () {
      expect(
        buildParser().parse(['--out', 'build/x'])['out'],
        buildParser().parse(['-o', 'build/x'])['out'],
      );
    });

    test('an unknown option is rejected rather than ignored', () {
      // Silently dropping a typo is how a nightly job quietly stops
      // prerendering while still exiting zero.
      expect(
        () => buildParser().parse(['--no-such-thing']),
        throwsA(isA<FormatException>()),
      );
    });

    test('the switches that cannot be negated still cannot be', () {
      // `--no-version` is not a thing anyone means, and `--no-dry-run` reading
      // as "actually write" would be a bad way to find out.
      for (final name in [
        'crawl',
        'dry-run',
        'verbose',
        'help',
        'version',
        'fail-on-empty',
        'fail-on-parity',
      ]) {
        expect(
          () => buildParser().parse(['--no-$name']),
          throwsA(isA<FormatException>()),
          reason: '--no-$name should not parse',
        );
      }
    });

    test('the switches that can be negated still can', () {
      for (final name in ['sitemap', 'robots', 'parity', 'app-script']) {
        final parsed = buildParser().parse(['--no-$name']);
        expect(
          parsed.flag(name),
          isFalse,
          reason: '--no-$name should turn it off',
        );
      }
    });

    test('an option that wants a value complains without one', () {
      expect(
        () => buildParser().parse(['--out']),
        throwsA(isA<FormatException>()),
      );
    });

    test('usage text mentions every flag and option', () {
      // The parser is also the documentation: a switch with no help line is
      // one nobody will find.
      //
      // `args` renders a negatable flag as `--[no-]sitemap` and a
      // non-negatable one as `--crawl`, so asserting on the bare form alone
      // fails on the four that can be turned off. That is the renderer's
      // convention, not a missing help line.
      final usage = buildParser().usage;
      for (final name in {...options, ...flags}) {
        expect(
          usage,
          anyOf(contains('--$name'), contains('--[no-]$name')),
          reason: '$name is undocumented',
        );
      }
    });
  });

  test('buildParser hands back a fresh parser each time', () {
    // Callers parse more than once -- the CLI reads argv, tests read fixtures.
    // A shared ArgParser would carry one call's results into the next.
    final first = buildParser();
    final second = buildParser();
    expect(identical(first, second), isFalse);
    expect(first, isA<ArgParser>());
  });
}
