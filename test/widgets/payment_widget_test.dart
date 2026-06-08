import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iboard_app/http/payment_data_source.dart';
import 'package:iboard_app/models/payment_model.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/payment_provider.dart';
import 'package:iboard_app/widgets/mainscreen/main_display/payment_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('determinePaymentWidgetViewMode', () {
    test('maps loading, unavailable, selector, and active states', () {
      expect(
        determinePaymentWidgetViewMode(
          const PaymentState(isLoading: true),
        ),
        PaymentWidgetViewMode.initializing,
      );
      expect(
        determinePaymentWidgetViewMode(const PaymentState()),
        PaymentWidgetViewMode.unavailable,
      );
      expect(
        determinePaymentWidgetViewMode(
          PaymentState(units: [_unit()]),
        ),
        PaymentWidgetViewMode.selectorWithUnavailablePayment,
      );
      expect(
        determinePaymentWidgetViewMode(
          const PaymentState(
            paymentConfig: PaymentConfig(
              buildingId: 'b1',
              enabledMethods: [PaymentMethod.wechat],
              feeRates: {},
            ),
          ),
        ),
        PaymentWidgetViewMode.active,
      );
    });
  });

  group('PaymentWidget', () {
    testWidgets('shows fallback payment unavailable page with no units',
        (tester) async {
      final notifier = PaymentNotifier();
      addTearDown(notifier.dispose);

      await tester.pumpWidget(_wrap(notifier));
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('選擇樓層'), findsNothing);
      expect(find.text('支付功能暫未開通'), findsNothing);
    });

    testWidgets('shows selectors and unavailable notice when units exist',
        (tester) async {
      final notifier = PaymentNotifier()
        ..debugSetState(
          PaymentState(
            units: [_unit()],
            paymentConfig: const PaymentConfig(
              buildingId: 'b1',
              enabledMethods: [],
              feeRates: {},
            ),
          ),
        );
      addTearDown(notifier.dispose);

      await tester.pumpWidget(_wrap(notifier));
      await tester.pump();

      expect(find.text('選擇樓層'), findsOneWidget);
      expect(find.text('選擇單位'), findsOneWidget);
      expect(find.text('支付功能暫未開通'), findsOneWidget);
      expect(find.text('Payment Feature Not Available'), findsOneWidget);
    });

    testWidgets('fires idle timeout using injected duration', (tester) async {
      var idleCount = 0;
      final notifier = PaymentNotifier();
      addTearDown(notifier.dispose);

      await tester.pumpWidget(
        _wrap(
          notifier,
          widget: PaymentWidget(
            resetOnEnter: false,
            initializeFromBuilding: false,
            idleTimeout: const Duration(milliseconds: 20),
            onIdleTimeout: () => idleCount++,
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 25));

      expect(idleCount, 1);
    });

    testWidgets('selects bills and reveals payment method and fee details',
        (tester) async {
      final notifier = PaymentNotifier(
        paymentClient: _FakePaymentDataSource(
          bills: [
            _billJson(id: 'paid', amount: 0),
            _billJson(id: 'payable', amount: 100),
          ],
        ),
      )..debugSetState(
          PaymentState(
            units: [_unit()],
            paymentConfig: const PaymentConfig(
              buildingId: 'b1',
              enabledMethods: [PaymentMethod.wechat],
              feeRates: {'wechat': 0.02},
            ),
          ),
        );
      addTearDown(notifier.dispose);

      await tester.pumpWidget(_wrap(notifier));
      await tester.pump();

      await tester.tap(find.text('01'));
      await tester.pump();
      await tester.tap(find.text('A'));
      await tester.pumpAndSettle();

      expect(find.text('paid'), findsOneWidget);
      expect(find.text('payable'), findsOneWidget);

      await tester.tap(find.text('全選'));
      await tester.pump();

      expect(notifier.state.selectedBills, hasLength(1));
      expect(notifier.state.selectedBills.single.itemId, 'payable');
      expect(find.text('微信支付'), findsOneWidget);

      await tester.ensureVisible(find.text('微信支付'));
      await tester.pump();
      await tester.tap(find.text('微信支付'));
      await tester.pump();

      await tester.ensureVisible(find.text('費用明細'));
      await tester.pump();
      expect(find.text('費用明細'), findsOneWidget);
      expect(find.text('HK\$100.00'), findsWidgets);
      expect(find.text('HK\$102.00'), findsOneWidget);
      expect(find.text('結賬'), findsOneWidget);
    });

    testWidgets('shows QR code and cancel resets payment state',
        (tester) async {
      final bill = _bill(id: 'payable', amount: 100);
      final notifier = PaymentNotifier()
        ..debugSetState(
          _activeState(
            status: PaymentStatus.processing,
            selectedBills: [bill],
            paymentResponse: const PaymentResponse(
              paymentId: 'pay-order-1',
              status: PaymentStatus.processing,
              transactionId: 'txn-1',
              qrCode: 'qr-data',
            ),
          ),
        );
      addTearDown(notifier.dispose);

      await tester.pumpWidget(_wrap(notifier));
      await tester.pump();

      expect(find.text('請掃描二維碼完成支付'), findsOneWidget);
      expect(find.text('取消支付'), findsOneWidget);

      await tester.ensureVisible(find.text('取消支付'));
      await tester.pump();
      await tester.tap(find.text('取消支付'));
      await tester.pump();

      expect(notifier.state.status, PaymentStatus.pending);
      expect(notifier.state.paymentResponse, isNull);
      expect(notifier.state.selectedBills, isEmpty);
      expect(find.text('請掃描二維碼完成支付'), findsNothing);
    });

    testWidgets(
        'shows success state and completion reset keeps building config',
        (tester) async {
      final notifier = PaymentNotifier()
        ..debugSetState(
          _activeState(
            status: PaymentStatus.success,
            selectedBills: [_bill(id: 'paid', amount: 100)],
            paymentResponse: const PaymentResponse(
              paymentId: 'pay-order-1',
              status: PaymentStatus.success,
              transactionId: 'txn-success',
            ),
          ),
        );
      addTearDown(notifier.dispose);

      await tester.pumpWidget(_wrap(notifier));
      await tester.pump();

      expect(find.text('支付成功！'), findsOneWidget);
      expect(find.text('交易編號：txn-success'), findsOneWidget);

      await tester.ensureVisible(find.text('完成'));
      await tester.pump();
      await tester.tap(find.text('完成'));
      await tester.pump();

      expect(notifier.state.status, PaymentStatus.pending);
      expect(notifier.state.paymentResponse, isNull);
      expect(notifier.state.selectedBuildingId, 'b1');
      expect(notifier.state.paymentConfig?.buildingId, 'b1');
      expect(notifier.state.selectedUnitId, isNull);
    });
  });
}

