import 'dart:async'; // 22, 用於Timer無操作計時器
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:iboard_app/providers/payment_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/models/payment_model.dart';

enum PaymentWidgetViewMode {
  initializing,
  unavailable,
  selectorWithUnavailablePayment,
  active,
}

const TextStyle _billTableHeaderTextStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w800,
  height: 1.15,
  color: Colors.black87,
);

const TextStyle _billTableCellTextStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  height: 1.18,
);

const TextStyle _billTableAmountTextStyle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w800,
  height: 1.15,
);

class PaymentWidget extends StatefulWidget {
  final VoidCallback? onIdleTimeout; // 20, 無操作超時回調
  final bool resetOnEnter;
  final bool initializeFromBuilding;
  final Duration idleTimeout;

  const PaymentWidget({
    super.key,
    this.onIdleTimeout,
    this.resetOnEnter = true,
    this.initializeFromBuilding = true,
    this.idleTimeout = const Duration(seconds: 100),
  });

  @override
  State<PaymentWidget> createState() => _PaymentWidgetState();
}

class _PaymentWidgetState extends State<PaymentWidget> {
  String? _selectedBlock;
  String? _selectedFloor;
  String? _selectedUnit;
  PaymentMethod? _selectedPaymentMethod;

  // 21, 無操作計時器相關
  Timer? _idleTimer;
  // 14, 暫時注釋掉開發中訊息變數
  // bool _showDevelopmentMessage = false; // 是否顯示開發中訊息

