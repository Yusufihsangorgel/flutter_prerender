import 'package:puppeteer/puppeteer.dart';

import 'exceptions.dart';

/// The raw material recovered from one loaded route: the document title, the
/// serialised Flutter semantics DOM, and the app's rendered text.
final class CapturedPage {
  /// Creates a [CapturedPage].
  const CapturedPage({
    required this.title,
    required this.semanticsHtml,
    required this.renderedText,
  });

  /// The value of `document.title` after the app booted.
  final String title;

  /// The outer HTML of `<flt-semantics-host>`, or the empty string if the app
  /// exposed no semantics tree.
  final String semanticsHtml;

  /// The app's rendered `document.body.innerText`, used by the parity guard.
  final String renderedText;
}

/// Loads a route in a real browser and captures its content.
///
/// This interface isolates the (Chrome-dependent) capture step so the rest of
/// the pipeline can be unit-tested with fixtures instead of a live browser.
abstract interface class PageCapturer {
  /// Loads [url], forces the Flutter accessibility tree on, and returns the
  /// captured page.
  Future<CapturedPage> capture(Uri url);

  /// Releases any browser resources.
  Future<void> close();
}

/// A [PageCapturer] backed by `package:puppeteer` and headless Chrome.
final class PuppeteerCapturer implements PageCapturer {
  /// Creates a capturer.
  ///
  /// [executablePath] points at a Chrome/Chromium binary; when `null`,
  /// `package:puppeteer` downloads and manages its own copy. [extraWaitMs] is
  /// an additional settle delay after the semantics tree appears.
  PuppeteerCapturer({
    this.executablePath,
    this.extraWaitMs = 4000,
    this.navigationTimeout = const Duration(seconds: 60),
    this.semanticsTimeout = const Duration(seconds: 30),
    this.userAgent = _googlebotUserAgent,
  });

  /// Path to a Chrome/Chromium executable, or `null` to auto-download.
  final String? executablePath;

  /// Milliseconds to wait after the semantics tree appears.
  final int extraWaitMs;

  /// Maximum time to wait for a route to finish loading.
  final Duration navigationTimeout;

  /// Maximum time to wait for the Flutter semantics tree to appear.
  final Duration semanticsTimeout;

  /// The user agent sent for each request (Googlebot by default).
  final String userAgent;

  static const String _googlebotUserAgent =
      'Mozilla/5.0 (compatible; Googlebot/2.1; '
      '+http://www.google.com/bot.html)';

  static const String _enableAccessibilityJs =
      '() => { const b = document.querySelector('
      "'[aria-label=\"Enable accessibility\"]'); if (b) { b.click(); } }";

  static const String _innerTextLenJs =
      '() => (document.body && document.body.innerText '
      '? document.body.innerText.length : 0)';

  static const String _titleJs = '() => document.title';

  static const String _renderedTextJs =
      '() => document.body ? document.body.innerText : ""';

  static const String _semanticsJs =
      "() => { const h = document.querySelector('flt-semantics-host'); "
      'return h ? h.outerHTML : ""; }';

  Browser? _browser;

  Future<Browser> _ensureBrowser() async {
    final existing = _browser;
    if (existing != null) return existing;
    try {
      final browser = await puppeteer.launch(
        headless: true,
        executablePath: executablePath,
        args: const <String>['--no-sandbox'],
      );
      _browser = browser;
      return browser;
    } on Object catch (error) {
      throw BrowserLaunchException(
        'Could not launch Chrome. Pass --chrome with a path to a Chrome '
        'executable, or let package:puppeteer download one. Cause: $error',
      );
    }
  }

  @override
  Future<CapturedPage> capture(Uri url) async {
    final browser = await _ensureBrowser();
    final page = await browser.newPage();
    try {
      await page.setUserAgent(userAgent);
      await page.goto(
        url.toString(),
        wait: Until.networkIdle,
        timeout: navigationTimeout,
      );
      // networkIdle can fire before the Flutter app finishes booting, so wait
      // for the app's view element before touching the accessibility toggle.
      try {
        await page.waitForSelector(
          'flutter-view, flt-glass-pane',
          timeout: semanticsTimeout,
        );
      } on Object {
        // No Flutter view appeared; the emptiness check below will report it.
      }
      await _enableSemantics(page);
      if (extraWaitMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: extraWaitMs));
      }
      final title = (await page.evaluate<Object?>(_titleJs))?.toString() ?? '';
      final rendered =
          (await page.evaluate<Object?>(_renderedTextJs))?.toString() ?? '';
      final semantics =
          (await page.evaluate<Object?>(_semanticsJs))?.toString() ?? '';
      if (semantics.trim().isEmpty && rendered.trim().isEmpty) {
        throw RouteCaptureException(
          url.path,
          'No content was recovered. The page may not be a Flutter web app, '
          'or it failed to boot in the browser.',
        );
      }
      return CapturedPage(
        title: title,
        semanticsHtml: semantics,
        renderedText: rendered,
      );
    } finally {
      await page.close();
    }
  }

  /// Clicks the engine's "Enable accessibility" placeholder and polls until the
  /// semantics tree has populated the DOM with readable text.
  ///
  /// The click is retried because the placeholder may not be mounted the moment
  /// the app's view appears, and the tree fills in asynchronously.
  Future<void> _enableSemantics(Page page) async {
    final deadline = DateTime.now().add(semanticsTimeout);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    while (DateTime.now().isBefore(deadline)) {
      await page.evaluate<void>(_enableAccessibilityJs);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      final length = await page.evaluate<Object?>(_innerTextLenJs);
      final chars = length is num ? length.toInt() : 0;
      if (chars > 0) return;
    }
  }

  @override
  Future<void> close() async {
    await _browser?.close();
    _browser = null;
  }
}
