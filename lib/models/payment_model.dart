/// 1, 支付方式枚舉
enum PaymentMethod {
  wechat,
  alipay,
  unionpay,
  card,
  cash,
  bankTransfer,
  cheque,
}

/// 2, 支付狀態枚舉
enum PaymentStatus {
  idle, // 空閒
  pending, // 待處理
  processing, // 處理中
  success, // 支付成功
  failed, // 支付失敗
  cancelled, // 支付取消
}

/// 3, 賬單模型
class PaymentBill {
  final String flatCode;
  final String itemId;
  final String trsTo;
  final String billDt;
  final double netAmount;
  final String invoiceNo;
  final String? remark;
  final String? unitName;
  final double paidAmount;

  const PaymentBill({
    required this.flatCode,
    required this.itemId,
    required this.trsTo,
    required this.billDt,
    required this.netAmount,
    required this.invoiceNo,
    this.remark,
    this.unitName,
    this.paidAmount = 0.0,
  });

  factory PaymentBill.fromJson(Map<String, dynamic> json) {
    final netAmount = _parseDouble(json['net_amount']);
    return PaymentBill(
      flatCode: json['flat_code']?.toString() ?? '',
      itemId: json['item_id']?.toString() ?? '',
      trsTo: json['trs_to']?.toString() ?? '',
      billDt: json['bill_dt']?.toString() ?? '',
      netAmount: netAmount,
      invoiceNo: json['invoice_no']?.toString() ?? '',
      remark: json['remark']?.toString(),
      unitName: json['unit_name']?.toString(),
      paidAmount: _parseNullableDouble(json['paid_amount']) ?? netAmount,
    );
  }

  ///3.1, 複製並覆蓋字段
  PaymentBill copyWith({
    String? flatCode,
    String? itemId,
    String? trsTo,
    String? billDt,
    double? netAmount,
    String? invoiceNo,
    String? remark,
    String? unitName,
    double? paidAmount,
  }) {
    return PaymentBill(
      flatCode: flatCode ?? this.flatCode,
      itemId: itemId ?? this.itemId,
      trsTo: trsTo ?? this.trsTo,
      billDt: billDt ?? this.billDt,
      netAmount: netAmount ?? this.netAmount,
      invoiceNo: invoiceNo ?? this.invoiceNo,
      remark: remark ?? this.remark,
      unitName: unitName ?? this.unitName,
      paidAmount: paidAmount ?? this.paidAmount,
    );
  }

  ///3.2, 從列表構建賬單清單（可覆蓋unitName）
  static List<PaymentBill> listFrom(
    List<dynamic> jsonList, {
    String? unitName,
  }) {
    return jsonList
        .whereType<Map>()
        .map((e) => PaymentBill.fromJson(_parseMap(e)))
        .map((bill) => (unitName != null && unitName.isNotEmpty)
            ? bill.copyWith(
                unitName: (bill.unitName == null || bill.unitName!.isEmpty)
                    ? unitName
                    : bill.unitName,
              )
            : bill)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'flat_code': flatCode,
      'item_id': itemId,
      'trs_to': trsTo,
      'bill_dt': billDt,
      'net_amount': netAmount,
      'invoice_no': invoiceNo,
      if (remark != null) 'remark': remark,
      if (unitName != null) 'unit_name': unitName,
      'paid_amount': paidAmount,
    };
  }

  /// 3.3, 計算單個賬單的手續費
  /// 公式：手續費 = 賬單金額 × 費率
  /// 例如：賬單10元，費率25%，手續費 = 10 × 0.25 = 2.5元
  /// 進位規則：直接進位（向上取整到分），不四捨五入
  double getFee(double feeRate) {
    if (feeRate <= 0 || netAmount <= 0) {
      return 0.0;
    }
    // 計算手續費：賬單金額 × 費率
    final fee = netAmount * feeRate;
    // 直接進位到分（乘以100，向上取整，再除以100）
    return (fee * 100).ceil() / 100.0;
  }

  /// 3.4, 計算單個賬單的總金額（包含手續費）
  /// 公式：總金額 = 賬單金額 × (1 + 費率)
  /// 進位規則：直接進位（向上取整到分）
  double getTotalWithFee(double feeRate) {
    if (feeRate <= 0 || netAmount <= 0) {
      return netAmount;
    }
    // 計算總金額：賬單金額 × (1 + 費率)
    final totalAmount = netAmount * (1 + feeRate);
    // 直接進位到分
    return (totalAmount * 100).ceil() / 100.0;
  }
}

