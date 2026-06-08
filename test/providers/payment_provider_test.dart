import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/payment_data_source.dart';
import 'package:iboard_app/http/payment_gateway.dart';
import 'package:iboard_app/models/payment_model.dart';
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

  group('PaymentNotifier state flow', () {
    test('selectBuilding clears stale unit, bills, selected bills, and errors',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fakeClient = _FakePaymentDataSource(
        units: [
          {
            'unit_id': 'u1',
            'simpleadd': '01/F A',
            'block': '',
            'floor': '01',
            'unit': 'A',
          },
        ],
        transactionTypes: {
          'building_id': 'b2',
          'transaction_types': [
            {'pay_type': 'POS_ALIWE', 'markup': '0.02'},
          ],
        },
      );
      final notifier = PaymentNotifier(paymentClient: fakeClient);
      addTearDown(notifier.dispose);

      await notifier.selectBuilding('b1');
      await notifier.selectUnit('u1');
      notifier.addBillToCart(notifier.state.bills.single);

      fakeClient.units = [
        {
          'unit_id': 'u2',
          'simpleadd': '02/F B',
          'block': '',
          'floor': '02',
          'unit': 'B',
        },
      ];

      await notifier.selectBuilding('b2');

      expect(notifier.state.selectedBuildingId, 'b2');
      expect(notifier.state.selectedUnitId, isNull);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.bills, isEmpty);
      expect(notifier.state.selectedBills, isEmpty);
      expect(notifier.state.units.single.unitId, 'u2');
      expect(notifier.state.paymentConfig?.enabledMethods,
          containsAll([PaymentMethod.wechat, PaymentMethod.alipay]));
    });

    test(
        'selectUnit clears stale error and selected bills before loading bills',
        () async {
      SharedPreferences.setMockInitialValues({});
      final fakeClient = _FakePaymentDataSource(
        bills: [
          {
            'flat_code': 'F1',
            'item_id': 'bill-2',
            'trs_to': '2026-06',
            'bill_dt': '2026-06-01',
            'net_amount': '20.5',
            'invoice_no': 'INV2',
          },
        ],
      );
      final notifier = PaymentNotifier(paymentClient: fakeClient);
      addTearDown(notifier.dispose);

      await notifier.selectUnit('u1');
      notifier.addBillToCart(notifier.state.bills.single);

      fakeClient.bills = [
        {
          'flat_code': 'F2',
          'item_id': 'bill-3',
          'trs_to': '2026-07',
          'bill_dt': '2026-07-01',
          'net_amount': 31,
          'invoice_no': 'INV3',
        },
      ];

      await notifier.selectUnit('u2');

      expect(notifier.state.selectedUnitId, 'u2');
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.selectedBills, isEmpty);
      expect(notifier.state.bills.single.itemId, 'bill-3');
    });

    test('successful retry clears stale unit-loading errors', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeClient = _FakePaymentDataSource()..throwOnBills = true;
      final notifier = PaymentNotifier(paymentClient: fakeClient);
      addTearDown(notifier.dispose);

      await notifier.selectUnit('u1');

      expect(notifier.state.errorMessage, contains('載入账单失敗'));

      fakeClient
        ..throwOnBills = false
        ..bills = [
          {
            'flat_code': 'F2',
            'item_id': 'bill-retry',
            'trs_to': '2026-08',
            'bill_dt': '2026-08-01',
            'net_amount': 42,
            'invoice_no': 'INV4',
          },
        ];

      await notifier.selectUnit('u1');

      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.bills.single.itemId, 'bill-retry');
    });

    test('createWechatPayment fails visibly when gateway is missing', () async {
      SharedPreferences.setMockInitialValues({});
      final bill = _bill();
      final notifier = PaymentNotifier();
      addTearDown(notifier.dispose);

      notifier.debugSetState(_payableState(selectedBills: [bill]));

      await notifier.createWechatPayment(selectedBills: [bill]);

      expect(notifier.state.status, PaymentStatus.failed);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, '支付服務未初始化');
    });

    test('createWechatPayment sends amount with fee and stores QR response',
        () async {
      SharedPreferences.setMockInitialValues({});
      final bill = _bill(amount: 100);
      final fakeGateway = _FakePaymentGateway();
      final notifier = PaymentNotifier(
        paymentStatusPollInterval: const Duration(days: 1),
      )..setPaymentGateway(fakeGateway);
      addTearDown(notifier.dispose);

      notifier.debugSetState(_payableState(selectedBills: [bill]));

      await notifier.createWechatPayment(selectedBills: [bill]);

      expect(fakeGateway.lastCreateMethod, PaymentMethod.wechat);
      expect(fakeGateway.lastOrderNo, startsWith('PAY'));
      expect(fakeGateway.lastAmount, 102);
      expect(fakeGateway.lastSubject, '物業管理費繳納');
      expect(fakeGateway.lastBody, contains('1筆賬單'));
      expect(fakeGateway.lastBody, contains('HK\$102.00'));
      expect(notifier.state.status, PaymentStatus.processing);
      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.paymentResponse?.paymentId, 'pay-order-1');
      expect(notifier.state.paymentResponse?.qrCode, 'qr-data');
      expect(notifier.state.selectedBills.single.itemId, bill.itemId);
    });

    test('payment status polling updates success and saves history', () async {
      SharedPreferences.setMockInitialValues({});
      final bill = _bill(amount: 100);
      final fakeGateway = _FakePaymentGateway()
        ..queryResponse = {
          'payOrderId': 'pay-order-1',
          'payData': 'qr-data',
          'channelOrderNo': 'txn-success',
          'state': 2,
          'createdTime': 1710000000000,
          'successTime': 1710000060000,
        };
      final notifier = PaymentNotifier(
        paymentStatusPollInterval: const Duration(milliseconds: 1),
        paymentStatusTimeout: const Duration(seconds: 5),
      )..setPaymentGateway(fakeGateway);
      addTearDown(notifier.dispose);

      notifier.debugSetState(_payableState(
        buildings: const [BuildingInfo(buildingId: 'b1', name: 'Tower One')],
        units: const [
          UnitInfo(
            unitId: 'u1',
            flatCode: '01/F A',
            blockName: '',
            floorName: '01',
            unitName: 'A',
          ),
        ],
        selectedBills: [bill],
      ));

      await notifier.createWechatPayment(selectedBills: [bill]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.state.status, PaymentStatus.success);
      expect(notifier.state.paymentResponse?.transactionId, 'txn-success');
      expect(fakeGateway.lastQueryPaymentMethod, 'wechat_alipay');

      final history = await notifier.getPaymentHistory();
      expect(history, hasLength(1));
      expect(history.single['transaction_id'], 'txn-success');
      expect(history.single['building_name'], 'Tower One');
      expect(history.single['unit_name'], '01A');
    });

    test('payment status polling surfaces third-party failures', () async {
      SharedPreferences.setMockInitialValues({});
      final bill = _bill(amount: 100);
      final fakeGateway = _FakePaymentGateway()
        ..queryResponse = {
          'payOrderId': 'pay-order-1',
          'payData': 'qr-data',
          'channelOrderNo': 'txn-failed',
          'state': 3,
          'errMsg': 'insufficient funds',
          'createdTime': 1710000000000,
        };
      final notifier = PaymentNotifier(
        paymentStatusPollInterval: const Duration(milliseconds: 1),
        paymentStatusTimeout: const Duration(seconds: 5),
      )..setPaymentGateway(fakeGateway);
      addTearDown(notifier.dispose);

      notifier.debugSetState(_payableState(selectedBills: [bill]));

      await notifier.createWechatPayment(selectedBills: [bill]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.state.status, PaymentStatus.failed);
      expect(notifier.state.paymentResponse?.status, PaymentStatus.failed);
      expect(notifier.state.paymentResponse?.transactionId, 'txn-failed');
      expect(notifier.state.errorMessage, '支付失敗：insufficient funds');
    });

    test('payment status polling times out pending payments', () async {
      SharedPreferences.setMockInitialValues({});
      final bill = _bill(amount: 100);
      final fakeGateway = _FakePaymentGateway();
      final notifier = PaymentNotifier(
        paymentStatusPollInterval: const Duration(milliseconds: 50),
        paymentStatusTimeout: const Duration(milliseconds: 5),
      )..setPaymentGateway(fakeGateway);
      addTearDown(notifier.dispose);

      notifier.debugSetState(_payableState(selectedBills: [bill]));

      await notifier.createWechatPayment(selectedBills: [bill]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(notifier.state.status, PaymentStatus.failed);
      expect(notifier.state.errorMessage, '支付超時，請重新嘗試');
      expect(fakeGateway.lastQueryOrderNo, isNull);
    });

    test('payment status polling stops polling pending payments after timeout',
        () async {
      SharedPreferences.setMockInitialValues({});
      final bill = _bill(amount: 100);
      final fakeGateway = _FakePaymentGateway()
        ..queryResponse = {
          'payOrderId': 'pay-order-1',
          'channelOrderNo': 'txn-pending',
          'state': 1,
          'createdTime': 1710000000000,
        };
      final notifier = PaymentNotifier(
        paymentStatusPollInterval: const Duration(milliseconds: 1),
        paymentStatusTimeout: const Duration(milliseconds: 10),
      )..setPaymentGateway(fakeGateway);
      addTearDown(notifier.dispose);

      notifier.debugSetState(_payableState(selectedBills: [bill]));

      await notifier.createWechatPayment(selectedBills: [bill]);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      final queryCountAfterTimeout = fakeGateway.queryCount;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.status, PaymentStatus.failed);
      expect(notifier.state.errorMessage, '支付超時，請重新嘗試');
      expect(fakeGateway.queryCount, queryCountAfterTimeout);
    });

    test('payment status polling does not overlap slow status requests',
        () async {
      SharedPreferences.setMockInitialValues({});
      final bill = _bill(amount: 100);
      final queryCompleter = Completer<Map<String, dynamic>>();
      final fakeGateway = _FakePaymentGateway()
        ..queryCompleter = queryCompleter;
      final notifier = PaymentNotifier(
        paymentStatusPollInterval: const Duration(milliseconds: 1),
        paymentStatusTimeout: const Duration(seconds: 1),
      )..setPaymentGateway(fakeGateway);
      addTearDown(notifier.dispose);

      notifier.debugSetState(_payableState(selectedBills: [bill]));

      await notifier.createWechatPayment(selectedBills: [bill]);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeGateway.queryCount, 1);

      queryCompleter.complete({
        'payOrderId': 'pay-order-1',
        'channelOrderNo': 'txn-success',
        'state': 2,
        'createdTime': 1710000000000,
        'successTime': 1710000060000,
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.status, PaymentStatus.success);
    });
  });
}

