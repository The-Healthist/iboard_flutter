import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/api_client.dart';

void main() {
  group('ApiClient carousel array responses', () {
    test('keeps valid map rows and skips malformed list items', () async {
      final server = await _jsonServer([
        {'id': 1, 'title': 'Lobby'},
        'malformed',
        42,
        {'id': 2, 'title': 'Gate'},
      ]);

      try {
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        final rows = await client.getCarouselTopAdvertisements();

        expect(rows, hasLength(2));
        expect(rows[0], {'id': 1, 'title': 'Lobby'});
        expect(rows[1], {'id': 2, 'title': 'Gate'});
      } finally {
        await server.close(force: true);
      }
    });

    test('handles data-wrapped arrays with malformed items', () async {
      final server = await _jsonServer({
        'data': [
          {'id': 7},
          null,
          ['not-a-map'],
        ],
      });

      try {
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        final rows = await client.getCarouselTopAdvertisements();

        expect(rows, [
          {'id': 7},
        ]);
      } finally {
        await server.close(force: true);
      }
    });
  });
}

Future<HttpServer> _jsonServer(Object responseBody) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(responseBody));
    request.response.close();
  });
  return server;
}
