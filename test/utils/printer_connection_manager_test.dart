import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/utils/printer_connection_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PrinterConnectionManager cache loading', () {
    tearDown(() async {
      await PrinterConnectionManager().clearAll();
    });

    test('loads valid saved printers and skips malformed cache rows', () async {
      SharedPreferences.setMockInitialValues({
        'saved_printers': jsonEncode([
          {
            'id': 'printer-1',
            'name': 'Lobby Printer',
            'ipAddress': '192.168.1.20',
            'isConnected': true,
            'model': 'HP',
          },
          {'id': 'missing-name'},
          'bad row',
          {
            'id': 7,
            'name': 'bad id',
            'isConnected': true,
          },
        ]),
      });

      final manager = PrinterConnectionManager();

      await manager.initialize();

      final printers = manager.getSavedPrinters();
      expect(printers, hasLength(1));
      expect(printers.single.id, 'printer-1');
      expect(printers.single.name, 'Lobby Printer');
      expect(printers.single.ipAddress, '192.168.1.20');
      expect(printers.single.isConnected, isTrue);
    });

    test('uses an empty saved printer list for non-list cache JSON', () async {
      SharedPreferences.setMockInitialValues({
        'saved_printers': jsonEncode({'unexpected': 'object'}),
      });

      final manager = PrinterConnectionManager();

      await manager.initialize();

      expect(manager.getSavedPrinters(), isEmpty);
    });

    test('ignores malformed default printer JSON', () async {
      SharedPreferences.setMockInitialValues({
        'default_printer': jsonEncode({'id': 'missing-name'}),
      });

      final manager = PrinterConnectionManager();

      await manager.initialize();

      expect(manager.getDefaultPrinter(), isNull);
    });
  });
}
