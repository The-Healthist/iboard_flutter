import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iboard_app/http/api_print.dart';
import 'package:iboard_app/models/printer_model.dart';

void main() {
  group('PrintApiClient.printPdfBase64', () {
    test('submits the expected flattened print request body', () async {
      late Uri capturedUri;
      late Map<String, dynamic> capturedBody;

      final client = PrintApiClient(
        orangePiIp: '192.168.1.20',
        httpClient: MockClient((request) async {
          capturedUri = request.url;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;

          return http.Response(
            jsonEncode({
              'success': true,
              'job_id': 12,
              'cups_job_id': 34,
              'message': 'queued',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final response = await client.printPdfBase64(
        printerIp: '10.0.0.8',
        base64Data: 'JVBERi0xLjQ=',
        filename: 'notice.pdf',
        title: 'Notice',
        settings: const PrintSettings(
          copies: 2,
          colorMode: 'monochrome',
          duplex: true,
          duplexType: 'long-edge',
          pageRange: '1-2',
        ),
      );

      expect(
        capturedUri.toString(),
        'http://192.168.1.20:8080/api/printers/ip/10.0.0.8/print/base64',
      );
      expect(capturedBody['printer_ip'], '10.0.0.8');
      expect(capturedBody['file_data'], 'JVBERi0xLjQ=');
      expect(capturedBody['filename'], 'notice.pdf');
      expect(capturedBody['title'], 'Notice');
      expect(capturedBody['copies'], 2);
      expect(capturedBody['color_mode'], 'monochrome');
      expect(capturedBody['duplex'], isTrue);
      expect(capturedBody['duplex_type'], 'long-edge');
      expect(capturedBody['page_range'], '1-2');
      expect(response.success, isTrue);
      expect(response.jobId, 12);
      expect(response.cupsJobId, 34);
    });

    test('preserves server error messages from non-success responses',
        () async {
      final client = PrintApiClient(
        orangePiIp: '192.168.1.20',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'success': false,
              'message': 'Printer is offline',
            }),
            503,
            reasonPhrase: 'Service Unavailable',
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(
        () => client.printPdfBase64(
          printerIp: '10.0.0.8',
          base64Data: 'JVBERi0xLjQ=',
          filename: 'notice.pdf',
          title: 'Notice',
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Printer is offline'),
          ),
        ),
      );
    });
  });
}
