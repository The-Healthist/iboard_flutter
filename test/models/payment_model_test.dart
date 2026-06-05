import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/payment_model.dart';

void main() {
  group('PaymentConfig.fromJson', () {
    test('parses transaction types into enabled methods and fee rates', () {
      final config = PaymentConfig.fromJson({
        'building_id': 20,
        'transaction_types': [
          {'pay_type': 'POS_ALIWE', 'markup': 0.015},
          {'pay_type': 'POS_UNIONPAY', 'markup': 0.012},
          {'pay_type': 'POS_BANK', 'markup': 0},
          {'pay_type': 'POS_CASH', 'markup': 0},
          {'pay_type': 'POS_CHEQUE', 'markup': 0},
        ],
      });

      expect(config.buildingId, '20');
      expect(
        config.enabledMethods,
        containsAll([
          PaymentMethod.wechat,
          PaymentMethod.alipay,
          PaymentMethod.unionpay,
          PaymentMethod.bankTransfer,
          PaymentMethod.cash,
          PaymentMethod.cheque,
        ]),
      );
      expect(config.enabledMethods.toSet(),
          hasLength(config.enabledMethods.length));
      expect(config.feeRates['wechat'], 0.015);
      expect(config.feeRates['alipay'], 0.015);
      expect(config.feeRates['unionpay'], 0.012);
      expect(config.feeRates['bank_transfer'], 0);
      expect(config.feeRates['cash'], 0);
      expect(config.feeRates['cheque'], 0);
    });

    test('maps POS_CARD UnionPay names to unionpay only', () {
      final config = PaymentConfig.fromJson({
        'building_id': 'B1',
        'transaction_types': [
          {
            'pay_type': 'POS_CARD',
            'pay_type_name_chi': '雲閃付',
            'markup': 0.018,
          },
        ],
      });

      expect(config.enabledMethods, [PaymentMethod.unionpay]);
      expect(config.feeRates, {'unionpay': 0.018});
    });

    test('uses card fee as UnionPay fallback for generic POS_CARD', () {
      final config = PaymentConfig.fromJson({
        'building_id': 'B1',
        'transaction_types': [
          {
            'pay_type': 'POS_CARD',
            'pay_type_name_chi': '信用卡',
            'markup': 0.02,
          },
        ],
      });

      expect(
          config.enabledMethods, [PaymentMethod.card, PaymentMethod.unionpay]);
      expect(config.feeRates, {'card': 0.02, 'unionpay': 0.02});
    });

    test('falls back to enabled_methods when transaction_types is absent', () {
      final config = PaymentConfig.fromJson({
        'building_id': 'B1',
        'enabled_methods': ['wechat', 'alipay', 'cash'],
      });

      expect(config.enabledMethods, [
        PaymentMethod.wechat,
        PaymentMethod.alipay,
        PaymentMethod.cash,
      ]);
      expect(config.feeRates, isEmpty);
    });
  });
}