  @override
  void initState() {
    super.initState();
    // 22, 啟動無操作計時器
    _startIdleTimer();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 進入時清空殘留的購物車與支付方式
      if (widget.resetOnEnter) {
        try {
          final notifier = context.read<PaymentNotifier>();
          notifier.clearCart();
          // 18, 重置支付狀態，清除之前的二維碼和成功信息
          notifier.resetPayment();
        } catch (_) {}
        setState(() {
          _selectedPaymentMethod = null;
          _selectedBlock = null;
          _selectedFloor = null;
          _selectedUnit = null;
        });
      }

      // 2, 檢查是否需要初始化支付
      if (!widget.initializeFromBuilding) {
        return;
      }
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      final ismartId = appDataProvider.buildingInfo?.ismartId;

      if (ismartId != null && ismartId.isNotEmpty) {
        // 如果有 ismartId，嘗試初始化支付
        try {
          final notifier = context.read<PaymentNotifier>();
          if (notifier.state.paymentConfig == null) {
            notifier.initializePayment(buildingId: ismartId);
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    // 23, 清理無操作計時器
    _idleTimer?.cancel();
    _idleTimer = null;

    //1, 退出電子繳費時清空賬單與支付方式，避免下方UI殘留
    try {
      final notifier = context.read<PaymentNotifier>();
      notifier.clearCart();
    } catch (_) {}
    _selectedPaymentMethod = null;
    _selectedBlock = null;
    _selectedFloor = null;
    _selectedUnit = null;
    super.dispose();
  }

  /// 24, 啟動無操作計時器
  void _startIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleTimeout, () {
      // 調用回調返回輪播
      widget.onIdleTimeout?.call();
    });
  }

  /// 25, 重置無操作計時器（用戶有交互時調用）
  void _resetIdleTimer() {
    _startIdleTimer();
  }

  /// 1, 使用登录后的 ismartId 初始化支付流程
  void _initializePaymentWithBuildingId() {
    final appDataProvider =
        Provider.of<AppDataProvider>(context, listen: false);
    final ismartId = appDataProvider.buildingInfo?.ismartId;
    final buildingName = appDataProvider.buildingInfo?.name;
    //todo:使用該ismartid獲取該大廈的手續費配置信息:getBuildingTransactionTypes
    //如果沒有微信支付/支付寳支付的方式的話或者ismartid獲取失敗,就需要和我的便利服務的widget的展示的ui類似
    //顯示的便利服務的方案類似,顯示一個背景圖,樣式完全一致就可以
    final hasBuildingName = buildingName != null && buildingName.isNotEmpty;

    if (ismartId != null && ismartId.isNotEmpty) {
      context.read<PaymentNotifier>().initializePayment(buildingId: ismartId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hasBuildingName ? '未找到大廈編號，請重新登錄' : '未找到大廈信息，請先登錄'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 23, 啟用樓層和單位選擇功能
    // 26, 包裹Listener檢測任何用戶交互
    return Listener(
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerMove: (_) => _resetIdleTimer(),
      child: Consumer<PaymentNotifier>(
        builder: (context, paymentNotifier, child) {
          final paymentState = paymentNotifier.state;
          final viewMode = determinePaymentWidgetViewMode(paymentState);

          // 根據載入狀態決定顯示內容
          if (viewMode == PaymentWidgetViewMode.initializing) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('正在初始化電子繳費...'),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _initializePaymentWithBuildingId,
                    child: const Text('開始使用電子繳費'),
                  ),
                ],
              ),
            );
          }

          // 24, 如果支付配置為空或支付方式為空，但有單位數據，仍顯示選擇器
          if (viewMode == PaymentWidgetViewMode.unavailable ||
              viewMode ==
                  PaymentWidgetViewMode.selectorWithUnavailablePayment) {
            // 如果沒有單位數據，顯示背景圖
            if (viewMode == PaymentWidgetViewMode.unavailable) {
              return _buildPaymentNotAvailablePage();
            }

            // 有單位數據，顯示選擇器但不顯示支付功能
            return Container(
              padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // 選擇器容器
                          _buildPaymentSelectorContainer(
                              paymentNotifier, paymentState),
                          const SizedBox(height: 16),

                          // 如果選擇了單位，顯示賬單相關內容
                          if (_selectedUnit != null) ...[
                            // 正在加載賬單
                            if (paymentState.isLoadingBills) ...[
                              _buildBillLoadingContainer(),
                              const SizedBox(height: 16),
                            ]
                            // 加載完成且有賬單，但只顯示不允許選擇
                            else if (paymentState.bills.isNotEmpty) ...[
                              _buildBillInfoContainer(
                                  paymentNotifier, paymentState),
                              const SizedBox(height: 16),
                            ]
                            // 加載完成但沒有賬單
                            else if (paymentNotifier.hasNobills) ...[
                              _buildNoBillsContainer(),
                              const SizedBox(height: 16),
                            ],
                          ],

                          // 顯示支付功能不可用提示
                          _buildPaymentUnavailableNotice(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // 正常的支付流程UI
          return Container(
            padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // 選擇器容器
                        _buildPaymentSelectorContainer(
                            paymentNotifier, paymentState),

                        const SizedBox(height: 16),

                        // 如果選擇了單位，顯示賬單相關內容
                        if (_selectedUnit != null) ...[
                          // 正在加載賬單
                          if (paymentState.isLoadingBills) ...[
                            _buildBillLoadingContainer(),
                            const SizedBox(height: 16),
                          ]
                          // 加載完成且有賬單
                          else if (paymentState.bills.isNotEmpty) ...[
                            _buildBillSelectionContainer(
                                paymentNotifier, paymentState),
                            const SizedBox(height: 16),
                          ]
                          // 加載完成但沒有賬單
                          else if (paymentNotifier.hasNobills) ...[
                            _buildNoBillsContainer(),
                            const SizedBox(height: 16),
                          ],
                        ],

                        // 如果有選中的賬單且總金額大於1分錢，顯示支付方式選擇
                        if (paymentState.selectedBills.isNotEmpty &&
                            paymentNotifier.cartTotalAmount >= 0.01) ...[
                          _buildPaymentMethodContainer(
                              paymentNotifier, paymentState),
                          const SizedBox(height: 16),
                        ],

                        // 如果選擇了支付方式且總金額大於1分錢，顯示費用計算
                        if (_selectedPaymentMethod != null &&
                            paymentState.selectedBills.isNotEmpty &&
                            paymentNotifier.cartTotalAmount >= 0.01) ...[
                          _buildAmountCalculationContainer(
                              paymentNotifier, paymentState),
                          const SizedBox(height: 16),
                        ],

                        // 結賬按鈕
                        if (paymentState.selectedBills.isNotEmpty &&
                            paymentNotifier.cartTotalAmount >= 0.01)
                          _buildCheckoutButton(paymentNotifier, paymentState),

                        const SizedBox(height: 16),

                        // 支付處理狀態
                        if (paymentState.status == PaymentStatus.processing)
                          _buildPaymentProcessingContainer(
                              paymentNotifier, paymentState),

                        // 支付成功狀態
                        if (paymentState.status == PaymentStatus.success)
                          _buildPaymentSuccessContainer(
                              paymentNotifier, paymentState),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ), // 27, 關閉Listener
    );
  }

  /// 25, 構建賬單信息容器（只顯示，不允許選擇）
  Widget _buildBillInfoContainer(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '該單位的待繳費賬單',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          // 33, 移除空賬單檢查，因為這裡只在有賬單時才會調用
          ...paymentState.bills.map((bill) => _buildBillInfoItem(bill)),
        ],
      ),
    );
  }