/// 4, 第三方支付響應模型
class ThirdPartyPaymentResponse {
  final String? qrCode;
  final String? transactionId;
  final String? orderNo;
  final String? payOrderId;
  final int? amount;
  final String? currency;
  final int? state; // 0:訂單生成, 1:支付中, 2:支付成功, 3:支付失敗, 4:已撤銷, 5:已退款, 6:訂單關閉
  final String? errCode;
  final String? errMsg;
  final DateTime? createdAt;
  final DateTime? successTime;

  ThirdPartyPaymentResponse({
    this.qrCode,
    this.transactionId,
    this.orderNo,
    this.payOrderId,
    this.amount,
    this.currency,
    this.state,
    this.errCode,
    this.errMsg,
    this.createdAt,
    this.successTime,
  });

  factory ThirdPartyPaymentResponse.fromJson(Map<String, dynamic> json) {
    // 尝试从多个可能的字段中获取QR码数据
    String? qrCodeData;
    if (json['payData'] != null) {
      qrCodeData = json['payData']?.toString();
    } else if (json['codeUrl'] != null) {
      qrCodeData = json['codeUrl']?.toString();
    } else if (json['qr_code'] != null) {
      qrCodeData = json['qr_code']?.toString();
    }

    return ThirdPartyPaymentResponse(
      qrCode: qrCodeData,
      transactionId: json['channelOrderNo']?.toString(),
      orderNo: json['mchOrderNo']?.toString(),
      payOrderId: json['payOrderId']?.toString(),
      amount: _parseNullableInt(json['amount']),
      currency: json['currency']?.toString(),
      state: _parseNullableInt(json['state']),
      errCode: json['errCode']?.toString(),
      errMsg: json['errMsg']?.toString(),
      createdAt: _parseEpochMilliseconds(json['createdTime']),
      successTime: _parseEpochMilliseconds(json['successTime']),
    );
  }

  /// 是否支付成功 (根据实际API行为：state=2为支付成功)
  /// state=0:訂單生成, state=1:支付中, state=2:支付成功, state=3:支付失敗
  bool get isSuccess => state == 2;

  /// 是否支付失敗
  bool get isFailed =>
      state == 3 || state == 4 || state == 5 || state == 6 || state == -1;

  /// 是否處理中/待支付 (state=0:訂單生成, state=1:支付中)
  bool get isProcessing => state == 0 || state == 1;

  /// 轉換為本地支付響應模型
  PaymentResponse toPaymentResponse() {
    PaymentStatus status;
    if (isSuccess) {
      status = PaymentStatus.success;
    } else if (isFailed) {
      status = PaymentStatus.failed;
    } else if (isProcessing) {
      status = PaymentStatus.processing;
    } else {
      status = PaymentStatus.pending;
    }

    return PaymentResponse(
      paymentId: payOrderId ?? '',
      status: status,
      transactionId: transactionId ?? '',
      qrCode: qrCode,
      createdAt: createdAt,
      completedAt: successTime,
      errorMessage: errMsg,
    );
  }
}

/// 5, 支付響應模型
class PaymentResponse {
  final String paymentId;
  final PaymentStatus status;
  final String transactionId;
  final String? qrCode;
  final String? paymentUrl;
  final String? receiptId;
  final double? handlingFee;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final String? errorMessage;
  final Map<String, dynamic>? rawData;

  const PaymentResponse({
    required this.paymentId,
    required this.status,
    required this.transactionId,
    this.qrCode,
    this.paymentUrl,
    this.receiptId,
    this.handlingFee,
    this.createdAt,
    this.completedAt,
    this.errorMessage,
    this.rawData,
  });

