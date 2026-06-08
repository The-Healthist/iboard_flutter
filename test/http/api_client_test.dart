import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/api_client.dart';

void main() {
  group('ApiClient object responses', () {
    test('keeps successful map responses', () async {
      final server = await _jsonServer({
        'version': '1.2.3',
        'build_number': '4',
      });

      try {
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        final data = await client.getAppVersion();

        expect(data, {
          'version': '1.2.3',
          'build_number': '4',
        });
      } finally {
        await server.close(force: true);
      }
    });

    test('uses an empty map for non-map successful JSON', () async {
      final server = await _jsonServer(['unexpected']);

      try {
        final client = ApiClient(baseUrl: 'http://127.0.0.1:${server.port}');

        final data = await client.getAppVersion();

        expect(data, isEmpty);
      } finally {
        await server.close(force: true);
      }
    });
  });

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

  group('ApiClient token refresh', () {
    test('refreshes after a real 401 without preflight health checks',
        () async {
      var carouselCalls = 0;
      var loginCalls = 0;
      var healthCalls = 0;

      final server = await _handlerServer((request) {
        if (request.uri.path == '/api/device/client/health_test') {
          healthCalls++;
          request.response.statusCode = HttpStatus.unauthorized;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'error': 'expired'}));
          return;
        }

        if (request.uri.path == '/api/device/login') {
          loginCalls++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'token': 'new-token'}));
          return;
        }

        if (request.uri.path ==
            '/api/device/client/carousel/top_advertisements') {
          carouselCalls++;
          request.response.headers.contentType = ContentType.json;
          if (carouselCalls == 1) {
            request.response.statusCode = HttpStatus.unauthorized;
            request.response.write(jsonEncode({'error': 'expired'}));
          } else {
            request.response.write(jsonEncode([
              {'id': 1, 'title': 'refreshed'},
            ]));
          }
          return;
        }

        request.response.statusCode = HttpStatus.notFound;
      });

      try {
        late final ApiClient client;
        client = ApiClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
          onNeedsTokenRefresh: () async {
            final response = await client.login(deviceId: 'device-1');
            return response['token'] as String?;
          },
        )..setAuthToken('expired-token');

        final rows = await client.getCarouselTopAdvertisements();

        expect(rows, [
          {'id': 1, 'title': 'refreshed'},
        ]);
        expect(healthCalls, 0);
        expect(loginCalls, 1);
        expect(carouselCalls, 2);
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

Future<HttpServer> _handlerServer(
  void Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    handler(request);
    request.response.close();
  });
  return server;
}
