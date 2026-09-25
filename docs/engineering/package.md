# Package engineering rules: flutter_prerender

Rules-Version: flutter_prerender/d2b17515a248476cd02271055bada0659e7f278396c8fc0684aebd48a79f8d7f
Core-Version: 1
Core-Digest: 1825fa7ff346dca23e65b1b3bf9b2e3e06959f1414bae9952d596d2f62f09b8f
Survey-Digest: f90f45c8a172068c3ed3b9488ba5a7cb4e58efa93c380d2d9a70b399349ec35e
Evidence-Revision: 3e32dd8
Verified-Revision: unverified

Read CONTRIBUTING.md and docs/engineering/debt.json before editing.

## Current architecture
HEAD 3e32dd8 (2026-08-30), v1.5.0, sdk ^3.9.0 (tall style), dependencies args, html, path, puppeteer, yaml; `executables: flutter_prerender`; the repository also carries a composite GitHub Action (action.yml) and hosting configurations (doc/hosting). CLI + library, pipeline architecture: bin → `runCli` (cli.dart, composition root: argument parsing, YAML→flag layering, starts the StaticServer, sets up the PuppeteerCapturer, maps exceptions to exit codes) → `PrerenderEngine.run` (engine.dart, orchestrator: capture per route → SemanticsExtractor → HtmlBuilder → ParityGuard → write file; BFS discovery in crawl mode; sitemap/robots). The browser is isolated behind the `PageCapturer` interface (the single puppeteer import is browser.dart). The transformation steps are pure and browser-free, tested with fixtures. `ContentNode` is sealed, switches are exhaustive. The barrel exports all 15 src files without `show`. 15 files, ~2,300 lines: no subdirectories but the implicit layers are clear.

## Layers and responsibilities
- bin/flutter_prerender.dart: `exitCode = await runCli(args)` (lines 6-8).
- lib/src/cli.dart: ArgParser, configuration resolution (file + flags), dry-run plan, summary, exit codes, default capturer factory, `packageVersion`.
- lib/src/config.dart, lib/src/route_meta.dart, lib/src/routes.dart: `PrerenderConfig`/`RouteSpec` (YAML→typed, copyWith), `RouteMeta` (merge), routes file parsing, normalization (traversal protection), same-origin discovery.
- lib/src/engine.dart: `PrerenderEngine`, `RouteResult`, `FailedRoute`, `PrerenderResult`; crawl queue, duplicate content signature, parity, file writing, sitemap/robots.
- lib/src/browser.dart: `PageCapturer` interface, `CapturedPage`, `PuppeteerCapturer` (Chrome launch, enabling the semantics tree, capture).
- lib/src/{semantics_extractor,content_node,html_builder,parity,sitemap,robots,source_head}.dart: Semantic DOM→ContentNode, static HTML generation, parity report, sitemap/robots text, tags to carry over from the build's head.
- lib/src/static_server.dart: Serving the build directory with HttpServer, fallback to index.html, traversal rejection, MIME table.
- lib/src/exceptions.dart: `PrerenderException` (non-final base) + ConfigException, BuildNotFoundException, BrowserLaunchException, RouteCaptureException.
- action.yml, doc/hosting/, tool/: Composite Action inputs (lines 11-78), hosting routing examples, measurement/figure scripts.

## Public API and dependency direction
The barrel exports all src files without `show` (lib/flutter_prerender.dart:17-31): runCli, buildParser, packageVersion, defaultConfigFile, PrerenderConfig, RouteSpec, RouteMeta, PrerenderEngine, RouteResult, FailedRoute, PrerenderResult, PageCapturer, PuppeteerCapturer, CapturedPage, SemanticsExtractor, ContentNode (+HeadingContent, ParagraphContent, LinkContent, ImageContent), HtmlBuilder, ParityGuard, ParityReport, buildSitemap, SitemapEntry, joinUrl, buildRobotsTxt, SourceHead, StaticServer, resolveWithinRoot, contentTypeFor, parseRoutesFile, normalizeRoute, sameOriginRoute, discoverRoutes, five exceptions. Public contracts outside the library: CLI flags (cli.dart:22-99), exit codes 0/1/2/3/4/64 (cli.dart:123, 157, 264, 270, 278), action.yml inputs, YAML keys (config.dart:81-104).