  factory PaymentResponse.fromJson(Map<String, dynamic> json) {
    return PaymentResponse(
      paymentId: json['payment_id']?.toString() ?? '',
      status: _parsePaymentStatus(json['status']),
      transactionId: json['transaction_id']?.toString() ?? '',
      qrCode: json['qr_code']?.toString(),
      paymentUrl: json['payment_url']?.toString(),
      receiptId: json['receipt_id']?.toString(),
      handlingFee: _parseNullableDouble(json['handling_fee']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : null,
      errorMessage: json['error_message']?.toString(),
      rawData: _nullableMap(json['raw_data']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'payment_id': paymentId,
      'status': _paymentStatusToString(status),
      'transaction_id': transactionId,
      if (qrCode != null) 'qr_code': qrCode,
      if (paymentUrl != null) 'payment_url': paymentUrl,
      if (receiptId != null) 'receipt_id': receiptId,
      if (handlingFee != null) 'handling_fee': handlingFee,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (errorMessage != null) 'error_message': errorMessage,
      if (rawData != null) 'raw_data': rawData,
    };
  }

  PaymentResponse copyWith({
    String? paymentId,
    PaymentStatus? status,
    String? transactionId,
    String? qrCode,
    String? paymentUrl,
    String? receiptId,
    double? handlingFee,
    DateTime? createdAt,
    DateTime? completedAt,
    String? errorMessage,
    Map<String, dynamic>? rawData,
  }) {
    return PaymentResponse(
      paymentId: paymentId ?? this.paymentId,
      status: status ?? this.status,
      transactionId: transactionId ?? this.transactionId,
      qrCode: qrCode ?? this.qrCode,
      paymentUrl: paymentUrl ?? this.paymentUrl,
      receiptId: receiptId ?? this.receiptId,
      handlingFee: handlingFee ?? this.handlingFee,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      rawData: rawData ?? this.rawData,
    );
  }

  static PaymentStatus _parsePaymentStatus(dynamic status) {
    if (status == null) return PaymentStatus.pending;

    switch (status.toString().toLowerCase()) {
      case 'idle':
        return PaymentStatus.idle;
      case 'pending':
        return PaymentStatus.pending;
      case 'processing':
        return PaymentStatus.processing;
      case 'success':
        return PaymentStatus.success;
      case 'failed':
        return PaymentStatus.failed;
      case 'cancelled':
        return PaymentStatus.cancelled;
      default:
        return PaymentStatus.pending;
    }
  }

  static String _paymentStatusToString(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.idle:
        return 'idle';
      case PaymentStatus.pending:
        return 'pending';
      case PaymentStatus.processing:
        return 'processing';
      case PaymentStatus.success:
        return 'success';
      case PaymentStatus.failed:
        return 'failed';
      case PaymentStatus.cancelled:
        return 'cancelled';
    }
  }
}

/// 5, 單位信息模型
class UnitInfo {
  final String unitId;
  final String flatCode;
  final String blockName;
  final String floorName;
  final String unitName;
  final String? buildingId;
  final String? displayName;

  const UnitInfo({
    required this.unitId,
    required this.flatCode,
    required this.blockName,
    required this.floorName,
    required this.unitName,
    this.buildingId,
    this.displayName,
  });

  factory UnitInfo.fromJson(Map<String, dynamic> json) {
    final unitInfo = UnitInfo(
      unitId: json['unit_id']?.toString() ?? '',
      flatCode: json['simpleadd']?.toString() ?? '',
      blockName: json['block']?.toString() ?? '',
      floorName: json['floor']?.toString() ?? '',
      unitName: json['unit']?.toString() ?? '',
      buildingId: json['building_id']?.toString(),
      displayName: json['simpleadd']?.toString(),
    );

    return unitInfo;
  }

  Map<String, dynamic> toJson() {
    return {
      'unit_id': unitId,
      'simpleadd': flatCode,
      'block': blockName,
      'floor': floorName,
      'unit': unitName,
      if (buildingId != null) 'building_id': buildingId,
      if (displayName != null) 'simpleadd': displayName,
    };
  }
}

/// 6, 銀行賬戶信息模型
class BankAccountInfo {
  final String accountName;
  final String accountNumber;
  final String bankName;
  final String? bankCode;
  final String? branchName;
  final String? swiftCode;

