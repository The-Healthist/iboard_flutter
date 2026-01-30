import 'dart:async'; // 22, 用於Timer無操作計時器
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:iboard_app/providers/payment_provider.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/models/payment_model.dart';

class PaymentWidget extends StatefulWidget {
  final VoidCallback? onIdleTimeout; // 20, 無操作超時回調
  
  const PaymentWidget({super.key, this.onIdleTimeout});

  @override
  State<PaymentWidget> createState() => _PaymentWidgetState();
}

class _PaymentWidgetState extends State<PaymentWidget> {
  final Logger _logger = Logger();
  String? _selectedBlock;
  String? _selectedFloor;
  String? _selectedUnit;
  PaymentMethod? _selectedPaymentMethod;
  
  // 21, 無操作計時器相關
  Timer? _idleTimer;
  static const _idleTimeout = Duration(seconds: 100); // 100秒無操作超時
  // 14, 暫時注釋掉開發中訊息變數
  // bool _showDevelopmentMessage = false; // 是否顯示開發中訊息

  @override
  void initState() {
    super.initState();
    // 22, 啟動無操作計時器
    _startIdleTimer();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 進入時清空殘留的購物車與支付方式
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

      // 2, 檢查是否需要初始化支付
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      final ismartId = appDataProvider.buildingInfo?.ismartId;

      if (ismartId != null && ismartId.isNotEmpty) {
        // 如果有 ismartId，嘗試初始化支付
        debugPrint('[PaymentWidget] 🚀 自動初始化支付流程，ismartId: $ismartId');
        try {
          final notifier = context.read<PaymentNotifier>();
          if (notifier.state.paymentConfig == null) {
            notifier.initializePayment(buildingId: ismartId);
          }
        } catch (e) {
          debugPrint('[PaymentWidget] ❌ 自動初始化失敗: $e');
        }
      } else {
        debugPrint('[PaymentWidget] ⚠️ 沒有 ismartId，無法自動初始化');
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
    _idleTimer = Timer(_idleTimeout, () {
      debugPrint('⏰ [PaymentWidget] 100秒無操作，自動返回輪播');
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
    debugPrint('[PaymentWidget] 🏢 開始初始化支付流程');
    debugPrint(
        '[PaymentWidget] 📋 大廈信息: ismartId=$ismartId, name=$buildingName');

    if (ismartId != null && ismartId.isNotEmpty) {
      _logger.i('🏢 [PaymentWidget] 使用 ismartId 初始化支付: $ismartId');
      debugPrint('[PaymentWidget] ✅ 找到ismartId，開始初始化支付');
      context.read<PaymentNotifier>().initializePayment(buildingId: ismartId);
    } else {
      _logger.w('⚠️ [PaymentWidget] 未找到 ismartId，无法初始化支付');
      debugPrint('[PaymentWidget] ❌ 未找到ismartId，無法初始化支付');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('未找到大廈信息，請先登錄'),
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

        // 根據載入狀態決定顯示內容
        if (paymentState.isLoading && paymentState.paymentConfig == null) {
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
        if (paymentState.paymentConfig == null || 
            (paymentState.paymentConfig?.enabledMethods.isEmpty ?? true)) {
          // 如果沒有單位數據，顯示背景圖
          if (paymentState.units.isEmpty) {
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
                        _buildPaymentSelectorContainer(paymentNotifier, paymentState),
                        const SizedBox(height: 16),
                        
                        // 如果選擇了單位且有賬單，顯示賬單信息但不允許選擇
                        if (_selectedUnit != null && paymentState.bills.isNotEmpty) ...[
                          _buildBillInfoContainer(paymentNotifier, paymentState),
                          const SizedBox(height: 16),
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
                      _buildPaymentSelectorContainer(paymentNotifier, paymentState),

                      const SizedBox(height: 16),

                      // 如果選擇了單位且有賬單，顯示賬單選擇
                      if (_selectedUnit != null && paymentState.bills.isNotEmpty) ...[
                        _buildBillSelectionContainer(paymentNotifier, paymentState),
                        const SizedBox(height: 16),
                      ],

                      // 如果有選中的賬單，顯示支付方式選擇
                      if (paymentState.selectedBills.isNotEmpty) ...[
                        _buildPaymentMethodContainer(paymentNotifier, paymentState),
                        const SizedBox(height: 16),
                      ],

                      // 如果選擇了支付方式，顯示費用計算
                      if (_selectedPaymentMethod != null && 
                          paymentState.selectedBills.isNotEmpty) ...[
                        _buildAmountCalculationContainer(paymentNotifier, paymentState),
                        const SizedBox(height: 16),
                      ],

                      // 結賬按鈕
                      if (paymentState.selectedBills.isNotEmpty)
                        _buildCheckoutButton(paymentNotifier, paymentState),

                      const SizedBox(height: 16),

                      // 支付處理狀態
                      if (paymentState.status == PaymentStatus.processing)
                        _buildPaymentProcessingContainer(paymentNotifier, paymentState),

                      // 支付成功狀態
                      if (paymentState.status == PaymentStatus.success)
                        _buildPaymentSuccessContainer(paymentNotifier, paymentState),
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
            color: Colors.black.withOpacity(0.05),
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
          if (paymentState.bills.isEmpty) ...[
            const Center(
              child: Text(
                '暫無待繳費賬單',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ),
          ] else ...[
            ...paymentState.bills
                .map((bill) => _buildBillInfoItem(bill)),
          ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
            const SizedBox(height: 16),
          ],

          // 樓層選擇器
          _buildFloorSelector(paymentNotifier, paymentState),

          const SizedBox(height: 16),

          // 單位選擇器
          _buildUnitSelector(paymentNotifier, paymentState),
        ],
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.business,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '當前大廈：${buildingInfo?.name ?? '未選擇'}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
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
        const Text(
          '選擇樓座',
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
          children: blocks.map((block) {
            final isSelected = _selectedBlock == block;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedBlock = block;
                  _selectedFloor = null;
                  _selectedUnit = null;
                  _selectedPaymentMethod = null;
                });
                paymentNotifier.clearCart();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                  ),
                ),
                child: Text(
                  '${block}座',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
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
        const Text(
          '選擇樓層',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        if (floors.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                paymentNotifier.shouldShowBlockSelector ? '請先選擇樓座' : '暫無樓層數據',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ] else ...[
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: floors.map((floor) {
              final isSelected = _selectedFloor == floor;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedFloor = floor;
                    _selectedUnit = null;
                    _selectedPaymentMethod = null;
                  });
                  paymentNotifier.clearCart();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    floor, // 只顯示樓層數字，不顯示"樓"字
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
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
        const Text(
          '選擇單位',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedFloor == null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                '請先選擇樓層',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ] else if (units.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Text(
                '暫無單位數據',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ] else ...[
          Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: units.map((unit) {
              final isSelected = _selectedUnit == unit.unitId;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedUnit = unit.unitId;
                    _selectedPaymentMethod = null;
                  });
                  paymentNotifier.selectUnit(unit.unitId);
                  paymentNotifier.clearCart();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    unit.unitName, // 只顯示單位號碼，不顯示樓層信息
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (paymentState.bills.isNotEmpty)
                TextButton(
                  onPressed: () {
                    if (paymentState.selectedBills.length ==
                        paymentState.bills.length) {
                      paymentNotifier.clearCart();
                    } else {
                      paymentNotifier.selectAllBills();
                    }
                  },
                  child: Text(
                    paymentState.selectedBills.length ==
                            paymentState.bills.length
                        ? '取消全選'
                        : '全選',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ...paymentState.bills
              .map((bill) => _buildBillItem(paymentNotifier, bill)),
        ],
      ),
    );
  }

  /// 8, 構建賬單項目
  Widget _buildBillItem(PaymentNotifier paymentNotifier, PaymentBill bill) {
    final isSelected = paymentNotifier.state.selectedBills
        .any((b) => b.invoiceNo == bill.invoiceNo);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (bool? value) {
          if (value == true) {
            paymentNotifier.addBillToCart(bill);
          } else {
            paymentNotifier.removeBillFromCart(bill);
          }
        },
        title: Text(
          bill.itemId,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('期間：${bill.trsTo}'),
            Text('金額：HK\$${bill.netAmount.toStringAsFixed(2)}'),
            Text('發票號：${bill.invoiceNo}'),
          ],
        ),
        secondary: Text(
          'HK\$${bill.netAmount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        activeColor: Theme.of(context).colorScheme.primary,
        contentPadding: EdgeInsets.zero,
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
            color: Colors.black.withOpacity(0.05),
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
              _buildPaymentMethodOption(
                  PaymentMethod.wechat, '微信支付', paymentState.paymentConfig),
              _buildPaymentMethodOption(
                  PaymentMethod.alipay, '支付寶', paymentState.paymentConfig),
              _buildPaymentMethodOption(
                  PaymentMethod.unionpay, '雲閃付', paymentState.paymentConfig),
            ],
          ),
        ],
      ),
    );
  }

  /// 10, 構建支付方式選項
  Widget _buildPaymentMethodOption(
      PaymentMethod method, String displayName, PaymentConfig? config) {
    final isSelected = _selectedPaymentMethod == method;

    // 調試信息
    debugPrint(
        '[PaymentWidget] 💳 支付方式: $displayName, 配置: ${config?.feeRates}');

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
        });
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
    final handlingFee = _selectedPaymentMethod != null &&
            paymentState.paymentConfig != null
        ? paymentState.paymentConfig!
            .getTotalFee(paymentState.selectedBills, _selectedPaymentMethod!)
        : 0.0;
    final totalAmount = billAmount + handlingFee;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('賬單費用：'),
              Text('HK\$${billAmount.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  '手續費${_selectedPaymentMethod != null && paymentState.paymentConfig != null ? '(${paymentState.paymentConfig!.getFeeRatePercentage(_selectedPaymentMethod!).toStringAsFixed(2)}%)' : ''}：'),
              Text('HK\$${handlingFee.toStringAsFixed(2)}'),
            ],
          ),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '總計：',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'HK\$${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
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
              : Theme.of(context).colorScheme.primary.withOpacity(0.12),
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

  /// 14, 構建開發中訊息容器
  Widget _buildDevelopmentMessageContainer() {
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
            Icons.construction,
            color: Colors.orange.shade600,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            '支付功能正在開發中',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Payment Feature Under Development',
            style: TextStyle(
              fontSize: 14,
              color: Colors.orange.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '敬請期待後續更新',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange.shade600,
            ),
          ),
        ],
      ),
    );
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
            color: Colors.black.withOpacity(0.05),
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
          Icon(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  // 這裡可以添加打印小票的邏輯
                },
                icon: const Icon(Icons.print),
                label: const Text('打印小票'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // 18, 重置支付狀態，返回初始頁面
                  paymentNotifier.resetPayment();
                  setState(() {
                    _selectedPaymentMethod = null;
                    _selectedBlock = null;
                    _selectedFloor = null;
                    _selectedUnit = null;
                  });
                },
                icon: const Icon(Icons.check),
                label: const Text('完成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
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
}
