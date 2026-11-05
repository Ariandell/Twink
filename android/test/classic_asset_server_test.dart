import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twink_android/classic_asset_server.dart';

void main() {
  test(
    'Android serves bundled original pages with a stable local origin',
    () async {
      final server = ClassicAssetServer(
        port: 0,
        loader: (path) async {
          expect(path, 'assets/classic/index.html');
          return ByteData.sublistView(
            Uint8List.fromList('<h1>WordLab</h1>'.codeUnits),
          );
        },
      );
      await server.start();
      final client = HttpClient();
      final response = await (await client.getUrl(server.origin)).close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(server.origin.host, '127.0.0.1');
      client.close(force: true);
      await server.close();
    },
  );
  test('missing assets return 404 instead of a different interface', () async {
    final server = ClassicAssetServer(
      port: 0,
      loader: (_) async => throw StateError('missing'),
    );
    await server.start();
    final client = HttpClient();
    final response = await (await client.getUrl(
      server.origin.resolve('missing.js'),
    )).close();
    expect(response.statusCode, 404);
    client.close(force: true);
    await server.close();
  });
  test('unsupported requests cannot write to application assets', () async {
    final server = ClassicAssetServer(
      port: 0,
      loader: (_) async => throw StateError('must not be read'),
    );
    await server.start();
    final client = HttpClient();
    final response = await (await client.postUrl(server.origin)).close();
    expect(response.statusCode, 405);
    client.close(force: true);
    await server.close();
  });
}
