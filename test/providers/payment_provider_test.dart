import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/providers/payment_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PaymentNotifier.getPaymentHistory', () {
    test('keeps valid history records and skips malformed entries', () async {
      SharedPreferences.setMockInitialValues({
        'payment_records': [
          '{"payment_id":"p1","total_amount":12.5}',
          'not json',
          '[1,2,3]',
          '{"2":"two"}',
        ],
      });

      final notifier = PaymentNotifier();
      addTearDown(notifier.dispose);

      final history = await notifier.getPaymentHistory();

      expect(history, [
        {'payment_id': 'p1', 'total_amount': 12.5},
        {'2': 'two'},
      ]);
    });
  });
}
