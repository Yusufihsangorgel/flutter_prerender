import 'dart:io';

import 'package:path/path.dart' as p;

/// A minimal static file server used to serve a `flutter build web` directory
/// to the headless browser during prerendering.
///
/// Unknown paths fall back to `index.html` so that client-side routes resolve
/// (the browser loads `/some/route`, Flutter boots from `index.html`, and its
/// router navigates to the requested path). Requests that try to escape the
/// served directory are rejected.
class StaticServer {
  StaticServer._(this._server, this.rootDir);

  final HttpServer _server;

  /// The absolute path of the directory being served.
  final String rootDir;

  /// The base URL the server is listening on, for example
  /// `http://127.0.0.1:53421/`.
  Uri get baseUri =>
      Uri.parse('http://${_server.address.host}:${_server.port}/');

  /// Binds a [StaticServer] serving [rootDir].
  ///
  /// [port] `0` selects a free port. [host] defaults to loopback.
  static Future<StaticServer> start(
    String rootDir, {
    int port = 0,
    String host = '127.0.0.1',
  }) async {
    final absoluteRoot = p.normalize(p.absolute(rootDir));
    final server = await HttpServer.bind(host, port);
    final instance = StaticServer._(server, absoluteRoot);
    server.listen(instance._handle);
    return instance;
  }

  /// Stops the server and releases its port.
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final resolved = resolveWithinRoot(rootDir, request.uri.path);
    File? file;
    if (resolved != null) {
      final candidate = File(resolved);
      if (candidate.existsSync()) {
        file = candidate;
      }
    }
    file ??= File(p.join(rootDir, 'index.html'));
    if (!file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    response.headers.contentType = ContentType.parse(contentTypeFor(file.path));
    await response.addStream(file.openRead());
    await response.close();
  }
}

/// Resolves [requestPath] against [rootDir], returning an absolute file path,
/// or `null` if the path would escape [rootDir] (a traversal attempt).
String? resolveWithinRoot(String rootDir, String requestPath) {
  final root = p.normalize(p.absolute(rootDir));
  var relative = Uri.decodeComponent(requestPath);
  if (relative.startsWith('/')) relative = relative.substring(1);
  if (relative.isEmpty) relative = 'index.html';
  final resolved = p.normalize(p.join(root, relative));
  if (resolved != root && !p.isWithin(root, resolved)) {
    return null;
  }
  return resolved;
}

/// Returns the MIME type for [filePath] based on its extension, defaulting to
/// `application/octet-stream`.
String contentTypeFor(String filePath) {
  switch (p.extension(filePath).toLowerCase()) {
    case '.html':
    case '.htm':
      return 'text/html; charset=utf-8';
    case '.js':
    case '.mjs':
      return 'text/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.wasm':
      return 'application/wasm';
    case '.xml':
      return 'application/xml; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.gif':
      return 'image/gif';
    case '.ico':
      return 'image/x-icon';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    case '.ttf':
      return 'font/ttf';
    default:
      return 'application/octet-stream';
  }
}
