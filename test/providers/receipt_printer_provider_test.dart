import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/providers/receipt_printer_provider.dart';

void main() {
  group('receiptAmountFromValue', () {
    test('parses numeric and string amounts safely', () {
      expect(receiptAmountFromValue(12), 12.0);
      expect(receiptAmountFromValue(12.5), 12.5);
      expect(receiptAmountFromValue('1,234.50'), 1234.5);
      expect(receiptAmountFromValue(''), 0.0);
      expect(receiptAmountFromValue('not-a-number'), 0.0);
      expect(receiptAmountFromValue(null), 0.0);
    });
  });

  group('parseReceiptBillLines', () {
    test('keeps valid map-like bill rows and skips malformed entries', () {
      final lines = parseReceiptBillLines([
        {
          'item_id': 1001,
          'net_amount': '88.20',
          'trs_to': DateTime.parse('2026-06-05T00:00:00Z'),
          'invoice_no': 'INV-1',
        },
        {
          42: 'ignored key',
          'net_amount': 12,
        },
        'malformed',
      ]);

      expect(lines, hasLength(2));
      expect(lines.first.itemId, '1001');
      expect(lines.first.netAmount, 88.2);
      expect(lines.first.trsTo, '2026-06-05 00:00:00.000Z');
      expect(lines.first.invoiceNo, 'INV-1');
      expect(lines.last.itemId, '');
      expect(lines.last.netAmount, 12.0);
    });
  });

  group('formatReceiptDateTime', () {
    test('formats DateTime and ISO strings without falling back to now', () {
      expect(
        formatReceiptDateTime(DateTime.parse('2026-06-05T09:07:00')),
        '2026-06-05 09:07',
      );
      expect(
        formatReceiptDateTime('2026-06-05T13:45:00'),
        '2026-06-05 13:45',
      );
      expect(formatReceiptDateTime('bad-date'), '');
      expect(formatReceiptDateTime(null), '');
    });
  });
}