cli → {engine, config, browser, static_server, routes, source_head, exceptions, args, path, dart:io}; engine → {browser (only PageCapturer/CapturedPage), config, content_node, exceptions, html_builder, parity, robots, routes, semantics_extractor, sitemap, source_head, path, dart:io}; config → {route_meta, routes, exceptions, yaml}; html_builder → {content_node, route_meta}; semantics_extractor → {content_node, html}; browser → {exceptions, puppeteer}; routes → exceptions; source_head → html; static_server → {path, dart:io}. Leaves: content_node, route_meta, parity, sitemap, robots, exceptions. engine does not import static_server or cli. dart:io only in cli/engine/static_server; puppeteer only in browser; yaml only in config; args only in cli. No cycles.

## Error, state and platform contracts
- Interface seam for the external process boundary: `PageCapturer` + `capturerFactory` injection in runCli and in the engine constructor (browser.dart:26-37; cli.dart:103-112, 235; engine.dart:132-148); tests use a fake capturer (cli_test, crawl_test, engine_test).
- sealed `ContentNode` + exhaustive switch (content_node.dart:6; html_builder.dart:205-214; engine.dart:415-422).
- Typed configuration helpers throw ConfigException naming the key (config.dart:262-288); the YAML map is normalized to `Map<String, Object?>`.
- Immutable value objects with const constructors; equality/hashCode on ContentNode subtypes.
- Output via an injected `StringSink` and a `log` callback; `avoid_print` is on (cli.dart:107-114; engine.dart:166).
- Path traversal protection at three layers (routes.dart:50-61; engine.dart:391-401; static_server.dart:65-77).
- Warnings are accumulated as String and carried in result objects; the exit code mapping lives in runCli.
- Version drift test (cli.dart:14-16 ↔ test/cli_test.dart:89-98).
- Relative imports and directives_ordering inside lib (analysis_options).
- No platform checks; no FFI; VM + dart:io CLI; Chrome is an external process (puppeteer).
- Long rationale comments on non-obvious decisions (engine.dart:142-146, 245-247; source_head.dart:4-15).

## Package rules
### flutter_prerender/FPR-1 [MUST]
Keep `package:puppeteer` and every Chrome detail inside lib/src/browser.dart behind `PageCapturer`. The engine and the pure modules depend on the interface; new capture behavior goes into `PuppeteerCapturer`.
Reason: The interface exists to make the rest of the pipeline testable without a browser (browser.dart:28-29); it is the package's single external-process seam under DIP.
Evidence: lib/src/browser.dart:1, 26-37; lib/src/engine.dart:132-154, 295; lib/src/cli.dart:111, 235, 287-290; import graph (puppeteer only browser.dart)
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-2 [MUST]
Keep the transformation modules pure: semantics_extractor, content_node, html_builder, parity, sitemap, robots, source_head, route_meta and routes take values and return values, with no `dart:io` and no browser. Each has a fixture-based unit test.
Reason: semantics_extractor.dart:16-17 says 'deliberately no browser dependency, fully unit testable'; every module has its own test file.
Evidence: lib/src/semantics_extractor.dart:16-17; import graph; test/{semantics_extractor,html_builder,parity,sitemap,robots,source_head,routes}_test.dart
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-3 [MUST]
Confine file system and network I/O to cli.dart, engine.dart and static_server.dart.
Reason: dart:io appears today only in these three files; the pure modules keep the boundary.
Evidence: lib/src/cli.dart:1; lib/src/engine.dart:2; lib/src/static_server.dart:1
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-4 [MUST]
`ContentNode` stays sealed. A new node type is handled in every exhaustive switch (`HtmlBuilder._renderNode`, `PrerenderEngine._signature`) and gets extractor and builder tests.
Reason: The sealed type breaks compilation on a new kind (same spirit as shared J1 P-GELECEK); the two switches are exhaustive today.
Evidence: lib/src/content_node.dart:6; lib/src/html_builder.dart:205-214; lib/src/engine.dart:415-422
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-5 [MUST]
Report user-facing failures as `PrerenderException` subtypes. `runCli` turns them into `Error: <message>` and an exit code; config parsing must not let a `TypeError` or `FormatException` escape.
Reason: runCli catches only PrerenderException; any other type crashes with a stack trace. route_meta.dart violates this today (debt FPR-B1).
Evidence: lib/src/exceptions.dart:1-57; lib/src/cli.dart:117-124, 155-158; lib/src/config.dart:48-64, 262-288; ihlal lib/src/route_meta.dart:23-27
Evidence role: both
Existing violation: flutter_prerender-D001

