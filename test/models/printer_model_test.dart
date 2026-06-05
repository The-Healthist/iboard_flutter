import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/printer_model.dart';

void main() {
  group('PrinterInfo.fromJson', () {
    test('parses flexible scalar values safely', () {
      final printer = PrinterInfo.fromJson({
        'id': '12',
        'name': 123,
        'display_name': 456,
        'state': 'idle',
        'accepting_jobs': 'yes',
        'uri': 789,
        'ip_address': 101,
        'enabled': '1',
        'created_at': 'bad-date',
        'status': 1,
        'reason': 2,
      });

      expect(printer.id, 12);
      expect(printer.name, '123');
      expect(printer.displayName, '456');
      expect(printer.acceptingJobs, isTrue);
      expect(printer.uri, '789');
      expect(printer.ipAddress, '101');
      expect(printer.enabled, isTrue);
      expect(printer.createdAt, isNull);
      expect(printer.status, '1');
      expect(printer.reason, '2');
    });
  });

  group('PrinterDetails.fromJson', () {
    test('parses nested status from dynamic maps safely', () {
      final details = PrinterDetails.fromJson({
        'id': 1.9,
        'name': 'Printer',
        'display_name': 'Main Printer',
        'state_code': '3',
        'accepting_jobs': 1,
        'enabled': 'false',
        'status': {
          'connected': 'true',
          'status': 200,
          'is_online': '1',
          'accepting_jobs': 'yes',
          'message': 123,
        },
      });

      expect(details.id, 1);
      expect(details.stateCode, 3);
      expect(details.acceptingJobs, isTrue);
      expect(details.enabled, isFalse);
      expect(details.status.connected, isTrue);
      expect(details.status.status, '200');
      expect(details.status.isOnline, isTrue);
      expect(details.status.acceptingJobs, isTrue);
      expect(details.status.message, '123');
    });
  });

  group('PrintersListResponse.fromJson', () {
    test('skips malformed printer list entries and parses string count', () {
      final response = PrintersListResponse.fromJson({
        'success': 'true',
        'count': '2',
        'printers': [
          {
            'id': '1',
            'name': 'P1',
            'display_name': 'Printer 1',
            'state': 'idle',
            'accepting_jobs': true,
            'enabled': true,
          },
          'bad item',
        ],
      });

      expect(response.success, isTrue);
      expect(response.count, 2);
      expect(response.printers, hasLength(1));
      expect(response.printers.single.id, 1);
    });
  });

  group('PrintSettings.fromJson', () {
    test('parses numeric and boolean settings from strings', () {
      final settings = PrintSettings.fromJson({
        'copies': '2',
        'duplex': 'true',
        'number_up': 4.8,
        'priority': '80',
      });

      expect(settings.copies, 2);
      expect(settings.duplex, isTrue);
      expect(settings.numberUp, 4);
      expect(settings.priority, 80);
    });
  });

  group('PrintJobResponse.fromJson', () {
    test('parses job ids and file info from flexible payloads', () {
      final response = PrintJobResponse.fromJson({
        'success': 1,
        'job_id': '123',
        'cups_job_id': 456.9,
        'message': 789,
        'file_info': {
          'filename': 1,
          'size_kb': '12.5',
          'format': 2,
        },
      });

      expect(response.success, isTrue);
      expect(response.jobId, 123);
      expect(response.cupsJobId, 456);
      expect(response.message, '789');
      expect(response.fileInfo!.filename, '1');
      expect(response.fileInfo!.sizeKb, 12.5);
      expect(response.fileInfo!.format, '2');
    });
  });

  group('TestConnectionResponse.fromJson', () {
    test('parses protocol booleans from dynamic maps safely', () {
      final response = TestConnectionResponse.fromJson({
        'success': 'yes',
        'connected': 1,
        'protocols': {
          631: 'true',
          '9100': 0,
        },
      });

      expect(response.success, isTrue);
      expect(response.connected, isTrue);
      expect(response.protocols, {'631': true, '9100': false});
    });
  });
}