Widget _wrap(
  PaymentNotifier notifier, {
  PaymentWidget widget = const PaymentWidget(
    resetOnEnter: false,
    initializeFromBuilding: false,
  ),
}) {
  SharedPreferences.setMockInitialValues({});
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PaymentNotifier>.value(value: notifier),
      ChangeNotifierProvider<AppDataProvider>(
        create: (_) => AppDataProvider(baseUrl: 'http://example.test'),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: widget),
    ),
  );
}

UnitInfo _unit() {
  return const UnitInfo(
    unitId: 'u1',
    flatCode: '01/F A',
    blockName: '',
    floorName: '01',
    unitName: 'A',
  );
}

Map<String, dynamic> _billJson({
  required String id,
  required num amount,
}) {
  return {
    'flat_code': 'F1',
    'item_id': id,
    'trs_to': '2026-06',
    'bill_dt': '2026-06-01',
    'net_amount': amount,
    'invoice_no': 'INV-$id',
  };
}

PaymentBill _bill({
  required String id,
  required double amount,
}) {
  return PaymentBill(
    flatCode: 'F1',
    itemId: id,
    trsTo: '2026-06',
    billDt: '2026-06-01',
    netAmount: amount,
    invoiceNo: 'INV-$id',
  );
}

PaymentState _activeState({
  required PaymentStatus status,
  required PaymentResponse paymentResponse,
  List<PaymentBill> selectedBills = const [],
}) {
  return PaymentState(
    status: status,
    selectedBuildingId: 'b1',
    selectedUnitId: 'u1',
    units: [_unit()],
    bills: selectedBills,
    selectedBills: selectedBills,
    paymentResponse: paymentResponse,
    paymentConfig: const PaymentConfig(
      buildingId: 'b1',
      enabledMethods: [PaymentMethod.wechat],
      feeRates: {'wechat': 0.02},
    ),
  );
}

class _FakePaymentDataSource implements PaymentDataSource {
  const _FakePaymentDataSource({required this.bills});

  final List<Map<String, dynamic>> bills;

  @override
  Future<List<Map<String, dynamic>>> getBuildingList() async => const [];

  @override
  Future<List<Map<String, dynamic>>> getBuildingFlatUnits({
    required String blgId,
  }) async =>
      const [];

  @override
  Future<Map<String, dynamic>> getBuildingTransactionTypes({
    required String blgId,
  }) async =>
      const {};

  @override
  Future<List<Map<String, dynamic>>> getBuildingFlatUnitBills({
    required String unitId,
  }) async =>
      bills;
}