### flutter_prerender/FPR-6 [MUST]
Add a config key everywhere at once: the `PrerenderConfig` field and constructor default, `fromMap` through the typed helpers, `copyWith` and a CLI flag when it can be overridden, an action.yml input when the action exposes it, and a test in config_test.dart or cli_test.dart.
Reason: One key lives on four surfaces; if one is forgotten, YAML, flags and the action silently diverge.
Evidence: lib/src/config.dart:25-106, 189-231; lib/src/cli.dart:22-99, 187-208; action.yml:11-78
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-7 [MUST]
Treat exit codes as a public contract: 0 success, 1 `PrerenderException`, 2 parity failure, 3 empty or failed route, 4 every route collapsed onto /, 64 bad usage. Never renumber them; a new failure mode gets a new documented code.
Reason: In CI and in the composite action users branch on the code; today the numbers are scattered literals (debt FPR-B6).
Evidence: lib/src/cli.dart:123, 132, 136, 157, 264, 270, 278, 280
Evidence role: current-pattern
Existing violation: flutter_prerender-D006

### flutter_prerender/FPR-8 [MUST]
Send every path that is written or served through the traversal guards: `normalizeRoute`, the `p.isWithin` check in `_writeRoute`, and `resolveWithinRoot`.
Reason: Routes are written to disk and the local server serves files; the three layers of protection are deliberate (engine.dart:394-396 'defence in depth').
Evidence: lib/src/routes.dart:50-61; lib/src/engine.dart:391-401; lib/src/static_server.dart:65-77
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-9 [MUST]
Every public top-level name in lib/src is public API because lib/flutter_prerender.dart exports all of its files without `show`. Make a helper private with `_` unless users are meant to call it.
Reason: The current export model is file-based; a new helper enters the semver surface automatically (debt FPR-B2).
Evidence: lib/flutter_prerender.dart:17-31
Evidence role: counterexample
Existing violation: flutter_prerender-D002

### flutter_prerender/FPR-10 [MUST]
Keep `packageVersion` in lib/src/cli.dart equal to the pubspec version; test/cli_test.dart enforces it.
Reason: The `--version` output must match the pubspec; a drift test exists.
Evidence: lib/src/cli.dart:14-16; test/cli_test.dart:89-98
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-11 [MUST]
Tag every test that needs Chrome or a built example with `@Tags(['e2e'])`. Everything else runs without a browser through a fake `PageCapturer`.
Reason: The CI `test` job excludes e2e; an untagged browser test breaks CI.
Evidence: dart_test.yaml; test/e2e_test.dart:1; test/cli_test.dart, test/crawl_test.dart, test/engine_test.dart (implements PageCapturer); .github/workflows/ci.yaml `--exclude-tags e2e`
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-12 [SHOULD]
Write output through the injected `StringSink` or the `log` callback, never `print`.
Reason: Tests capture output with an injected sink; avoid_print is enabled.
Evidence: lib/src/cli.dart:103-114; lib/src/engine.dart:166; analysis_options.yaml avoid_print
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-13 [SHOULD]
Prove a change to action.yml through the CI `action` job, which runs the composite action against example/.
Reason: The CI comment: correct bash does not mean the action works; the difference shows up only here.
Evidence: .github/workflows/ci.yaml `action` job
Evidence role: current-pattern
Existing violation: none

