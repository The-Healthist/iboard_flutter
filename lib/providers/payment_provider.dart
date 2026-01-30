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
  Timer? _pollingTimer;
  Timer? _paymentStatusTimer;

  PaymentState _state = const PaymentState();
  PaymentState get state => _state;

  PaymentNotifier() {
    _paymentClient = PaymentClient();
  }

  /// 19, 載入緩存數據
  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 載入緩存的大廈列表
      final cachedBuildings = prefs.getString('cached_buildings');
      if (cachedBuildings != null) {
        final buildingsData = json.decode(cachedBuildings) as List;
        _updateState(state.copyWith(
          buildings: buildingsData.map((b) => BuildingInfo.fromMap(b)).toList(),
        ));
      }

      // 載入最後選擇的大廈和單位
      final lastBuildingId = prefs.getString('last_selected_building');
      final lastUnitId = prefs.getString('last_selected_unit');

      if (lastBuildingId != null) {
        _updateState(state.copyWith(selectedBuildingId: lastBuildingId));
      }

      if (lastUnitId != null) {
        _updateState(state.copyWith(selectedUnitId: lastUnitId));
      }

      // _logger.i('✅ [PaymentProvider] 緩存數據載入完成');
    } catch (e) {}
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
      // _logger.i('✅ [PaymentProvider] 支付記錄已保存');
    } catch (e) {}
  }

  /// 22, 獲取支付歷史記錄
  Future<List<Map<String, dynamic>>> getPaymentHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paymentRecords = prefs.getStringList('payment_records') ?? [];

      return paymentRecords.map((record) {
        return json.decode(record) as Map<String, dynamic>;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// 1, 初始化支付流程
  Future<void> initializePayment({String? buildingId}) async {
    // debugPrint('[PaymentProvider] 🎬 開始初始化支付流程，buildingId: $buildingId');

    _updateState(state.copyWith(
      status: PaymentStatus.pending,
      errorMessage: null,
    ));
    // _logger.i('🎬 [PaymentProvider] 初始化支付流程');

    // 如果提供了 buildingId，直接加载该大厦的单位
    if (buildingId != null && buildingId.isNotEmpty) {
      await selectBuilding(buildingId);
    }
  }

  /// 2, 載入大廈列表
  Future<void> loadBuildingList() async {
    try {
      _updateState(state.copyWith(isLoading: true));
      // _logger.i('📋 [PaymentProvider] 載入大廈列表');

      final buildings = await _paymentClient.getBuildingList();

      _updateState(state.copyWith(
        isLoading: false,
        buildings: buildings.map((b) => BuildingInfo.fromMap(b)).toList(),
      ));

      // _logger.i('✅ [PaymentProvider] 大廈列表載入完成，共 ${buildings.length} 個大廈');
    } catch (e) {
      _logger.e('❌ [PaymentProvider] 載入大廈列表失敗: $e');
      _updateState(state.copyWith(
        isLoading: false,
        errorMessage: '載入大廈列表失敗: $e',
      ));
    }
  }

  /// 3, 選擇大廈並載入單位
  Future<void> selectBuilding(String buildingId) async {
    try {
      // debugPrint('[PaymentProvider] 🏢 開始選擇大廈: $buildingId');

      _updateState(state.copyWith(
        selectedBuildingId: buildingId,
        isLoading: true,
        selectedUnitId: null,
        bills: [],
      ));

      // 載入大廈單位列表
      // debugPrint('[PaymentProvider] 📡 調用API獲取大廈單位列表...');
      final units =
          await _paymentClient.getBuildingFlatUnits(blgId: buildingId);

      final unitInfos = units.map((u) => UnitInfo.fromJson(u)).toList();
      // debugPrint('[PaymentProvider] 🔄 轉換後的單位信息: ${unitInfos.length} 個單位');

      // 檢查樓層和樓座數據（用於調試）
      // final floors = unitInfos
      //     .map((u) => u.floorName)
      //     .where((f) => f.isNotEmpty)
      //     .toSet()
      //     .toList();
      // final blocks = unitInfos
      //     .map((u) => u.blockName)
      //     .where((b) => b.isNotEmpty)
      //     .toSet()
      //     .toList();

      // 先更新單位數據，使用默認支付配置
      _updateState(state.copyWith(
        isLoading: false,
        units: unitInfos,
        paymentConfig: PaymentConfig.defaultConfig(buildingId),
      ));

      // getBuildingTransactionTypes
      try {
        // debugPrint('[PaymentProvider] ⚙️ 載入支付配置...');
        final config =
            await _paymentClient.getBuildingTransactionTypes(blgId: buildingId);
        // debugPrint('[PaymentProvider] ⚙️ 支付配置數據: $config');

        final paymentConfig = PaymentConfig.fromJson(config);
        // debugPrint('[PaymentProvider] ⚙️ 解析後的費率配置: ${paymentConfig.feeRates}');

        // 直接使用 API 返回的配置
        _updateState(state.copyWith(paymentConfig: paymentConfig));

        //  debugPrint(
        //  '[PaymentProvider] ⚙️ 狀態更新完成，當前費率: ${state.paymentConfig?.feeRates}');
      } catch (e) {
        // 如果 API 調用失敗，創建一個空的配置，這樣會顯示支付功能不可用頁面
        final emptyConfig = PaymentConfig(
          buildingId: buildingId,
          enabledMethods: [],
          feeRates: {},
        );
        _updateState(state.copyWith(paymentConfig: emptyConfig));
      }

      //_logger.i('✅ [PaymentProvider] 大廈選擇完成，載入 ${units.length} 個單位');
      //_logger.i(
      //    '📋 [PaymentProvider] 單位數據示例: ${unitInfos.take(3).map((u) => '${u.floorName}樓${u.unitName}室').join(', ')}');

      //debugPrint(
      //   '[PaymentProvider] ✅ 大廈選擇完成，狀態更新: units=${unitInfos.length}, isLoading=false');
    } catch (e) {
      _logger.e('❌ [PaymentProvider] 選擇大廈失敗: $e');
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
      return '${floorName}樓${unitName}室';
    } else {
      // 顯示樓座+樓層+單元，例如：01座01樓A室
      return '${blockName}座${floorName}樓${unitName}室';
    }
  }

  /// 11, 選擇單位並載入待繳費帳單
  Future<void> selectUnit(String unitId) async {
    try {
      _updateState(state.copyWith(
        selectedUnitId: unitId,
        isLoading: true,
        bills: [],
        selectedBills: [], //清空選中的繳費table
      ));

      // 載入待繳費帳單
      final bills =
          await _paymentClient.getBuildingFlatUnitBills(unitId: unitId);

      _updateState(state.copyWith(
        isLoading: false,
        bills: bills.map((b) => PaymentBill.fromJson(b)).toList(),
      ));
    } catch (e) {
      _logger.e('❌ [PaymentProvider] 選擇單位失敗: $e');
      _updateState(state.copyWith(
        isLoading: false,
        errorMessage: '選擇單位失敗: $e',
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

  /// 15, 全選帳單
  void selectAllBills() {
    _updateState(
        state.copyWith(selectedBills: List<PaymentBill>.from(state.bills)));
  }

  /// 16, 計算購物車總金額
  double get cartTotalAmount {
    return state.selectedBills.fold<double>(
      0.0,
      (sum, bill) => sum + bill.netAmount,
    );
  }

  /// 17, 獲取購物車項目數量
  int get cartItemCount => state.selectedBills.length;

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
    debugPrint('🚀 [PaymentProvider] _createOnlinePayment 開始');
    debugPrint('📊 [PaymentProvider] 支付方式: $paymentMethod');
    debugPrint('📄 [PaymentProvider] 選擇的帳單數量: ${selectedBills.length}');
    
    if (state.selectedBuildingId == null || state.selectedUnitId == null) {
      debugPrint('❌ [PaymentProvider] 缺少必要信息：buildingId=${state.selectedBuildingId}, unitId=${state.selectedUnitId}');
      _updateState(state.copyWith(errorMessage: '請先選擇大廈和單位'));
      return;
    }

    if (_apiClient == null) {
      debugPrint('❌ [PaymentProvider] ApiClient 未初始化');
      _logger.e('❌ [PaymentNotifier] ApiClient 未初始化');
      return;
    }

    try {
      debugPrint('🚀 [PaymentProvider] 開始支付流程，支付方式: $paymentMethod');
      
      // 清除之前的轮询
      _paymentStatusTimer?.cancel();
      _paymentStatusTimer = null;
      debugPrint('🔄 [PaymentProvider] 已清除之前的支付状态轮询');
      
      debugPrint('⏳ [PaymentProvider] 設置支付狀態為處理中...');
      _updateState(state.copyWith(
        status: PaymentStatus.processing,
        isLoading: true,
        errorMessage: null,
        paymentResponse: null, // 清除之前的支付響應
      ));

      // 生成新的訂單號
      final orderNo = _generateOrderNo();
      debugPrint('🎫 [PaymentProvider] 生成訂單號: $orderNo');
      
      // 計算總金額（包含手續費）
      final billAmount = selectedBills.fold<double>(
          0.0, (sum, bill) => sum + bill.netAmount);
      final handlingFee = state.paymentConfig?.getTotalFee(
          selectedBills, paymentMethod) ?? 0.0;
      final totalAmount = billAmount + handlingFee;

      // 構建訂單描述
      final subject = '物業管理費繳納';
      final body = '${selectedBills.length}筆賬單，總金額：HK\$${totalAmount.toStringAsFixed(2)}';

      debugPrint('💰 [PaymentProvider] 帳單金額: $billAmount');
      debugPrint('💸 [PaymentProvider] 手續費: $handlingFee');
      debugPrint('💵 [PaymentProvider] 總金額: $totalAmount');

      _logger.i('🔥 [PaymentNotifier] 開始創建${_getPaymentMethodName(paymentMethod)}支付訂單');
      _logger.i('📋 [PaymentNotifier] 訂單號: $orderNo');
      _logger.i('💰 [PaymentNotifier] 總金額: $totalAmount');

      Map<String, dynamic> responseData;

      debugPrint('🌐 [PaymentProvider] 調用支付API，方式: $paymentMethod');
      
      if (paymentMethod == PaymentMethod.wechat) {
        debugPrint('🔥 [PaymentProvider] 創建微信支付...');
        responseData = await _apiClient!.createWechatPayment(
          orderNo: orderNo,
          amount: totalAmount,
          subject: subject,
          body: body,
        );
      } else if (paymentMethod == PaymentMethod.alipay) {
        debugPrint('🔥 [PaymentProvider] 創建支付寶支付...');
        responseData = await _apiClient!.createAlipayPayment(
          orderNo: orderNo,
          amount: totalAmount,
          subject: subject,
          body: body,
        );
      } else if (paymentMethod == PaymentMethod.unionpay) {
        debugPrint('🔥 [PaymentProvider] 創建雲閃付支付...');
        responseData = await _apiClient!.createUnionpayPayment(
          orderNo: orderNo,
          amount: totalAmount,
          subject: subject,
          body: body,
        );
      } else {
        throw Exception('不支持的支付方式: $paymentMethod');
      }

      debugPrint('📦 [PaymentProvider] API返回數據: $responseData');
      
      final thirdPartyResponse = ThirdPartyPaymentResponse.fromJson(responseData);
      debugPrint('📋 [PaymentProvider] 解析後的響應: state=${thirdPartyResponse.state}, QR碼長度=${thirdPartyResponse.qrCode?.length ?? 0}');
      
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
      debugPrint('💳 [PaymentProvider] 轉換後的支付響應: status=processing, QR碼長度=${paymentResponse.qrCode?.length ?? 0}');

      _updateState(state.copyWith(
        isLoading: false,
        status: PaymentStatus.processing,
        paymentResponse: paymentResponse,
        selectedBills: selectedBills,
      ));

      debugPrint('✅ [PaymentProvider] 支付狀態已更新，開始輪詢...');

      // 開始輪詢支付狀態
      _startNewPaymentStatusPolling(orderNo, paymentMethod);
      
      _logger.i('✅ [PaymentNotifier] ${_getPaymentMethodName(paymentMethod)}支付訂單創建成功');
    } catch (e) {
      debugPrint('💥 [PaymentProvider] 支付創建失敗: $e');
      debugPrint('📊 [PaymentProvider] 錯誤類型: ${e.runtimeType}');
      _logger.e('❌ [PaymentProvider] 創建支付失敗: $e');
      _updateState(state.copyWith(
        status: PaymentStatus.failed,
        isLoading: false,
        errorMessage: '創建支付失敗: $e',
      ));
    }
  }

  /// 30, 獲取支付方式名稱
  String _getPaymentMethodName(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.wechat:
        return '微信';
      case PaymentMethod.alipay:
        return '支付寶';
      case PaymentMethod.unionpay:
        return '雲閃付';
      default:
        return '未知';
    }
  }

  /// 31, 生成訂單號
  String _generateOrderNo() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999).toString().padLeft(6, '0');
    final orderNo = 'PAY$timestamp$random';
    debugPrint('🎯 [PaymentProvider] 生成新訂單號: $orderNo');
    return orderNo;
  }

  /// 32, 新的輪詢支付狀態方法
  void _startNewPaymentStatusPolling(String orderNo, PaymentMethod method) {
    String appId;
    String appSecret;

    switch (method) {
      case PaymentMethod.wechat:
      case PaymentMethod.alipay:
        appId = PaymentApiConfig.qrCodeAppId;
        appSecret = PaymentApiConfig.qrCodeAppSecret;
        break;
      case PaymentMethod.unionpay:
        appId = PaymentApiConfig.unionPayQrAppId;
        appSecret = PaymentApiConfig.unionPayQrAppSecret;
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
          );

          final thirdPartyResponse = ThirdPartyPaymentResponse.fromJson(responseData);
          
          // 33, 記錄支付狀態信息便於調試
          debugPrint('💳 [支付輪詢] 訂單號: $orderNo, state: ${thirdPartyResponse.state}');
          debugPrint('💳 [支付輪詢] isSuccess: ${thirdPartyResponse.isSuccess}, isFailed: ${thirdPartyResponse.isFailed}, isProcessing: ${thirdPartyResponse.isProcessing}');
          
          // 34, 只有在確實支付成功時才更新為成功狀態（state=2表示支付成功）
          // 根據第三方支付接口：state=0:訂單生成, state=1:支付中, state=2:支付成功, state=3:支付失敗
          if (thirdPartyResponse.state == 2) {
            timer.cancel();
            final paymentResponse = thirdPartyResponse.toPaymentResponse();
            _updateState(state.copyWith(
              status: PaymentStatus.success,
              paymentResponse: paymentResponse,
            ));
            _logger.i('✅ [PaymentNotifier] 支付成功，state=2');
            
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
            _logger.e('❌ [PaymentNotifier] 支付失敗: ${thirdPartyResponse.errMsg}');
          } else {
            // 35, 仍在處理中或待支付狀態，繼續輪詢
            debugPrint('⏳ [支付輪詢] 訂單處理中，繼續輪詢...');
          }
          
        } catch (e) {
          _logger.e('❌ [PaymentNotifier] 查詢支付狀態失敗: $e');
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

  /// 8, 開始輪詢支付狀態（保持舊接口兼容性）
  void _startPaymentStatusPolling(String paymentId) {
    _stopPaymentStatusPolling();

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      await _checkPaymentStatus(paymentId);
    });
  }

  /// 9, 停止輪詢支付狀態
  void _stopPaymentStatusPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _paymentStatusTimer?.cancel();
    _paymentStatusTimer = null;
  }

  /// 10, 檢查支付狀態
  Future<void> _checkPaymentStatus(String paymentId) async {
    try {
      final response =
          await _paymentClient.queryPaymentStatus(paymentId: paymentId);
      final status = PaymentStatus.values.firstWhere(
        (s) => s.name == response['status'],
        orElse: () => PaymentStatus.pending,
      );

      final updatedResponse = state.paymentResponse?.copyWith(
        status: status,
        completedAt: status == PaymentStatus.success ? DateTime.now() : null,
      );

      _updateState(state.copyWith(
        status: status,
        paymentResponse: updatedResponse,
      ));

      if (status == PaymentStatus.success || status == PaymentStatus.failed) {
        _stopPaymentStatusPolling();

        if (status == PaymentStatus.success) {
          await _handlePaymentSuccess();
          // 保存支付記錄
          if (updatedResponse != null) {
            await _savePaymentRecord(updatedResponse);
          }
        }
      }
    } catch (e) {
      _logger.e('❌ [PaymentProvider] 檢查支付狀態失敗: $e');
    }
  }

  /// 11, 處理支付成功
  Future<void> _handlePaymentSuccess() async {
    // 創建小票數據
    if (state.paymentResponse != null && state.selectedBills.isNotEmpty) {
      final receiptData = _paymentClient.createReceiptData(
        paymentId: state.paymentResponse!.paymentId,
        buildingName: _getBuildingName(),
        unitName: _getUnitName(),
        paymentMethod: _getPaymentMethodDisplayName(),
        totalAmount: _calculateTotalAmount(),
        bills: state.selectedBills.map((b) => b.toJson()).toList(),
        paymentTime: DateTime.now(),
        transactionId: state.paymentResponse!.transactionId,
      );

      _updateState(state.copyWith(receiptData: receiptData));
    }
  }

  /// 12, 取消支付
  void cancelPayment() {
    _stopPaymentStatusPolling();
    // 37, 取消支付時直接重置為初始狀態，而不是設置為cancelled狀態
    // 這樣可以避免頁面上殘留取消狀態的信息
    _state = const PaymentState();
    notifyListeners();
  }

  /// 13, 重置支付狀態
  void resetPayment() {
    _stopPaymentStatusPolling();
    _state = const PaymentState();
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

  /// 16, 獲取支付方式顯示名稱
  String _getPaymentMethodDisplayName() {
    if (state.paymentResponse == null) return '';

    switch (state.paymentResponse!.status) {
      case PaymentStatus.success:
        return state.selectedBills.isNotEmpty ? '微信支付' : '支付寶';
      default:
        return '';
    }
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

/// 支付狀態數據類
class PaymentState {
  final bool isLoading;
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

  PaymentState copyWith({
    bool? isLoading,
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
  }) {
    return PaymentState(
      isLoading: isLoading ?? this.isLoading,
      status: status ?? this.status,
      errorMessage: errorMessage,
      buildings: buildings ?? this.buildings,
      units: units ?? this.units,
      bills: bills ?? this.bills,
      selectedBills: selectedBills ?? this.selectedBills,
      selectedBuildingId: selectedBuildingId ?? this.selectedBuildingId,
      selectedUnitId: selectedUnitId ?? this.selectedUnitId,
      paymentResponse: paymentResponse ?? this.paymentResponse,
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
