import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iboard_app/http/payment.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/payment_model.dart';

/// 支付狀態通知器
class PaymentNotifier extends ChangeNotifier {
  final Logger _logger = Logger();
  late final PaymentClient _paymentClient;
  ApiClient? _apiClient;
  Timer? _paymentStatusTimer;

  PaymentState _state = const PaymentState();
  PaymentState get state => _state;

  PaymentNotifier() {
    _paymentClient = PaymentClient();
  }

  /// 21, 保存支付記錄
  Future<void> _savePaymentRecord(PaymentResponse paymentResponse) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paymentRecords = prefs.getStringList('payment_records') ?? [];

      final recordData = {
        'payment_id': paymentResponse.paymentId,
        'transaction_id': paymentResponse.transactionId,
        'status': paymentResponse.status.name,
        'created_at': paymentResponse.createdAt?.toIso8601String(),
        'completed_at': paymentResponse.completedAt?.toIso8601String(),
        'building_id': state.selectedBuildingId,
        'unit_id': state.selectedUnitId,
        'building_name': _getBuildingName(),
        'unit_name': _getUnitName(),
        'bills_count': state.selectedBills.length,
        'total_amount': _calculateTotalAmount(),
      };

      paymentRecords.insert(0, json.encode(recordData));

      // 只保留最近50條記錄
      if (paymentRecords.length > 50) {
        paymentRecords.removeRange(50, paymentRecords.length);
      }