PaymentState _payableState({
  List<BuildingInfo> buildings = const [],
  List<UnitInfo> units = const [],
  List<PaymentBill> selectedBills = const [],
}) {
  return PaymentState(
    buildings: buildings,
    units: units,
    selectedBuildingId: 'b1',
    selectedUnitId: 'u1',
    selectedBills: selectedBills,
    paymentConfig: const PaymentConfig(
      buildingId: 'b1',
      enabledMethods: [PaymentMethod.wechat],
      feeRates: {'wechat': 0.02},
    ),
  );
}

PaymentBill _bill({double amount = 10}) {
  return PaymentBill(
    flatCode: 'F1',
    itemId: 'bill-1',
    trsTo: '2026-06',
    billDt: '2026-06-01',
    netAmount: amount,
    invoiceNo: 'INV1',
  );
}

class _FakePaymentDataSource implements PaymentDataSource {
  _FakePaymentDataSource({
    this.units = const [],
    this.transactionTypes = const {
      'building_id': 'default',
      'enabled_methods': ['wechat'],
    },
    this.bills = const [
      {
        'flat_code': 'F1',
        'item_id': 'bill-1',
        'trs_to': '2026-06',
        'bill_dt': '2026-06-01',
        'net_amount': 10,
        'invoice_no': 'INV1',
      },
    ],
  });

