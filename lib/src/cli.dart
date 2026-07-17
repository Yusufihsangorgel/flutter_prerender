import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'browser.dart';
import 'config.dart';
import 'engine.dart';
import 'exceptions.dart';
import 'routes.dart';
import 'static_server.dart';

/// The published version of the package. Kept in sync with `pubspec.yaml`.
const String packageVersion = '0.1.0';

/// The default config file name looked up in the working directory.
const String defaultConfigFile = 'flutter_prerender.yaml';

/// Builds the command-line argument parser for the tool.
ArgParser buildParser() {
  return ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      help:
          'Path to a YAML config file. Defaults to $defaultConfigFile if '
          'present.',
    )
    ..addOption(
      'build-dir',
      abbr: 'b',
      help: 'Directory containing the `flutter build web` output.',
    )
    ..addOption(
      'routes',
      abbr: 'r',
      help: 'Path to a routes file (one route per line).',
    )
    ..addOption(
      'out',
      abbr: 'o',
      help: 'Output directory for prerendered HTML.',
    )
    ..addOption(
      'base-url',
      help: 'Public site origin, e.g. https://example.com.',
    )
    ..addOption('port', help: 'Static server port (0 selects a free port).')
    ..addOption('chrome', help: 'Path to a Chrome/Chromium executable.')
    ..addOption('wait', help: 'Extra settle wait, in milliseconds.')
    ..addOption(
      'parity-threshold',
      help: 'Minimum content similarity before a page is flagged (0.0-1.0).',
    )
    ..addFlag('sitemap', help: 'Write sitemap.xml (needs --base-url).')
    ..addFlag('app-script', help: 'Include the Flutter bootstrap script.')
    ..addFlag('parity', help: 'Run the content-parity guard.')
    ..addFlag(
      'fail-on-parity',
      negatable: false,
      help: 'Exit non-zero if any page fails the parity guard.',
    )
    ..addFlag(
      'fail-on-empty',
      negatable: false,
      help: 'Exit non-zero if any route recovers no content.',
    )
    ..addFlag(
      'dry-run',
      negatable: false,
      help: 'Print the plan and exit without launching a browser.',
    )
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addFlag('version', negatable: false, help: 'Show the version.');
}

/// Parses [args], runs the prerender, and returns a process exit code.
///
/// [out] and [err] default to [stdout] and [stderr] but can be overridden in
/// tests. [capturerFactory] builds the browser capturer; the default uses
/// [PuppeteerCapturer]. Injecting a fake capturer lets callers exercise the
/// full pipeline without Chrome.
Future<int> runCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
  PageCapturer Function(PrerenderConfig config)? capturerFactory,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final parser = buildParser();

  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (error) {
    stderrSink.writeln(error.message);
    stderrSink.writeln(parser.usage);
    return 64;
  }

  if (results.flag('help')) {
    stdoutSink.writeln(
      'Prerender a Flutter web app to static, crawlable HTML.',
    );
    stdoutSink.writeln('\nUsage: flutter_prerender [options]\n');
    stdoutSink.writeln(parser.usage);
    return 0;
  }
  if (results.flag('version')) {
    stdoutSink.writeln('flutter_prerender $packageVersion');
    return 0;
  }

  try {
    final config = await _resolveConfig(results);
    if (config.routes.isEmpty) {
      throw const ConfigException(
        'No routes to prerender. Provide --routes, or a "routes:" list in the '
        'config file.',
      );
    }
    return await _execute(
      config,
      results.flag('dry-run'),
      results.flag('verbose'),
      stdoutSink,
      stderrSink,
      capturerFactory,
    );
  } on PrerenderException catch (error) {
    stderrSink.writeln('Error: ${error.message}');
    return 1;
  }
}

Future<PrerenderConfig> _resolveConfig(ArgResults results) async {
  final configPath = results.option('config');
  var config = const PrerenderConfig();
  final file = configPath != null
      ? File(configPath)
      : (File(defaultConfigFile).existsSync() ? File(defaultConfigFile) : null);
  if (file != null) {
    if (!file.existsSync()) {
      throw ConfigException('Config file not found: ${file.path}');
    }
    config = PrerenderConfig.fromYaml(file.readAsStringSync());
  }

  List<RouteSpec>? routes;
  final routesPath = results.option('routes');
  if (routesPath != null) {
    final routesFile = File(routesPath);
    if (!routesFile.existsSync()) {
      throw ConfigException('Routes file not found: $routesPath');
    }
    routes = [
      for (final path in parseRoutesFile(routesFile.readAsStringSync()))
        RouteSpec(path),
    ];
  }

  return config.copyWith(
    buildDir: results.option('build-dir'),
    outDir: results.option('out'),
    baseUrl: results.option('base-url'),
    routes: routes,
    chromeExecutable: results.option('chrome'),
    port: _intOption(results, 'port'),
    waitMs: _intOption(results, 'wait'),
    parityThreshold: _doubleOption(results, 'parity-threshold'),
    generateSitemap: results.wasParsed('sitemap')
        ? results.flag('sitemap')
        : null,
    includeAppScript: results.wasParsed('app-script')
        ? results.flag('app-script')
        : null,
    parityCheck: results.wasParsed('parity') ? results.flag('parity') : null,
    failOnParity: results.flag('fail-on-parity') ? true : null,
    failOnEmpty: results.flag('fail-on-empty') ? true : null,
  );
}