      await prefs.setStringList('payment_records', paymentRecords);
    } catch (e) {
      _logger.w(' [PaymentProvider] 保存支付記錄失敗: $e');
    }
  }

  /// 22, 獲取支付歷史記錄
  Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paymentRecords = prefs.getStringList('payment_records') ?? [];

      final history = <Map<String, dynamic>>[];
      for (final record in paymentRecords) {
        try {
          final decoded = json.decode(record);
          final normalized = _nullableMap(decoded);
          if (normalized != null) {
            history.add(normalized);
          }
        } catch (_) {
          // 忽略單條損壞記錄，保留其它可用歷史
        }
      }
      return history;
    } catch (e) {
      return [];
    }
  }

  /// 1, 初始化支付流程
  Future<void> initializePayment({String? buildingId}) async {
    _updateState(state.copyWith(
      status: PaymentStatus.pending,
      errorMessage: null,
    ));

    // 如果提供了 buildingId，直接加载该大厦的单位
    if (buildingId != null && buildingId.isNotEmpty) {
      await selectBuilding(buildingId);
    }
  }

  /// 2, 載入大廈列表
  Future<void> loadBuildingList() async {
    try {
      _updateState(state.copyWith(isLoading: true));

      final buildings = await _paymentClient.getBuildingList();

      _updateState(state.copyWith(
        isLoading: false,
        buildings: buildings.map((b) => BuildingInfo.fromMap(b)).toList(),
      ));
    } catch (e) {
      _logger.e(' [PaymentProvider] 載入大廈列表失敗: $e');
      _updateState(state.copyWith(
        isLoading: false,
        errorMessage: '載入大廈列表失敗: $e',
      ));
    }
  }

  /// 3, 選擇大廈並載入單位
  Future<void> selectBuilding(String buildingId) async {
    try {
      _updateState(state.copyWith(
        selectedBuildingId: buildingId,
        isLoading: true,
        selectedUnitId: null,
        bills: [],
      ));

      // 載入大廈單位列表
      final units =
          await _paymentClient.getBuildingFlatUnits(blgId: buildingId);

      final unitInfos = units.map((u) => UnitInfo.fromJson(u)).toList();

      // 先更新單位數據，使用默認支付配置
      _updateState(state.copyWith(
        isLoading: false,
        units: unitInfos,
        paymentConfig: PaymentConfig.defaultConfig(buildingId),
      ));

      // getBuildingTransactionTypes
      try {
        final config =
            await _paymentClient.getBuildingTransactionTypes(blgId: buildingId);

        final paymentConfig = PaymentConfig.fromJson(config);

        _updateState(state.copyWith(paymentConfig: paymentConfig));
      } catch (e) {
        // 如果 API 調用失敗，創建一個空的配置，這樣會顯示支付功能不可用頁面
        final emptyConfig = PaymentConfig(
          buildingId: buildingId,
          enabledMethods: [],
          feeRates: {},
        );
        _updateState(state.copyWith(paymentConfig: emptyConfig));
      }
    } catch (e) {
      _logger.e(' [PaymentProvider] 選擇大廈失敗: $e');
      _updateState(state.copyWith(
        isLoading: false,
        errorMessage: '選擇大廈失敗: $e',
      ));
    }
  }

  /// 4, 獲取所有樓層列表（類似 arrear_provider 的處理方式）
  List<String> get floors {
    final floorNames = <String>{};

    for (final unit in state.units) {
      if (unit.floorName.isNotEmpty) {
        floorNames.add(unit.floorName);
      }
    }

    // 排序：字母樓層在前，數字樓層在後
    return floorNames.toList()
      ..sort((a, b) {
        // 檢查是否為字母樓層（第一個字符是字母）
        final aIsLetter = a.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a[0]);
        final bIsLetter = b.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b[0]);

        // 如果一個是字母一個是數字，字母排在前面
        if (aIsLetter && !bIsLetter) return -1;
        if (!aIsLetter && bIsLetter) return 1;

        // 如果都是字母或都是數字，按正常排序
        return a.compareTo(b);
      });
  }

  /// 5, 獲取指定樓層的所有單位
  List<UnitInfo> getUnitsByFloor(String floorName) {
    final units =
        state.units.where((unit) => unit.floorName == floorName).toList();

    // 排序：字母單位在前，數字單位在後
    units.sort((a, b) {
      // 檢查是否為字母單位（第一個字符是字母）
      final aIsLetter =
          a.unitName.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a.unitName[0]);
      final bIsLetter =
          b.unitName.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b.unitName[0]);

      // 如果一個是字母一個是數字，字母排在前面
      if (aIsLetter && !bIsLetter) return -1;
      if (!aIsLetter && bIsLetter) return 1;

      // 如果都是字母或都是數字，按正常排序
      return a.unitName.compareTo(b.unitName);
    });

    return units;
  }

  /// 6, 獲取所有樓座列表（如果有多個樓座）
  List<String> get blocks {
    final blockNames = <String>{};

    for (final unit in state.units) {
      if (unit.blockName.isNotEmpty) {
        blockNames.add(unit.blockName);
      }
    }

    // 排序：數字樓座在前，字母樓座在後
    return blockNames.toList()
      ..sort((a, b) {
        final aIsNumber = a.isNotEmpty && RegExp(r'^[0-9]').hasMatch(a[0]);
        final bIsNumber = b.isNotEmpty && RegExp(r'^[0-9]').hasMatch(b[0]);

        if (aIsNumber && !bIsNumber) return -1;
        if (!aIsNumber && bIsNumber) return 1;

        return a.compareTo(b);
      });
  }

  /// 7, 獲取指定樓座的樓層列表
  List<String> getFloorsByBlock(String blockName) {
    final floorNames = <String>{};

    for (final unit in state.units) {
      if (unit.blockName == blockName && unit.floorName.isNotEmpty) {
        floorNames.add(unit.floorName);
      }
    }

    // 排序：字母樓層在前，數字樓層在後
    return floorNames.toList()
      ..sort((a, b) {
        final aIsLetter = a.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a[0]);
        final bIsLetter = b.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b[0]);

        if (aIsLetter && !bIsLetter) return -1;
        if (!aIsLetter && bIsLetter) return 1;

        return a.compareTo(b);
      });
  }

  /// 8, 獲取指定樓座和樓層的單位列表
  List<UnitInfo> getUnitsByBlockAndFloor(String blockName, String floorName) {
    final units = state.units
        .where((unit) =>
            unit.blockName == blockName && unit.floorName == floorName)
        .toList();

    // 排序：字母單位在前，數字單位在後
    units.sort((a, b) {
      final aIsLetter =
          a.unitName.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(a.unitName[0]);
      final bIsLetter =
          b.unitName.isNotEmpty && RegExp(r'^[a-zA-Z]').hasMatch(b.unitName[0]);

      if (aIsLetter && !bIsLetter) return -1;
      if (!aIsLetter && bIsLetter) return 1;

      return a.unitName.compareTo(b.unitName);
    });

    return units;
  }

  /// 9, 檢查是否應該顯示樓座選擇器
  bool get shouldShowBlockSelector {
    // 只有當有多個非空名稱的樓座時才顯示選擇器
    return blocks.length > 1;
  }

  /// 10, 格式化單位顯示（樓座+樓層+單元）
  String formatUnitDisplay(
      String blockName, String floorName, String unitName) {
    if (blockName.isEmpty) {
      // 如果樓座名稱為空，顯示：XX樓XX室
      return '$floorName樓$unitName室';
    } else {
      // 顯示樓座+樓層+單元，例如：01座01樓A室
      return '$blockName座$floorName樓$unitName室';
    }
  }

  /// 11, 選擇單位並載入待繳費帳單
  Future<void> selectUnit(String unitId) async {
    try {
      // 27, 開始加載账单時設置專門的账单加載狀態
      _updateState(state.copyWith(
        selectedUnitId: unitId,
        isLoadingBills: true,
        bills: [],
        selectedBills: [], //清空選中的繳費table
        errorMessage: null, // 清除之前的錯誤信息
      ));

      // 載入待繳費帳單
      final bills =
          await _paymentClient.getBuildingFlatUnitBills(unitId: unitId);

      // 28, 加載完成後更新账单列表和狀態
      final billList = bills.map((b) => PaymentBill.fromJson(b)).toList();

      _updateState(state.copyWith(
        isLoadingBills: false,
        bills: billList,
      ));
    } catch (e) {
      _logger.e(' [PaymentProvider] 選擇單位失敗: $e');
      _updateState(state.copyWith(
        isLoadingBills: false,
        errorMessage: '載入账单失敗: $e',
      ));
    }
  }

  /// 12, 添加帳單到購物車
  void addBillToCart(PaymentBill bill) {
    final currentBills = List<PaymentBill>.from(state.selectedBills);
    if (!currentBills.any((b) => b.itemId == bill.itemId)) {
      currentBills.add(bill);
      _updateState(state.copyWith(selectedBills: currentBills));
    }
  }

  /// 13, 從購物車移除帳單
  void removeBillFromCart(PaymentBill bill) {
    final currentBills = List<PaymentBill>.from(state.selectedBills);
    currentBills.removeWhere((b) => b.itemId == bill.itemId);
    _updateState(state.copyWith(selectedBills: currentBills));
  }

  /// 14, 清空購物車
  void clearCart() {
    _updateState(state.copyWith(selectedBills: []));
  }

  /// 15, 全選賬單
  void selectAllBills() {
    _updateState(
        state.copyWith(selectedBills: List<PaymentBill>.from(state.bills)));
  }

  /// 15.1, 從指定列表中選擇賬單（用於全選過濾後的賬單）
  void selectBillsFromList(List<PaymentBill> bills) {
    _updateState(state.copyWith(selectedBills: List<PaymentBill>.from(bills)));
  }

  /// 16, 計算購物車總金額
  double get cartTotalAmount {
    return state.selectedBills.fold<double>(
      0.0,
      (sum, bill) => sum + bill.netAmount,
    );
  }

  /// 18, 獲取購物車項目數量
  int get cartItemCount => state.selectedBills.length;

  /// 30, 检查是否正在加载账单
  bool get isLoadingBills => state.isLoadingBills;

  /// 31, 检查是否有账单数据
  bool get hasBills => state.bills.isNotEmpty;

  /// 32, 检查是否已选中单位但没有账单（用于显示"暂无账单"）
  bool get hasNobills =>
      state.selectedUnitId != null &&
      !state.isLoadingBills &&
      state.bills.isEmpty &&
      state.errorMessage == null;

  /// 5, 創建微信支付（線上支付）
  Future<void> createWechatPayment({
    required List<PaymentBill> selectedBills,
    String? remark,
  }) async {
    await _createOnlinePayment(
      PaymentMethod.wechat,
      selectedBills,
      remark,
    );
  }

  /// 6, 創建支付寶支付（線上支付）
  Future<void> createAlipayPayment({
    required List<PaymentBill> selectedBills,
    String? remark,
  }) async {
    await _createOnlinePayment(
      PaymentMethod.alipay,
      selectedBills,
      remark,
    );
  }

  /// 6.1, 創建雲閃付支付（線上支付）
  Future<void> createUnionpayPayment({
    required List<PaymentBill> selectedBills,
    String? remark,
  }) async {
    await _createOnlinePayment(
      PaymentMethod.unionpay,
      selectedBills,
      remark,
    );
  }

  /// 7, 線上支付創建方法
  Future<void> _createOnlinePayment(
    PaymentMethod paymentMethod,
    List<PaymentBill> selectedBills,
    String? remark,
  ) async {
    if (state.selectedBuildingId == null || state.selectedUnitId == null) {
      _updateState(state.copyWith(errorMessage: '請先選擇大廈和單位'));
      return;
    }

    if (_apiClient == null) {
      _logger.e(' [PaymentNotifier] ApiClient 未初始化');
      return;
    }

    try {
      // 清除之前的轮询
      _paymentStatusTimer?.cancel();
      _paymentStatusTimer = null;

      _updateState(state.copyWith(
        status: PaymentStatus.processing,
        isLoading: true,
        errorMessage: null,
        paymentResponse: null, // 清除之前的支付響應
      ));

      // 生成新的訂單號
      final orderNo = _generateOrderNo();

      // 38, 計算總金額（使用新公式：總金額 = 賬單金額 ÷ (1 - 費率)）
      final billAmount =
          selectedBills.fold<double>(0.0, (sum, bill) => sum + bill.netAmount);

      // 使用新方法計算總金額（包含手續費，直接進位）
      final totalAmount =
          state.paymentConfig?.getTotalAmount(selectedBills, paymentMethod) ??
              billAmount;

      // 構建訂單描述
      const subject = '物業管理費繳納';
      final body =
          '${selectedBills.length}筆賬單，總金額：HK\$${totalAmount.toStringAsFixed(2)}';

      Map<String, dynamic> responseData;

      if (paymentMethod == PaymentMethod.wechat) {
        responseData = await _apiClient!.createWechatPayment(
          orderNo: orderNo,
          amount: totalAmount,
          subject: subject,
          body: body,
        );
      } else if (paymentMethod == PaymentMethod.alipay) {
        responseData = await _apiClient!.createAlipayPayment(
          orderNo: orderNo,
          amount: totalAmount,
          subject: subject,
          body: body,
        );
      } else if (paymentMethod == PaymentMethod.unionpay) {
        responseData = await _apiClient!.createUnionpayPayment(
          orderNo: orderNo,
          amount: totalAmount,
          subject: subject,
          body: body,
        );
      } else {
        throw Exception('不支持的支付方式: $paymentMethod');
      }

      final thirdPartyResponse =
          ThirdPartyPaymentResponse.fromJson(responseData);

      // 36, 創建訂單時強制使用processing狀態，不管API返回什麼state
      // 只有輪詢查詢時才根據state判斷是否支付成功
      final paymentResponse = PaymentResponse(
        paymentId: thirdPartyResponse.payOrderId ?? '',
        status: PaymentStatus.processing, // 強制為processing狀態
        transactionId: thirdPartyResponse.transactionId ?? '',
        qrCode: thirdPartyResponse.qrCode,
        createdAt: thirdPartyResponse.createdAt,
        completedAt: null, // 創建時不應該有完成時間
        errorMessage: thirdPartyResponse.errMsg,
      );

      _updateState(state.copyWith(
        isLoading: false,
        status: PaymentStatus.processing,
        paymentResponse: paymentResponse,
        selectedBills: selectedBills,
      ));

      // 開始輪詢支付狀態
      _startNewPaymentStatusPolling(orderNo, paymentMethod);
    } catch (e) {
      _logger.e(' [PaymentProvider] 創建支付失敗: $e');
      _updateState(state.copyWith(
        status: PaymentStatus.failed,
        isLoading: false,
        errorMessage: '創建支付失敗: $e',
      ));
    }
  }

  /// 31, 生成訂單號
  String _generateOrderNo() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'PAY$timestamp$random';
  }

  /// 32, 新的輪詢支付狀態方法
  void _startNewPaymentStatusPolling(String orderNo, PaymentMethod method) {
    String paymentMethodStr; // 45, 添加支付方式字符串

    switch (method) {
      case PaymentMethod.wechat:
      case PaymentMethod.alipay:
        paymentMethodStr = 'wechat_alipay';
        break;
      case PaymentMethod.unionpay:
        paymentMethodStr = 'unionpay';
        break;
      default:
        return;
    }

    _paymentStatusTimer?.cancel();
    _paymentStatusTimer = Timer.periodic(
      const Duration(seconds: 3),
      (timer) async {
        try {
          final responseData = await _apiClient!.queryPaymentStatus(
            orderNo: orderNo,
            paymentMethod: paymentMethodStr, // 46, 傳遞支付方式參數
          );

          final thirdPartyResponse =
              ThirdPartyPaymentResponse.fromJson(responseData);

          // 34, 只有在確實支付成功時才更新為成功狀態（state=2表示支付成功）
          // 根據第三方支付接口：state=0:訂單生成, state=1:支付中, state=2:支付成功, state=3:支付失敗
          if (thirdPartyResponse.state == 2) {
            timer.cancel();
            final paymentResponse = thirdPartyResponse.toPaymentResponse();
            _updateState(state.copyWith(
              status: PaymentStatus.success,
              paymentResponse: paymentResponse,
            ));
            // 保存支付記錄
            await _savePaymentRecord(paymentResponse);
          } else if (thirdPartyResponse.isFailed) {
            timer.cancel();
            final paymentResponse = thirdPartyResponse.toPaymentResponse();
            _updateState(state.copyWith(
              status: PaymentStatus.failed,
              paymentResponse: paymentResponse,
              errorMessage: '支付失敗：${thirdPartyResponse.errMsg}',
            ));
            _logger.e(' [PaymentNotifier] 支付失敗: ${thirdPartyResponse.errMsg}');
          }
        } catch (e) {
          _logger.e(' [PaymentNotifier] 查詢支付狀態失敗: $e');
        }
      },
    );

    // 5分鐘後停止輪詢
    Timer(const Duration(minutes: 5), () {
      _paymentStatusTimer?.cancel();
      if (state.status == PaymentStatus.processing) {
        _updateState(state.copyWith(
          status: PaymentStatus.failed,
          errorMessage: '支付超時，請重新嘗試',
        ));
      }
    });
  }

  /// 9, 停止輪詢支付狀態
  void _stopPaymentStatusPolling() {
    _paymentStatusTimer?.cancel();
    _paymentStatusTimer = null;
  }

  /// 12, 取消支付
  void cancelPayment() {
    _stopPaymentStatusPolling();
    // 37, 取消支付時只清除支付相關狀態，保留選擇器數據（大廈、單位、賬單等）
    // 這樣二維碼會消失，但用戶可以繼續選擇其他支付方式
    _updateState(state.copyWith(
      status: PaymentStatus.pending,
      paymentResponse: null,
      errorMessage: null,
      isLoading: false,
      selectedBills: [], // 清空已選賬單，讓用戶重新選擇
    ));
  }

  /// 13, 重置支付狀態（完全重置，慎用）
  void resetPayment() {
    _stopPaymentStatusPolling();
    _state = const PaymentState();
    notifyListeners();
  }

  /// 48, 支付完成後重置（保留大廈配置，清除選擇狀態）
  /// 用於支付成功後用戶點擊「完成」按鈕時調用
  void resetAfterPaymentComplete() {
    _stopPaymentStatusPolling();
    // 保留 paymentConfig、units 和 selectedBuildingId，只清除支付相關狀態
    _updateState(state.copyWith(
      status: PaymentStatus.pending,
      paymentResponse: null,
      errorMessage: null,
      isLoading: false,
      isLoadingBills: false,
      selectedUnitId: null,
      selectedBills: [],
      bills: [],
      receiptData: null,
    ));
  }

  /// 44, 清除支付響應（保持處理狀態但移除二維碼）
  void clearPaymentResponse() {
    _state = state.copyWith(
      status: PaymentStatus.processing, // 明確保持processing狀態
      clearPaymentResponse: true, // 使用標志明確清除paymentResponse
      isLoading: true,
    );
    notifyListeners();
  }

  /// 14, 獲取大廈名稱
  String _getBuildingName() {
    final building = state.buildings.firstWhere(
      (b) => b.buildingId == state.selectedBuildingId,
      orElse: () => const BuildingInfo(buildingId: '', name: '未知大廈'),
    );
    return building.name;
  }

  /// 15, 獲取單位名稱
  String _getUnitName() {
    final unit = state.units.firstWhere(
      (u) => u.unitId == state.selectedUnitId,
      orElse: () => const UnitInfo(
        unitId: '',
        flatCode: '',
        blockName: '',
        floorName: '',
        unitName: '未知單位',
      ),
    );
    return '${unit.blockName}${unit.floorName}${unit.unitName}';
  }

  /// 17, 計算總金額
  double _calculateTotalAmount() {
    return state.selectedBills.fold<double>(
      0.0,
      (sum, bill) => sum + bill.netAmount,
    );
  }

  /// 18, 更新狀態並通知監聽器
  void _updateState(PaymentState newState) {
    _state = newState;
    notifyListeners();
  }

  /// 29, 設置 API 客戶端
  void setApiClient(ApiClient apiClient) {
    _apiClient = apiClient;
  }

  @override
  void dispose() {
    _stopPaymentStatusPolling();
    super.dispose();
  }
}

