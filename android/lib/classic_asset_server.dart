import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

typedef ClassicLoader = Future<ByteData> Function(String path);

class ClassicAssetServer {
  ClassicAssetServer({ClassicLoader? loader, this.port = 18867})
    : loader = loader ?? rootBundle.load;
  final ClassicLoader loader;
  final int port;
  HttpServer? _server;
  Uri get origin => Uri.parse('http://127.0.0.1:${_server!.port}/');
  Future<void> start() async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _server!.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (!['GET', 'HEAD'].contains(request.method)) {
        request.response.statusCode = 405;
        await request.response.close();
        return;
      }
      if (request.uri.pathSegments.any(
        (part) =>
            part == '..' || part.contains('\\') || part.contains('\u0000'),
      )) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }
      final path = request.uri.path == '/'
          ? 'index.html'
          : request.uri.pathSegments.join('/');
      final bytes = await loader('assets/classic/$path');
      final ext = path.split('.').last.toLowerCase();
      const types = {
        'html': 'text/html; charset=utf-8',
        'js': 'application/javascript; charset=utf-8',
        'css': 'text/css; charset=utf-8',
        'json': 'application/json; charset=utf-8',
        'svg': 'image/svg+xml',
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'woff2': 'font/woff2',
        'mp3': 'audio/mpeg',
      };
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        types[ext] ?? 'application/octet-stream',
      );
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method != 'HEAD') {
        request.response.add(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    } catch (_) {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }
}
