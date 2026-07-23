/// Base class for all errors thrown by flutter_prerender.
///
/// Catching [PrerenderException] lets callers handle every failure mode of the
/// tool with a single `catch` clause while still exposing a human-readable
/// [message].
class PrerenderException implements Exception {
  /// Creates a [PrerenderException] with a human-readable [message].
  const PrerenderException(this.message);

  /// A description of what went wrong, suitable for printing to a terminal.
  final String message;

  @override
  String toString() => 'PrerenderException: $message';
}

/// Thrown when a configuration file or route list cannot be parsed.
final class ConfigException extends PrerenderException {
  /// Creates a [ConfigException] with a human-readable [message].
  const ConfigException(super.message);

  @override
  String toString() => 'ConfigException: $message';
}

/// Thrown when the Flutter web build directory is missing or incomplete.
final class BuildNotFoundException extends PrerenderException {
  /// Creates a [BuildNotFoundException] with a human-readable [message].
  const BuildNotFoundException(super.message);

  @override
  String toString() => 'BuildNotFoundException: $message';
}

/// Thrown when the headless browser cannot be launched (for example, when no
/// Chrome/Chromium executable can be found or downloaded).
final class BrowserLaunchException extends PrerenderException {
  /// Creates a [BrowserLaunchException] with a human-readable [message].
  const BrowserLaunchException(super.message);

  @override
  String toString() => 'BrowserLaunchException: $message';
}

/// Thrown when a route cannot be captured, for example when the page never
/// produces a Flutter semantics tree within the configured timeout.
final class RouteCaptureException extends PrerenderException {
  /// Creates a [RouteCaptureException] for [route] with a human-readable
  /// [message].
  const RouteCaptureException(this.route, String message) : super(message);

  /// The route path that failed to capture.
  final String route;

  @override
  String toString() => 'RouteCaptureException($route): $message';
}
