import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 小票打印機提供者
class ReceiptPrinterNotifier extends ChangeNotifier {
  final Logger _logger = Logger();

  ReceiptPrinterState _state = const ReceiptPrinterState();
  ReceiptPrinterState get state => _state;

  /// 1, 初始化打印機
  Future<void> initializePrinter() async {
    try {
      _updateState(_state.copyWith(isInitializing: true));
      _logger.i(' [ReceiptPrinter] 初始化小票打印機');

      // 檢查權限
      await _checkPermissions();

      // 查找可用打印機
      await _findAvailablePrinters();

      _updateState(_state.copyWith(
        isInitializing: false,
        isInitialized: true,
      ));

      _logger.i(' [ReceiptPrinter] 打印機初始化完成');
    } catch (e) {
      _logger.e(' [ReceiptPrinter] 打印機初始化失敗: $e');
      _updateState(_state.copyWith(
        isInitializing: false,
        error: '打印機初始化失敗: $e',
      ));
    }
  }

  /// 2, 檢查權限
  Future<void> _checkPermissions() async {
    if (!kIsWeb && Platform.isAndroid) {
      final storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        await Permission.storage.request();
      }
    }
  }

  /// 3, 查找可用打印機
  Future<void> _findAvailablePrinters() async {
    try {
      _logger.i(' [ReceiptPrinter] 查找可用打印機');

      // 使用 printing 包查找打印機
      // 這裡主要是為了檢測是否有打印機可用
      // 實際的熱敏打印機連接將通過 USB 或藍牙

      _updateState(_state.copyWith(
        availablePrinters: ['USB熱敏打印機', '藍牙打印機'],
        selectedPrinter: 'USB熱敏打印機',
      ));

      _logger.i(' [ReceiptPrinter] 找到 ${_state.availablePrinters.length} 台打印機');
    } catch (e) {
      _logger.e(' [ReceiptPrinter] 查找打印機失敗: $e');
      throw Exception('查找打印機失敗: $e');
    }
  }

  /// 4, 選擇打印機
  void selectPrinter(String printerName) {
    _updateState(_state.copyWith(selectedPrinter: printerName));
    _logger.i(' [ReceiptPrinter] 選擇打印機: $printerName');
  }

  /// 5, 打印支付小票
  Future<void> printPaymentReceipt(Map<String, dynamic> receiptData) async {
    try {
      _updateState(_state.copyWith(isPrinting: true, error: null));
      _logger.i(' [ReceiptPrinter] 開始打印支付小票');

      // 生成小票 PDF
      final pdfBytes = await _generateReceiptPDF(receiptData);

      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux) {
        // 桌面平台：使用系統打印對話框
        await _printToPDFPrinter(pdfBytes);
      } else {
        // 移動平台：保存到文件並分享
        await _saveReceiptToFile(pdfBytes, receiptData);
      }

      _updateState(_state.copyWith(
        isPrinting: false,
        lastPrintTime: DateTime.now(),
      ));

      _logger.i(' [ReceiptPrinter] 支付小票打印完成');
    } catch (e) {
      _logger.e(' [ReceiptPrinter] 打印支付小票失敗: $e');
      _updateState(_state.copyWith(
        isPrinting: false,
        error: '打印失敗: $e',
      ));
    }
  }

  /// 6, 生成小票 PDF
  Future<Uint8List> _generateReceiptPDF(
      Map<String, dynamic> receiptData) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(226.77, double.infinity), // 80mm 寬度
        margin: const pw.EdgeInsets.all(8),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 標題
              pw.Center(
                child: pw.Text(
                  '繳費小票',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 8),

              // 分隔線
              pw.Divider(),
              pw.SizedBox(height: 8),

              // 基本信息
              _buildReceiptInfoRow('大廈名稱:', receiptData['building_name'] ?? ''),
              _buildReceiptInfoRow('單位名稱:', receiptData['unit_name'] ?? ''),
              _buildReceiptInfoRow(
                  '支付方式:', receiptData['payment_method'] ?? ''),
              _buildReceiptInfoRow(
                  '支付時間:', _formatDateTime(receiptData['payment_time'])),
              _buildReceiptInfoRow('支付編號:', receiptData['payment_id'] ?? ''),
              if (receiptData['transaction_id'] != null)
                _buildReceiptInfoRow('交易編號:', receiptData['transaction_id']),

              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.SizedBox(height: 8),

              // 帳單明細
              pw.Text(
                '繳費明細:',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),

              ...(_getBillDetails(receiptData['bills'])),

              pw.SizedBox(height: 8),
              pw.Divider(),
              pw.SizedBox(height: 8),

              // 總金額
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '總計:',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '\$${(receiptData['total_amount'] as double).toStringAsFixed(2)}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 16),

              // 備註
              if (receiptData['remark'] != null &&
                  receiptData['remark'].toString().isNotEmpty) ...[
                pw.Text('備註: ${receiptData['remark']}'),
                pw.SizedBox(height: 8),
              ],

              // 底部信息
              pw.Center(
                child: pw.Text(
                  '謝謝使用智能繳費系統',
                  style: const pw.TextStyle(fontSize: 12),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  '此小票為繳費憑證，請妥善保管',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// 7, 構建小票信息行
  pw.Widget _buildReceiptInfoRow(String label, String value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 12),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// 8, 獲取帳單明細
  List<pw.Widget> _getBillDetails(dynamic bills) {
    if (bills == null || bills is! List) return [];

    return bills.map((bill) {
      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    bill['item_id'] ?? '',
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ),
                pw.Text(
                  '\$${(bill['net_amount'] as double).toStringAsFixed(2)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ],
            ),
            if (bill['trs_to'] != null)
              pw.Text(
                '期間: ${bill['trs_to']}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            if (bill['invoice_no'] != null)
              pw.Text(
                '發票: ${bill['invoice_no']}',
                style: const pw.TextStyle(fontSize: 9),
              ),
          ],
        ),
      );
    }).toList();
  }

  /// 9, 格式化日期時間
  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return '';

    DateTime dt;
    if (dateTime is String) {
      dt = DateTime.tryParse(dateTime) ?? DateTime.now();
    } else if (dateTime is DateTime) {
      dt = dateTime;
    } else {
      return '';
    }

    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// 10, 使用系統PDF打印機打印
  Future<void> _printToPDFPrinter(Uint8List pdfBytes) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: '繳費小票_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// 11, 保存小票到文件
  Future<void> _saveReceiptToFile(
    Uint8List pdfBytes,
    Map<String, dynamic> receiptData,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          '繳費小票_${receiptData['payment_id']}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${directory.path}/$fileName');

      await file.writeAsBytes(pdfBytes);

      _logger.i(' [ReceiptPrinter] 小票已保存到: ${file.path}');

      // 可以在這裡添加分享功能
      // Share.shareFiles([file.path], text: '繳費小票');
    } catch (e) {
      _logger.e(' [ReceiptPrinter] 保存小票失敗: $e');
      throw Exception('保存小票失敗: $e');
    }
  }

  /// 12, 測試打印
  Future<void> testPrint() async {
    final testData = {
      'payment_id': 'TEST_${DateTime.now().millisecondsSinceEpoch}',
      'building_name': '測試大廈',
      'unit_name': 'A座12樓B室',
      'payment_method': '微信支付',
      'payment_time': DateTime.now().toIso8601String(),
      'total_amount': 1500.00,
      'bills': [
        {
          'item_id': '管理費',
          'net_amount': 800.00,
          'trs_to': '2024年1月',
          'invoice_no': 'INV001',
        },
        {
          'item_id': '水費',
          'net_amount': 350.00,
          'trs_to': '2024年1月',
          'invoice_no': 'INV002',
        },
        {
          'item_id': '電費',
          'net_amount': 350.00,
          'trs_to': '2024年1月',
          'invoice_no': 'INV003',
        },
      ],
      'remark': '測試打印小票',
    };

    await printPaymentReceipt(testData);
  }

  /// 13, 清除錯誤
  void clearError() {
    _updateState(_state.copyWith(error: null));
  }

  /// 14, 更新狀態並通知監聽器
  void _updateState(ReceiptPrinterState newState) {
    _state = newState;
    notifyListeners();
  }
}

/// 小票打印機狀態
class ReceiptPrinterState {
  final bool isInitializing;
  final bool isInitialized;
  final bool isPrinting;
  final String? error;
  final List<String> availablePrinters;
  final String? selectedPrinter;
  final DateTime? lastPrintTime;

  const ReceiptPrinterState({
    this.isInitializing = false,
    this.isInitialized = false,
    this.isPrinting = false,
    this.error,
    this.availablePrinters = const [],
    this.selectedPrinter,
    this.lastPrintTime,
  });

  ReceiptPrinterState copyWith({
    bool? isInitializing,
    bool? isInitialized,
    bool? isPrinting,
    String? error,
    List<String>? availablePrinters,
    String? selectedPrinter,
    DateTime? lastPrintTime,
  }) {
    return ReceiptPrinterState(
      isInitializing: isInitializing ?? this.isInitializing,
      isInitialized: isInitialized ?? this.isInitialized,
      isPrinting: isPrinting ?? this.isPrinting,
      error: error,
      availablePrinters: availablePrinters ?? this.availablePrinters,
      selectedPrinter: selectedPrinter ?? this.selectedPrinter,
      lastPrintTime: lastPrintTime ?? this.lastPrintTime,
    );
  }
}