### flutter_prerender/FPR-14 [SHOULD]
Escape at the builder boundary: element text, attribute values, XML values, and `<` inside JSON-LD.
Reason: Route metadata and semantic text are external input; the output is embedded in HTML/XML.
Evidence: lib/src/html_builder.dart:161-171, 216-225; lib/src/sitemap.dart:68-73
Evidence role: current-pattern
Existing violation: none

## Required verification
- Working directory: repository root; command: dart pub get --no-example; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:23.
- Working directory: repository root; command: dart format --output=none --set-exit-if-changed lib test bin; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:25.
- Working directory: repository root; command: dart analyze --fatal-infos lib test bin; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:27.
- Working directory: repository root; command: dart test --exclude-tags e2e; conditions: ci.yaml job test; evidence: .github/workflows/ci.yaml:29.
- Working directory: example; command: flutter pub get; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:44.
- Working directory: example; command: flutter build web; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:45.
- Working directory: repository root; command: dart pub get; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:51.
- Working directory: repository root; command: dart pub global activate --source path .; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:52.
- Working directory: repository root; command: echo "$HOME/.pub-cache/bin" >> "$GITHUB_PATH"; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:53.
- Working directory: repository root; command: set -euo pipefail; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:68.
- Working directory: repository root; command: test -f example/build/prerendered/index.html; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:69.
- Working directory: repository root; command: test -f example/build/prerendered/sitemap.xml; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:70.
- Working directory: repository root; command: # The point of the tool: text a crawler can read, not an empty canvas.; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:71.
- Working directory: repository root; command: grep -q "<h1" example/build/prerendered/index.html; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:72.
- Working directory: repository root; command: echo "prerendered $(find example/build/prerendered -name '*.html' | wc -l) page(s)"; conditions: ci.yaml job action; evidence: .github/workflows/ci.yaml:73.
Not verified by the survey:
- I did not run `dart analyze` and `dart test` (read-only); e2e and the CI `action` job were not run. FPR-B1 is certain from reading (cast semantics), FPR-B8 triggering was not measured.
- tool/*.dart (415 lines), example/lib/main.dart and example/what_a_crawler_sees.dart, doc/hosting/* and the action.yml `runs:` steps were not read; only input names from action.yml.
- README.md content was not read; only an 'exit code' grep (0 hits). AGENTS.md headings: What it is, Invocation, Contracts, Mistakes, Layout (185 lines).
- There are untracked empty `-` and `p` directories at the repository root (2026-08-30 00:18); they do not enter git.
- GitHub Actions latest run result and pub.dev score (network not permitted).
- Whether the shared detectors (kod-kapisi.py) run on this package: the filter depends on the dart_mcp path (dart-kod-kurallari.md:130-133); I did not open the script.

## Existing debt
The complete register is docs/engineering/debt.json.
- flutter_prerender-D001 | small | lib/src/route_meta.dart:23-27 (↔ lib/src/config.dart:50-51; lib/src/cli.dart:155) | error contract / correctness
  Fix: Move the typed helpers into shared private functions (or have RouteMeta.fromMap throw a ConfigException that names the key); add wrong-type tests for defaults and below routes.
  Closure: RouteMeta.fromMap throws a ConfigException naming the offending key for wrong-typed values. New wrong-type tests for defaults and below routes pass.
- flutter_prerender-D002 | medium | lib/flutter_prerender.dart:17-31 | leaking public API
  Fix: Now add `show` lists that enumerate the current set exactly (non-breaking) and stop the leak; deprecate the accidentally public helpers and remove them in the next major.
  Closure: lib/flutter_prerender.dart exports each file through a show list that names exactly the intended public set. The accidentally public helpers carry deprecation notes for removal in the next major.
- flutter_prerender-D003 | small | lib/src/engine.dart:112-118 ↔ 324-331 | string-typed coupling
  Fix: Add a `duplicateOf` (String?) field to RouteResult set at 322-334; the getter reads it; engine_test already pins the current behavior.
  Closure: RouteResult carries a duplicateOf field set where duplicates are detected and collapsedOntoRoot reads that field instead of warning text. engine_test still passes.
- flutter_prerender-D004 | medium | lib/src/engine.dart:166-271, 283-291 | SRP / cognitive complexity (J2)
  Fix: A private `_RunState` (results, failedRoutes, signatureToRoute); extract `_crawl`, `_writeSitemap`, `_writeRobots`. Behavior stays pinned by engine_test and crawl_test.
  Closure: engine.run delegates to extracted _crawl, _writeSitemap and _writeRobots methods over a private _RunState and _renderRoute takes no mutable accumulators. engine_test and crawl_test still pass.
- flutter_prerender-D005 | small | lib/src/config.dart:26-45 ↔ 81-100; lib/src/browser.dart:48; lib/src/html_builder.dart:22-24; lib/src/parity.dart:72 | duplicated defaults
  Fix: Have fromMap fall back to the fields of a single `const PrerenderConfig()` instance; have the engine pass every value explicitly.
  Closure: fromMap falls back to the defaults of one const PrerenderConfig() and the engine passes every value explicitly. config_test still passes.
- flutter_prerender-D006 | small | lib/src/cli.dart:123, 157, 264, 270, 278 | magic number / contract documentation
  Fix: Named constants with dartdoc in one place; a table in the README.
  Closure: Exit codes live in named constants with dartdoc in one place and the README documents the table. cli_test still passes.
- flutter_prerender-D007 | small | lib/src/browser.dart:99, 165, 168 | unjustified operating constant (J5/D1)
  Fix: A named `static const` with a one-sentence rationale; state why the sandbox flag is needed or make it configurable.
  Closure: browser.dart declares the polling delays as named static const values with a one-sentence rationale. The sandbox flag is justified in a comment or made configurable.
- flutter_prerender-D008 | small | lib/src/static_server.dart:36, 43-62 | unlistened async error (PLAUSIBLE)
  Fix: Wrap the handler body with `on IOException`/`on HttpException` and close the response silently; extend static_server_test with a cancelled request.
  Closure: The static server handler wraps its body with on IOException and on HttpException and closes the response quietly. static_server_test covers a cancelled request.
- flutter_prerender-D009 | small | lib/src/html_builder.dart:216-225 ↔ lib/src/sitemap.dart:68-73 | duplication / ecosystem equivalent (J7)
  Fix: Use HtmlEscape for HTML. Keep the XML escape: HtmlEscape writes the apostrophe as &#39;, not &apos;; example/expected_output pins the output.
  Closure: html_builder escapes HTML through dart:convert HtmlEscape and keeps the XML escape for the apostrophe. example/expected_output and the builder tests still match.
- flutter_prerender-D010 | small | .github/workflows/ci.yaml (format and analyze on `lib test bin`); analysis_options.yaml `exclude: example/**` | CI gap
  Fix: Add `tool` to the format/analyze paths; move the pure Dart example outside the excluded tree or analyze it in the action job.
  Closure: CI runs format and analyze over tool in addition to lib test bin. The pure Dart example is analyzed in place or by the action job.
- flutter_prerender-D011 | small | lib/src/browser.dart:75 ↔ lib/src/semantics_extractor.dart:30 | duplication
  Fix: A single internal constant; both files use it.
  Closure: One internal constant holds the Enable accessibility label and both browser.dart and semantics_extractor.dart use it.