  /// 26, 構建賬單信息項目（只顯示）
  Widget _buildBillInfoItem(PaymentBill bill) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  bill.itemId,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Text(
                'HK\$${bill.netAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '期間：${bill.trsTo}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          Text(
            '發票號：${bill.invoiceNo}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  /// 27, 構建支付功能不可用提示
  Widget _buildPaymentUnavailableNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.orange.shade600,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            '支付功能暫未開通',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Payment Feature Not Available',
            style: TextStyle(
              fontSize: 14,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '該大廈尚未開通微信/支付寶支付功能',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 2, 構建支付選擇器容器
  Widget _buildPaymentSelectorContainer(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 當前大廈顯示
          _buildCurrentBuildingDisplay(paymentState),

          const SizedBox(height: 16),

          // 樓座選擇器（如果有多個樓座）
          if (paymentNotifier.shouldShowBlockSelector) ...[
            _buildBlockSelector(paymentNotifier, paymentState),
            const SizedBox(height: 18),
          ],

          // 樓層選擇器
          _buildFloorSelector(paymentNotifier, paymentState),

          const SizedBox(height: 18),

          // 單位選擇器
          _buildUnitSelector(paymentNotifier, paymentState),
        ],
      ),
    );
  }

  Widget _buildPaymentSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.15,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildPaymentOptionChip({
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 66,
            minHeight: 50,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? primaryColor : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: isSelected ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentEmptyHint(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// 3, 構建當前大廈顯示
  Widget _buildCurrentBuildingDisplay(PaymentState paymentState) {
    return Consumer<AppDataProvider>(
      builder: (context, appDataProvider, child) {
        final buildingInfo = appDataProvider.buildingInfo;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.business,
                color: Theme.of(context).colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '當前大廈：${buildingInfo?.name ?? '未選擇'}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 4, 構建樓座選擇器
  Widget _buildBlockSelector(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    final blocks = paymentNotifier.blocks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPaymentSectionTitle('選擇樓座'),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.start,
          spacing: 10,
          runSpacing: 10,
          children: blocks.map((block) {
            final isSelected = _selectedBlock == block;
            return _buildPaymentOptionChip(
              text: '$block座',
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  _selectedBlock = block;
                  _selectedFloor = null;
                  _selectedUnit = null;
                  _selectedPaymentMethod = null;
                });
                paymentNotifier.clearCart();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 5, 構建樓層選擇器
  Widget _buildFloorSelector(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    final floors = _selectedBlock != null
        ? paymentNotifier.getFloorsByBlock(_selectedBlock!)
        : paymentNotifier.floors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPaymentSectionTitle('選擇樓層'),
        const SizedBox(height: 12),
        if (floors.isEmpty) ...[
          _buildPaymentEmptyHint(
            paymentNotifier.shouldShowBlockSelector ? '請先選擇樓座' : '暫無樓層數據',
          ),
        ] else ...[
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 10,
            runSpacing: 10,
            children: floors.map((floor) {
              final isSelected = _selectedFloor == floor;
              return _buildPaymentOptionChip(
                text: floor,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedFloor = floor;
                    _selectedUnit = null;
                    _selectedPaymentMethod = null;
                  });
                  paymentNotifier.clearCart();
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  /// 6, 構建單位選擇器
  Widget _buildUnitSelector(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    List<UnitInfo> units = [];

    // 只有在選擇了樓層時才顯示單位
    if (_selectedFloor != null) {
      if (_selectedBlock != null) {
        units = paymentNotifier.getUnitsByBlockAndFloor(
            _selectedBlock!, _selectedFloor!);
      } else {
        units = paymentNotifier.getUnitsByFloor(_selectedFloor!);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPaymentSectionTitle('選擇單位'),
        const SizedBox(height: 12),
        if (_selectedFloor == null) ...[
          _buildPaymentEmptyHint('請先選擇樓層'),
        ] else if (units.isEmpty) ...[
          _buildPaymentEmptyHint('暫無單位數據'),
        ] else ...[
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 10,
            runSpacing: 10,
            children: units.map((unit) {
              final isSelected = _selectedUnit == unit.unitId;
              return _buildPaymentOptionChip(
                text: unit.unitName,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedUnit = unit.unitId;
                    _selectedPaymentMethod = null;
                  });
                  paymentNotifier.selectUnit(unit.unitId);
                  paymentNotifier.clearCart();
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  /// 7, 構建賬單選擇容器
  Widget _buildBillSelectionContainer(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    // 49, 显示所有账单（包括0元账单），但0元账单不可选中
    final billsToShow = paymentState.bills;
    // 过滤出可以缴费的账单（金额大于1分钱）用于全选功能
    final payableBills =
        paymentState.bills.where((bill) => bill.netAmount >= 0.01).toList();
    final allPayableSelected = payableBills.isNotEmpty &&
        paymentState.selectedBills.length == payableBills.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '選擇需要繳費的賬單',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              // 39, 只有當有可繳費賬單時才顯示全選按鈕
              if (payableBills.isNotEmpty)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _toggleAllPayableBills(
                    paymentNotifier,
                    paymentState,
                    payableBills,
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: allPayableSelected,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeColor: Theme.of(context).colorScheme.primary,
                          onChanged: (_) => _toggleAllPayableBills(
                            paymentNotifier,
                            paymentState,
                            payableBills,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '全選',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBillTable(paymentNotifier, billsToShow),
          // 43, 當選中的賬單總金額為0時，顯示「暫時沒有賬單可以支付」提示
          if (paymentState.selectedBills.isNotEmpty &&
              paymentNotifier.cartTotalAmount < 0.01) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '暫時沒有賬單可以支付（已選中的賬單金額為0）',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleAllPayableBills(
    PaymentNotifier paymentNotifier,
    PaymentState paymentState,
    List<PaymentBill> payableBills,
  ) {
    if (paymentState.selectedBills.length == payableBills.length) {
      paymentNotifier.clearCart();
    } else {
      // 42, 一次性選擇所有金額大於0的賬單
      paymentNotifier.selectBillsFromList(payableBills);
    }
  }

  Widget _buildBillTable(
    PaymentNotifier paymentNotifier,
    List<PaymentBill> bills,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildBillTableHeader(),
          ...bills.map((bill) => _buildBillItem(paymentNotifier, bill)),
        ],
      ),
    );
  }

  Widget _buildBillTableHeader() {
    return Container(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: const Row(
        children: [
          SizedBox(width: 38),
          Expanded(
            flex: 10,
            child: Text(
              '管理費',
              style: _billTableHeaderTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: Text(
              '期間',
              style: _billTableHeaderTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 15,
            child: Text(
              '發票號碼',
              style: _billTableHeaderTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            flex: 10,
            child: Text(
              '金額',
              style: _billTableHeaderTextStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 8, 構建賬單項目
  Widget _buildBillItem(PaymentNotifier paymentNotifier, PaymentBill bill) {
    final isSelected = paymentNotifier.state.selectedBills
        .any((b) => b.invoiceNo == bill.invoiceNo);
    // 55, 使用更严格的判断条件处理浮点数精度问题
    // 小于1分钱（0.01）的都视为0元账单
    final isZeroAmount = bill.netAmount < 0.01;

    final textColor = isZeroAmount ? Colors.grey : Colors.black87;
    final amountColor = isZeroAmount ? Colors.grey : Colors.red.shade700;

    return InkWell(
      onTap: isZeroAmount
          ? null
          : () {
              if (isSelected) {
                paymentNotifier.removeBillFromCart(bill);
              } else {
                paymentNotifier.addBillToCart(bill);
              }
            },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
              : Colors.white,
          border: Border(
            top: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Checkbox(
                value: isZeroAmount ? false : isSelected,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: isZeroAmount
                    ? null
                    : (bool? value) {
                        // 57, 0元账单完全禁用
                        if (value == true) {
                          paymentNotifier.addBillToCart(bill);
                        } else {
                          paymentNotifier.removeBillFromCart(bill);
                        }
                      },
              ),
            ),
            Expanded(
              flex: 10,
              child: Text(
                bill.itemId,
                style: _billTableCellTextStyle.copyWith(color: textColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 10,
              child: Text(
                bill.trsTo,
                style: _billTableCellTextStyle.copyWith(color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 15,
              child: Text(
                bill.invoiceNo,
                style: _billTableCellTextStyle.copyWith(color: textColor),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 10,
              child: Text(
                'HK\$${bill.netAmount.toStringAsFixed(2)}',
                style: _billTableAmountTextStyle.copyWith(color: amountColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 9, 構建支付方式選擇容器
  Widget _buildPaymentMethodContainer(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '選擇支付方式',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPaymentMethodOption(PaymentMethod.wechat, '微信支付',
                  paymentState.paymentConfig, paymentNotifier),
              _buildPaymentMethodOption(PaymentMethod.alipay, '支付寶',
                  paymentState.paymentConfig, paymentNotifier),
              _buildPaymentMethodOption(PaymentMethod.unionpay, '雲閃付',
                  paymentState.paymentConfig, paymentNotifier),
            ],
          ),
          // 選擇支付寶時顯示 AlipayHK 提示
          if (_selectedPaymentMethod == PaymentMethod.alipay) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.orange.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '該支付方式僅支持 AlipayHK（支付寶香港）',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 10, 構建支付方式選項
  Widget _buildPaymentMethodOption(PaymentMethod method, String displayName,
      PaymentConfig? config, PaymentNotifier paymentNotifier) {
    final isSelected = _selectedPaymentMethod == method;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
        });

        // 如果当前已经有二维码显示（处于支付处理状态），自动刷新二维码
        if (paymentNotifier.state.status == PaymentStatus.processing &&
            paymentNotifier.state.paymentResponse != null &&
            paymentNotifier.state.selectedBills.isNotEmpty) {
          // 立即清除旧的二维码并显示加载状态
          paymentNotifier.clearPaymentResponse();

          // 确保UI先更新显示加载状态，然后再创建新订单
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _handleCheckout(paymentNotifier);
              }
            });
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  method == PaymentMethod.wechat
                      ? Icons.wechat
                      : method == PaymentMethod.unionpay
                          ? Icons.credit_card
                          : Icons.payment,
                  color: isSelected ? Colors.white : Colors.black87,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 11, 構建金額計算容器
  Widget _buildAmountCalculationContainer(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    final billAmount = paymentNotifier.cartTotalAmount;

    // 41, 使用新公式計算總金額：總金額 = 賬單金額 ÷ (1 - 費率)
    final totalAmount = _selectedPaymentMethod != null &&
            paymentState.paymentConfig != null
        ? paymentState.paymentConfig!
            .getTotalAmount(paymentState.selectedBills, _selectedPaymentMethod!)
        : billAmount;
    // 手續費 = 總金額 - 賬單金額
    final handlingFee = totalAmount - billAmount;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '費用明細',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          _buildAmountLine(
            label: '賬單費用：',
            amount: 'HK\$${billAmount.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),
          _buildAmountLine(
            label:
                '手續費${_selectedPaymentMethod != null && paymentState.paymentConfig != null ? '(${paymentState.paymentConfig!.getFeeRatePercentage(_selectedPaymentMethod!).toStringAsFixed(2)}%)' : ''}：',
            amount: 'HK\$${handlingFee.toStringAsFixed(2)}',
          ),
          const Divider(),
          _buildAmountLine(
            label: '總計：',
            amount: 'HK\$${totalAmount.toStringAsFixed(2)}',
            labelStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            amountStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountLine({
    required String label,
    required String amount,
    TextStyle? labelStyle,
    TextStyle? amountStyle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: labelStyle,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: amountStyle,
            ),
          ),
        ),
      ],
    );
  }

  /// 12, 構建結賬按鈕
  Widget _buildCheckoutButton(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    final canCheckout =
        _selectedPaymentMethod != null && paymentState.selectedBills.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canCheckout ? () => _handleCheckout(paymentNotifier) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canCheckout
              ? Theme.of(context).primaryColor
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: canCheckout ? Colors.white : Colors.black87,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: canCheckout ? 2 : 0,
        ),
        child: const Text(
          '結賬',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 13, 處理結賬
  void _handleCheckout(PaymentNotifier paymentNotifier) {
    // 28, 啟用實際支付功能
    if (_selectedPaymentMethod == null) return;

    switch (_selectedPaymentMethod!) {
      case PaymentMethod.wechat:
        paymentNotifier.createWechatPayment(
            selectedBills: paymentNotifier.state.selectedBills);
        break;
      case PaymentMethod.alipay:
        paymentNotifier.createAlipayPayment(
            selectedBills: paymentNotifier.state.selectedBills);
        break;
      case PaymentMethod.unionpay:
        paymentNotifier.createUnionpayPayment(
            selectedBills: paymentNotifier.state.selectedBills);
        break;
      default:
        break;
    }

    // 15, 顯示開發中訊息而不執行實際支付 (已注釋)
    // if (_selectedPaymentMethod == null) return;
    // setState(() {
    //   _showDevelopmentMessage = true;
    // });

    // 16, 3秒後自動隱藏訊息 (已注釋)
    // Timer(const Duration(seconds: 3), () {
    //   if (mounted) {
    //     setState(() {
    //       _showDevelopmentMessage = false;
    //     });
    //   }
    // });

    // 17, 註釋掉實際的支付邏輯
    // switch (_selectedPaymentMethod!) {
    //   case PaymentMethod.wechat:
    //     paymentNotifier.createWechatPayment(
    //         selectedBills: paymentNotifier.state.selectedBills);
    //     break;
    //   case PaymentMethod.alipay:
    //     paymentNotifier.createAlipayPayment(
    //         selectedBills: paymentNotifier.state.selectedBills);
    //     break;
    //   default:
    //     break;
    // }
  }

  /// 15, 構建支付處理容器
  Widget _buildPaymentProcessingContainer(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    // 17, 如果已經有二維碼，只顯示二維碼，不顯示處理中狀態
    final hasQrCode = paymentState.paymentResponse?.qrCode != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (hasQrCode) ...[
            // 只顯示二維碼，不顯示處理中的加載動畫
            const Text(
              '請掃描二維碼完成支付',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            QrImageView(
              data: paymentState.paymentResponse!.qrCode!,
              version: QrVersions.auto,
              size: 200.0,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // 19, 取消支付並重置所有選擇
                paymentNotifier.cancelPayment();
                setState(() {
                  _selectedPaymentMethod = null;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey,
                foregroundColor: Colors.white,
              ),
              child: const Text('取消支付'),
            ),
          ] else ...[
            // 沒有二維碼時顯示處理中狀態
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text(
              '正在創建訂單...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 16, 構建支付成功容器
  Widget _buildPaymentSuccessContainer(
      PaymentNotifier paymentNotifier, PaymentState paymentState) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            '支付成功！',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '交易編號：${paymentState.paymentResponse?.transactionId ?? ''}',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 112),
                child: ElevatedButton.icon(
                  onPressed: () {
                    // 這裡可以添加打印小票的邏輯
                  },
                  icon: const Icon(Icons.print),
                  label: const Text(
                    '打印小票',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 96),
                child: ElevatedButton.icon(
                  onPressed: () {
                    // 18, 支付完成後重置狀態，保留大廈配置，清除選擇狀態
                    paymentNotifier.resetAfterPaymentComplete();
                    setState(() {
                      _selectedPaymentMethod = null;
                      _selectedBlock = null;
                      _selectedFloor = null;
                      _selectedUnit = null;
                    });
                  },
                  icon: const Icon(Icons.check),
                  label: const Text(
                    '完成',
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 17, 構建支付功能不可用頁面（類似便利服務的 UI）
  Widget _buildPaymentNotAvailablePage() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/payment.png',
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // 如果圖片加載失敗，顯示備用內容
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.payment,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '電子繳費',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Electronic Payment',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF757575),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '該大廈尚未開通微信/支付寶支付功能',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 34, 構建账单加载容器
  Widget _buildBillLoadingContainer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '該單位的待繳費账单',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                SizedBox(height: 12),
                Text(
                  '正在加载账单...',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 35, 構建無账单容器
  Widget _buildNoBillsContainer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '該單位的待繳費账单',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.receipt_outlined,
                  size: 48,
                  color: Colors.grey,
                ),
                SizedBox(height: 12),
                Text(
                  '暫無待繳費账单',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '該單位目前沒有待繳費的账单',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

@visibleForTesting
PaymentWidgetViewMode determinePaymentWidgetViewMode(PaymentState state) {
  if (state.isLoading && state.paymentConfig == null) {
    return PaymentWidgetViewMode.initializing;
  }

  final hasEnabledPaymentMethods =
      state.paymentConfig?.enabledMethods.isNotEmpty == true;
  if (!hasEnabledPaymentMethods) {
    return state.units.isEmpty
        ? PaymentWidgetViewMode.unavailable
        : PaymentWidgetViewMode.selectorWithUnavailablePayment;
  }

  return PaymentWidgetViewMode.active;
}