  const BankAccountInfo({
    required this.accountName,
    required this.accountNumber,
    required this.bankName,
    this.bankCode,
    this.branchName,
    this.swiftCode,
  });

  factory BankAccountInfo.fromJson(Map<String, dynamic> json) {
    return BankAccountInfo(
      accountName: json['account_name']?.toString() ?? '',
      accountNumber: json['account_number']?.toString() ?? '',
      bankName: json['bank_name']?.toString() ?? '',
      bankCode: json['bank_code']?.toString(),
      branchName: json['branch_name']?.toString(),
      swiftCode: json['swift_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account_name': accountName,
      'account_number': accountNumber,
      'bank_name': bankName,
      if (bankCode != null) 'bank_code': bankCode,
      if (branchName != null) 'branch_name': branchName,
      if (swiftCode != null) 'swift_code': swiftCode,
    };
  }
}

/// 7, 支付配置模型
class PaymentConfig {
  final String buildingId;
  final List<PaymentMethod> enabledMethods;
  final Map<String, double> feeRates;
  final BankAccountInfo? bankAccount;
  final Map<String, dynamic>? settings;

  const PaymentConfig({
    required this.buildingId,
    required this.enabledMethods,
    required this.feeRates,
    this.bankAccount,
    this.settings,
  });

  /// 默認支付配置構造函數
  factory PaymentConfig.defaultConfig(String buildingId) {
    return PaymentConfig(
      buildingId: buildingId,
      enabledMethods: [PaymentMethod.wechat, PaymentMethod.alipay],
      feeRates: {},
    );
  }

  factory PaymentConfig.fromJson(Map<String, dynamic> json) {
    // 處理手續費數據，從 transaction_types 數組中提取
    final feeRates = <String, double>{};
    final enabledMethods = <PaymentMethod>{};
    final bankAccountJson = json['bank_account'];

    if (json['transaction_types'] is List) {
      final List<dynamic> transactionTypes = json['transaction_types'];

      for (final type in transactionTypes) {
        final transactionType = _nullableMap(type);
        if (transactionType != null) {
          final payType = transactionType['pay_type']?.toString();
          final markup = _parseDouble(transactionType['markup']);

          // 映射支付類型到我們的枚舉
          if (payType == 'POS_ALIWE') {
            feeRates['wechat'] = markup;
            feeRates['alipay'] = markup;
            enabledMethods.addAll([PaymentMethod.wechat, PaymentMethod.alipay]);
          } else if (payType == 'POS_UNIONPAY') {
            feeRates['unionpay'] = markup;
            enabledMethods.add(PaymentMethod.unionpay);
          } else if (payType == 'POS_CARD') {
            final payTypeName =
                transactionType['pay_type_name_chi']?.toString() ?? '';
            // 检查是否为云闪付（根据中文名判断）
            if (payTypeName.contains('雲閃付') ||
                payTypeName.contains('银联') ||
                payTypeName.contains('UnionPay') ||
                payTypeName.contains('銀聯卡') ||
                payTypeName.contains('银联卡')) {
              feeRates['unionpay'] = markup;
              enabledMethods.add(PaymentMethod.unionpay);
            } else {
              // 如果没有专门的云闪付配置，但应用需要支持云闪付，则使用信用卡费率
              feeRates['card'] = markup;
              feeRates['unionpay'] = markup; // 云闪付使用信用卡费率
              enabledMethods.add(PaymentMethod.card);
              enabledMethods.add(PaymentMethod.unionpay);
            }
          } else if (payType == 'POS_BANK') {
            feeRates['bank_transfer'] = markup;
            enabledMethods.add(PaymentMethod.bankTransfer);
          } else if (payType == 'POS_CASH') {
            feeRates['cash'] = markup;
            enabledMethods.add(PaymentMethod.cash);
          } else if (payType == 'POS_CHEQUE') {
            feeRates['cheque'] = markup;
            enabledMethods.add(PaymentMethod.cheque);
          }
        }
      }
    }

    return PaymentConfig(
      buildingId: json['building_id']?.toString() ?? '',
      enabledMethods: enabledMethods.isNotEmpty
          ? enabledMethods.toList(growable: false)
          : _parsePaymentMethods(json['enabled_methods']),
      feeRates: feeRates,
      bankAccount: _nullableMap(bankAccountJson) != null
          ? BankAccountInfo.fromJson(_parseMap(bankAccountJson))
          : null,
      settings: _nullableMap(json['settings']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'building_id': buildingId,
      'enabled_methods': enabledMethods.map(_paymentMethodToString).toList(),
      'fee_rates': feeRates,
      if (bankAccount != null) 'bank_account': bankAccount!.toJson(),
      if (settings != null) 'settings': settings,
    };
  }

  static List<PaymentMethod> _parsePaymentMethods(dynamic methods) {
    if (methods == null || methods is! List) return [];

    return methods
        .map((method) {
          switch (method.toString().toLowerCase()) {
            case 'wechat':
              return PaymentMethod.wechat;
            case 'alipay':
              return PaymentMethod.alipay;
            case 'unionpay':
              return PaymentMethod.unionpay;
            case 'card':
              return PaymentMethod.card;
            case 'cash':
              return PaymentMethod.cash;
            case 'bank_transfer':
              return PaymentMethod.bankTransfer;
            case 'cheque':
              return PaymentMethod.cheque;
            default:
              return null;
          }
        })
        .whereType<PaymentMethod>()
        .toList();
  }

  static String _paymentMethodToString(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.wechat:
        return 'wechat';
      case PaymentMethod.alipay:
        return 'alipay';
      case PaymentMethod.unionpay:
        return 'unionpay';
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
      case PaymentMethod.cheque:
        return 'cheque';
    }
  }