Future<int> _execute(
  PrerenderConfig config,
  bool dryRun,
  bool verbose,
  StringSink out,
  StringSink err,
  PageCapturer Function(PrerenderConfig config)? capturerFactory,
) async {
  final buildDir = Directory(config.buildDir);
  final indexHtml = File(p.join(config.buildDir, 'index.html'));

  if (dryRun) {
    _printPlan(config, out, buildDir, indexHtml);
    return 0;
  }

  if (!buildDir.existsSync() || !indexHtml.existsSync()) {
    throw BuildNotFoundException(
      'No Flutter web build at "${config.buildDir}". Run `flutter build web` '
      'first, or pass --build-dir.',
    );
  }

  final server = await StaticServer.start(config.buildDir, port: config.port);
  final capturer = (capturerFactory ?? _defaultCapturer)(config);
  try {
    final engine = PrerenderEngine(config: config, capturer: capturer);
    final result = await engine.run(
      server.baseUri,
      log: verbose ? out.writeln : null,
    );
    _printSummary(result, out);
    for (final warning in result.allWarnings) {
      err.writeln('warning: $warning');
    }
    if (config.failOnParity && result.hasParityWarnings) {
      err.writeln(
        'Parity guard flagged one or more pages and --fail-on-parity is set.',
      );
      return 2;
    }
    if (config.failOnEmpty && result.hasEmptyRoutes) {
      err.writeln(
        'One or more routes recovered no content and --fail-on-empty is set.',
      );
      return 3;
    }
    return 0;
  } finally {
    await capturer.close();
    await server.close();
  }
}

PageCapturer _defaultCapturer(PrerenderConfig config) => PuppeteerCapturer(
  executablePath: config.chromeExecutable,
  extraWaitMs: config.waitMs,
);

void _printPlan(
  PrerenderConfig config,
  StringSink out,
  Directory buildDir,
  File indexHtml,
) {
  out.writeln('flutter_prerender $packageVersion (dry run)');
  out.writeln('  build dir:   ${config.buildDir}');
  out.writeln('  output dir:  ${config.outDir}');
  out.writeln('  base url:    ${config.baseUrl ?? '(none)'}');
  out.writeln('  sitemap:     ${config.generateSitemap}');
  out.writeln('  app script:  ${config.includeAppScript}');
  out.writeln(
    '  parity:      ${config.parityCheck} '
    '(threshold ${config.parityThreshold})',
  );
  if (!buildDir.existsSync() || !indexHtml.existsSync()) {
    out.writeln('  note:        build dir not found (run `flutter build web`)');
  }
  out.writeln('  routes (${config.routes.length}):');
  for (final spec in config.routes) {
    final title = spec.meta.merge(config.defaults).title;
    out.writeln('    ${spec.path}${title == null ? '' : '  ->  "$title"'}');
  }
}

void _printSummary(PrerenderResult result, StringSink out) {
  out.writeln('Prerendered ${result.routes.length} route(s):');
  for (final route in result.routes) {
    final parity = route.parity;
    final String flag;
    if (route.isEmpty) {
      flag = '  [empty: no content recovered]';
    } else if (parity == null) {
      flag = '';
    } else if (parity.isSuspicious) {
      flag = '  [parity: CHECK, sim ${parity.similarity.toStringAsFixed(2)}]';
    } else {
      flag = '  [parity ok]';
    }
    out.writeln(
      '  ${route.path}  '
      '${route.nodeCount} nodes, ${route.byteCount} bytes$flag',
    );
  }
  if (result.sitemapPath != null) {
    out.writeln('Sitemap: ${result.sitemapPath}');
  }
}

int? _intOption(ArgResults results, String name) {
  final value = results.option(name);
  if (value == null) return null;
  final parsed = int.tryParse(value);
  if (parsed == null) {
    throw ConfigException('--$name must be an integer, got "$value".');
  }
  return parsed;
}

double? _doubleOption(ArgResults results, String name) {
  final value = results.option(name);
  if (value == null) return null;
  final parsed = double.tryParse(value);
  if (parsed == null) {
    throw ConfigException('--$name must be a number, got "$value".');
  }
  return parsed;
}
