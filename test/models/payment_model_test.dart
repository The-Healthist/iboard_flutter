import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/models/payment_model.dart';

void main() {
  group('PaymentBill.fromJson', () {
    test('parses string amounts and skips malformed bill list entries', () {
      final bill = PaymentBill.fromJson({
        'flat_code': 101,
        'item_id': 20,
        'trs_to': 30,
        'bill_dt': 20260605,
        'net_amount': '123.45',
        'invoice_no': 40,
        'paid_amount': '',
      });

      expect(bill.flatCode, '101');
      expect(bill.itemId, '20');
      expect(bill.netAmount, 123.45);
      expect(bill.paidAmount, 123.45);
      expect(bill.invoiceNo, '40');

      final bills = PaymentBill.listFrom([
        {
          'item_id': '1',
          'net_amount': '10.5',
          'unit_name': '',
        },
        'bad item',
      ], unitName: 'A101');

      expect(bills, hasLength(1));
      expect(bills.single.itemId, '1');
      expect(bills.single.netAmount, 10.5);
      expect(bills.single.unitName, 'A101');
    });
  });

  group('ThirdPartyPaymentResponse.fromJson', () {
    test('parses flexible scalar values and epoch timestamps safely', () {
      final response = ThirdPartyPaymentResponse.fromJson({
        'payData': 123,
        'channelOrderNo': 456,
        'mchOrderNo': 789,
        'payOrderId': 10,
        'amount': '2500',
        'currency': 344,
        'state': '2',
        'errCode': 0,
        'errMsg': 1,
        'createdTime': '1780617600000',
        'successTime': 1780617660000,
      });

      expect(response.qrCode, '123');
      expect(response.transactionId, '456');
      expect(response.orderNo, '789');
      expect(response.payOrderId, '10');
      expect(response.amount, 2500);
      expect(response.currency, '344');
      expect(response.state, 2);
      expect(response.errCode, '0');
      expect(response.errMsg, '1');
      expect(response.createdAt,
          DateTime.fromMillisecondsSinceEpoch(1780617600000));
      expect(response.successTime,
          DateTime.fromMillisecondsSinceEpoch(1780617660000));
      expect(response.toPaymentResponse().status, PaymentStatus.success);
    });
  });

  group('PaymentResponse.fromJson', () {
    test('parses flexible handling fee and raw data maps', () {
      final response = PaymentResponse.fromJson({
        'payment_id': 1,
        'status': 'failed',
        'transaction_id': 2,
        'handling_fee': '3.4',
        'raw_data': {1: 'one'},
      });

      expect(response.paymentId, '1');
      expect(response.status, PaymentStatus.failed);
      expect(response.transactionId, '2');
      expect(response.handlingFee, 3.4);
      expect(response.rawData, {'1': 'one'});
    });
  });

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
        'enabled_methods': ['wechat', 'alipay', 'cash', 'cheque', 'bad'],
      });

      expect(config.enabledMethods, [
        PaymentMethod.wechat,
        PaymentMethod.alipay,
        PaymentMethod.cash,
        PaymentMethod.cheque,
      ]);
      expect(config.feeRates, isEmpty);
    });

    test('parses dynamic maps and string markup values safely', () {
      final config = PaymentConfig.fromJson({
        'building_id': 'B1',
        'transaction_types': [
          {
            'pay_type': 'POS_BANK',
            'markup': '0.01',
          },
          'bad item',
        ],
        'bank_account': {
          1: 'ignored key',
          'account_name': 123,
          'account_number': 456,
          'bank_name': 789,
        },
        'settings': {1: 'one'},
      });

      expect(config.enabledMethods, [PaymentMethod.bankTransfer]);
      expect(config.feeRates, {'bank_transfer': 0.01});
      expect(config.bankAccount!.accountName, '123');
      expect(config.bankAccount!.accountNumber, '456');
      expect(config.bankAccount!.bankName, '789');
      expect(config.settings, {'1': 'one'});
    });
  });
}