Map<String, dynamic>? _nullableMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

/// 支付狀態數據類
class PaymentState {
  final bool isLoading;
  final bool isLoadingBills; // 23, 添加账单加载状态
  final PaymentStatus status;
  final String? errorMessage;
  final List<BuildingInfo> buildings;
  final List<UnitInfo> units;
  final List<PaymentBill> bills;
  final List<PaymentBill> selectedBills;
  final String? selectedBuildingId;
  final String? selectedUnitId;
  final PaymentResponse? paymentResponse;
  final PaymentConfig? paymentConfig;
  final Map<String, dynamic>? receiptData;

  const PaymentState({
    this.isLoading = false,
    this.isLoadingBills = false, // 24, 初始化账单加载状态
    this.status = PaymentStatus.pending,
    this.errorMessage,
    this.buildings = const [],
    this.units = const [],
    this.bills = const [],
    this.selectedBills = const [],
    this.selectedBuildingId,
    this.selectedUnitId,
    this.paymentResponse,
    this.paymentConfig,
    this.receiptData,
  });

  /// 27, copyWith方法 - 用于创建状态副本
  /// 使用clearPaymentResponse标志来明确清除paymentResponse
  PaymentState copyWith({
    bool? isLoading,
    bool? isLoadingBills, // 25, 添加账单加载状态参数
    PaymentStatus? status,
    String? errorMessage,
    List<BuildingInfo>? buildings,
    List<UnitInfo>? units,
    List<PaymentBill>? bills,
    List<PaymentBill>? selectedBills,
    String? selectedBuildingId,
    String? selectedUnitId,
    PaymentResponse? paymentResponse,
    PaymentConfig? paymentConfig,
    Map<String, dynamic>? receiptData,
    bool clearPaymentResponse = false, // 新增：明确清除paymentResponse的标志
  }) {
    return PaymentState(
      isLoading: isLoading ?? this.isLoading,
      isLoadingBills: isLoadingBills ?? this.isLoadingBills, // 26, 更新账单加载状态
      status: status ?? this.status,
      errorMessage: errorMessage,
      buildings: buildings ?? this.buildings,
      units: units ?? this.units,
      bills: bills ?? this.bills,
      selectedBills: selectedBills ?? this.selectedBills,
      selectedBuildingId: selectedBuildingId ?? this.selectedBuildingId,
      selectedUnitId: selectedUnitId ?? this.selectedUnitId,
      // 如果clearPaymentResponse为true，则设置为null；否则使用传入值或保留旧值
      paymentResponse: clearPaymentResponse
          ? null
          : (paymentResponse ?? this.paymentResponse),
      paymentConfig: paymentConfig ?? this.paymentConfig,
      receiptData: receiptData ?? this.receiptData,
    );
  }
}

/// 建築信息模型
class BuildingInfo {
  final String buildingId;
  final String name;

  const BuildingInfo({
    required this.buildingId,
    required this.name,
  });

  factory BuildingInfo.fromMap(Map<String, dynamic> map) {
    return BuildingInfo(
      buildingId: map['building_id']?.toString() ?? '',
      name: map['building_name']?.toString() ?? '',
    );
  }
}