  List<Map<String, dynamic>> units;
  Map<String, dynamic> transactionTypes;
  List<Map<String, dynamic>> bills;
  bool throwOnBills = false;

  @override
  Future<List<Map<String, dynamic>>> getBuildingList() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getBuildingFlatUnits({
    required String blgId,
  }) async =>
      units;

  @override
  Future<Map<String, dynamic>> getBuildingTransactionTypes({
    required String blgId,
  }) async =>
      transactionTypes;

  @override
  Future<List<Map<String, dynamic>>> getBuildingFlatUnitBills({
    required String unitId,
  }) async {
    if (throwOnBills) {
      throw Exception('network failed');
    }
    return bills;
  }
}

class _FakePaymentGateway implements PaymentGateway {
  PaymentMethod? lastCreateMethod;
  String? lastOrderNo;
  double? lastAmount;
  String? lastSubject;
  String? lastBody;
  String? lastQueryOrderNo;
  String? lastQueryPaymentMethod;
  int queryCount = 0;
  Completer<Map<String, dynamic>>? queryCompleter;
  Map<String, dynamic> queryResponse = const {
    'payOrderId': 'pay-order-1',
    'payData': 'qr-data',
    'channelOrderNo': 'txn-1',
    'state': 0,
    'createdTime': 1710000000000,
  };

  @override
  Future<Map<String, dynamic>> createWechatPayment({
    required String orderNo,
    required double amount,
    required String subject,
    String? body,
    String? returnUrl,
  }) async {
    _captureCreate(PaymentMethod.wechat, orderNo, amount, subject, body);
    return const {
      'payOrderId': 'pay-order-1',
      'payData': 'qr-data',
      'channelOrderNo': 'txn-1',
      'state': 0,
      'createdTime': 1710000000000,
    };
  }

  @override
  Future<Map<String, dynamic>> createAlipayPayment({
    required String orderNo,
    required double amount,
    required String subject,
    String? body,
    String? returnUrl,
  }) async {
    _captureCreate(PaymentMethod.alipay, orderNo, amount, subject, body);
    return const {};
  }

  @override
  Future<Map<String, dynamic>> createUnionpayPayment({
    required String orderNo,
    required double amount,
    required String subject,
    String? body,
    String? returnUrl,
  }) async {
    _captureCreate(PaymentMethod.unionpay, orderNo, amount, subject, body);
    return const {};
  }

  @override
  Future<Map<String, dynamic>> queryPaymentStatus({
    required String orderNo,
    String? paymentMethod,
  }) async {
    queryCount++;
    lastQueryOrderNo = orderNo;
    lastQueryPaymentMethod = paymentMethod;
    final completer = queryCompleter;
    if (completer != null) {
      return completer.future;
    }
    return queryResponse;
  }

  void _captureCreate(
    PaymentMethod method,
    String orderNo,
    double amount,
    String subject,
    String? body,
  ) {
    lastCreateMethod = method;
    lastOrderNo = orderNo;
    lastAmount = amount;
    lastSubject = subject;
    lastBody = body;
  }
}
