import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/payment.dart';

void main() {
  group('PaymentClient array responses', () {
    test('keeps valid map rows and skips malformed raw list items', () async {
      final server = await _jsonServer([
        {'building_id': '9077004', 'buildname_chi': '玉桂園(4座)'},
        'malformed',
        12,
        {'building_id': '9077005', 'buildname_chi': '玉桂園(5座)'},
      ]);

      try {
        final client = PaymentClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
        );

        final rows = await client.getBuildingList();

        expect(rows, [
          {'building_id': '9077004', 'buildname_chi': '玉桂園(4座)'},
          {'building_id': '9077005', 'buildname_chi': '玉桂園(5座)'},
        ]);
      } finally {
        await server.close(force: true);
      }
    });

    test('handles data-wrapped arrays with malformed items', () async {
      final server = await _jsonServer({
        'data': [
          {'invoice_no': '0228100003202', 'net_amount': 1930},
          null,
          ['not-a-map'],
        ],
      });

      try {
        final client = PaymentClient(
          baseUrl: 'http://127.0.0.1:${server.port}',
        );

        final rows =
            await client.getBuildingFlatUnitBills(unitId: '09999000434');

        expect(rows, [
          {'invoice_no': '0228100003202', 'net_amount': 1930},
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