  /// 7.1, 計算總手續費
  /// 公式：每筆賬單的手續費 = 賬單金額 ÷ (1 - 費率) - 賬單金額
  /// 進位規則：每筆賬單單獨計算並直接進位到分
  double getTotalFee(List<PaymentBill> bills, PaymentMethod method) {
    if (bills.isEmpty) {
      return 0;
    }

    final feeRate = feeRates[_getMethodKey(method)] ?? 0.0;
    if (feeRate <= 0) {
      return 0;
    }

    // 計算每筆賬單的手續費並累加
    var totalFee = bills.map((bill) {
      return bill.getFee(feeRate);
    }).reduce((value, element) => value + element);

    return totalFee;
  }

  /// 7.1.1, 計算總金額（賬單金額 + 手續費）
  double getTotalAmount(List<PaymentBill> bills, PaymentMethod method) {
    if (bills.isEmpty) {
      return 0;
    }

    final feeRate = feeRates[_getMethodKey(method)] ?? 0.0;
    if (feeRate <= 0) {
      // 沒有手續費，直接返回賬單總額
      return bills.fold<double>(0.0, (sum, bill) => sum + bill.netAmount);
    }

    // 計算每筆賬單的總金額（含手續費）並累加
    return bills.map((bill) {
      return bill.getTotalWithFee(feeRate);
    }).reduce((value, element) => value + element);
  }

  /// 7.2, 獲取支付方式對應的key
  String _getMethodKey(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.wechat:
        return 'wechat';
      case PaymentMethod.alipay:
        return 'alipay';
      case PaymentMethod.unionpay:
        return 'unionpay';
      case PaymentMethod.card:
        return 'card';
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.bankTransfer:
        return 'bank_transfer';
      case PaymentMethod.cheque:
        return 'cheque';
    }
  }

  /// 7.3, 獲取支付方式的手續費率（百分比顯示）
  double getFeeRatePercentage(PaymentMethod method) {
    final feeRate = feeRates[_getMethodKey(method)] ?? 0.0;
    return feeRate * 100; // 轉換為百分比
  }
}

Map<String, dynamic> _parseMap(Object? value) {
  return _nullableMap(value) ?? const {};
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

double _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0.0;
  }
  return 0.0;
}

double? _parseNullableDouble(Object? value) {
  if (value == null || value == '') {
    return null;
  }
  return _parseDouble(value);
}

int? _parseNullableInt(Object? value) {
  if (value == null || value == '') {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

DateTime? _parseEpochMilliseconds(Object? value) {
  final milliseconds = _parseNullableInt(value);
  if (milliseconds == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds);
}
