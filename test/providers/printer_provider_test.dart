import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PrinterProvider.initialize', () {
    test('loads cached printers and skips malformed cached entries', () async {
      SharedPreferences.setMockInitialValues({
        'orange_pi_ip': '192.168.1.10',
        'api_default_printer_id': 7,
        'api_saved_printers': '''
          [
            {
              "id": "7",
              "name": "office",
              "display_name": "Office Printer",
              "state": "idle",
              "accepting_jobs": "true",
              "uri": "ipp://192.168.1.50/ipp/print",
              "ip_address": "192.168.1.50",
              "enabled": "1"
            },
            "bad item"
          ]
        ''',
      });

      final provider = PrinterProvider();

      await provider.initialize(probeService: false);

      expect(provider.orangePiIp, '192.168.1.10');
      expect(provider.printers, hasLength(1));
      expect(provider.printers.single.id, 7);
      expect(provider.printers.single.acceptingJobs, isTrue);
      expect(provider.defaultPrinter?.id, 7);
    });
  });
}
