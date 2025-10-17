import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/printer_model.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:iboard_app/providers/app_data_provider.dart';

/// 增強版列印對話框 - 支持完整打印參數設置
class SimplePrintDialogEnhanced extends StatefulWidget {
  final AnnouncementModel announcement;
  final String? localFilePath;

  const SimplePrintDialogEnhanced({
    super.key,
    required this.announcement,
    this.localFilePath,
  });

  @override
  SimplePrintDialogEnhancedState createState() =>
      SimplePrintDialogEnhancedState();
}

class SimplePrintDialogEnhancedState extends State<SimplePrintDialogEnhanced> {
  final Logger _logger = Logger();
  PrinterProvider? _printerProvider;

  List<PrinterInfo> _printers = [];
  PrinterInfo? _selectedPrinter;
  bool _isLoading = true;
  final TextEditingController _codeController = TextEditingController();
  bool _hasCodeError = false;

  // 打印參數
  int _copies = 1;
  String _colorMode = 'color';
  bool _duplex = false;
  String _duplexType = 'long-edge';
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _printerProvider = Provider.of<PrinterProvider>(context, listen: false);
    _initializeDialog();
    _getTotalPages();

    // 30秒後自動關閉對話框
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  ///1, 初始化對話框 - 直接從香橙派獲取打印機列表
  Future<void> _initializeDialog() async {
    try {
      if (_printerProvider != null) {
        // 確保香橙派IP已配置
        final orangePiIp = _printerProvider!.orangePiIp;
        if (orangePiIp.isEmpty) {
          _logger.w('⚠️ 香橙派IP未配置，嘗試從設備設置獲取');
          final appDataProvider =
              Provider.of<AppDataProvider>(context, listen: false);
          final settingsIp = appDataProvider.deviceSettings?.orangePiIp ?? '';

          if (settingsIp.isNotEmpty) {
            _logger.i('📱 從設備設置獲取香橙派IP: $settingsIp');
            await _printerProvider!.updateOrangePiIp(settingsIp);
          } else {
            _logger.e('❌ 無法獲取香橙派IP地址');
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }

        // 直接從香橙派獲取打印機列表
        try {
          _logger.i('🔄 正在從香橙派獲取打印機列表...');
          await _printerProvider!
              .refreshPrinters()
              .timeout(const Duration(seconds: 5));

          _printers = _printerProvider!.printers;
          _selectedPrinter = _printers.isNotEmpty ? _printers.first : null;

          _logger.i('✅ 成功獲取 ${_printers.length} 個打印機');
        } on TimeoutException {
          _logger.w('🕒 獲取打印機列表超時 (5s)');
          _printers = [];
          _selectedPrinter = null;
        } catch (e) {
          _logger.e('❌ 獲取打印機列表失敗: $e');
          _printers = [];
          _selectedPrinter = null;
        }
      }

      setState(() {
        _isLoading = false;
      });

      _logger.i('🖨️ 列印對話框初始化完成，載入 ${_printers.length} 個列印機');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _logger.e('初始化列印對話框失敗: $e');
    }
  }

  ///2, 獲取PDF總頁數
  Future<void> _getTotalPages() async {
    if (widget.localFilePath == null) return;

    try {
      final file = File(widget.localFilePath!);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();
      final pdfString = String.fromCharCodes(bytes);

      // 簡單解析PDF頁數
      final matches = RegExp(r'/Type\s*/Page[^s]').allMatches(pdfString);
      setState(() {
        _totalPages = matches.length;
      });

      _logger.i('📄 PDF總頁數: $_totalPages');
    } catch (e) {
      _logger.w('獲取PDF頁數失敗: $e');
      setState(() {
        _totalPages = 0;
      });
    }
  }

  ///3, 開始列印 - 完整流程（使用Base64打印）
  Future<void> _startPrint() async {
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('🚀 [打印流程] 開始執行打印流程');
    debugPrint('═══════════════════════════════════════════════════════');

    if (widget.localFilePath == null) {
      debugPrint('❌ [打印流程] PDF文件路徑為空');
      setState(() {
        _hasCodeError = true;
      });
      return;
    }
    debugPrint('✅ [打印流程] PDF文件路徑: ${widget.localFilePath}');

    if (_selectedPrinter == null) {
      debugPrint('❌ [打印流程] 未選擇打印機');
      setState(() {
        _hasCodeError = true;
      });
      return;
    }
    debugPrint(
        '✅ [打印流程] 選擇的打印機: ${_selectedPrinter!.displayName} (${_selectedPrinter!.ipAddress})');

    try {
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      final expected =
          appDataProvider.deviceSettings?.printPassWord ?? '1090119';
      final input = _codeController.text.trim();

      // 調試信息
      debugPrint('───────────────────────────────────────────────────────');
      debugPrint('🔐 [密碼驗證] 開始驗證列印密碼');
      _logger.i('🔐 列印密碼驗證:');
      debugPrint('   輸入密碼: "$input"');
      _logger.i('   輸入密碼: "$input"');
      debugPrint('   期望密碼: "$expected"');
      _logger.i('   期望密碼: "$expected"');
      debugPrint(
          '   DeviceSettings: ${appDataProvider.deviceSettings != null ? "已載入" : "未載入"}');
      _logger.i(
          '   DeviceSettings: ${appDataProvider.deviceSettings != null ? "已載入" : "未載入"}');

      if (input.isEmpty || input != expected) {
        debugPrint('❌ [密碼驗證] 密碼驗證失敗!');
        debugPrint('═══════════════════════════════════════════════════════');
        _logger.w('❌ 密碼驗證失敗!');
        setState(() {
          _hasCodeError = true;
        });
        return;
      }

      debugPrint('✅ [密碼驗證] 密碼驗證成功!');
      debugPrint('───────────────────────────────────────────────────────');
      _logger.i('✅ 密碼驗證成功!');

      // 保存打印參數
      final selectedPrinter = _selectedPrinter!;
      final copies = _copies;
      final colorMode = _colorMode;
      final duplex = _duplex;
      final duplexType = _duplexType;
      final totalPages = _totalPages;

      debugPrint('📋 [打印參數]');
      debugPrint('   打印機: ${selectedPrinter.displayName}');
      debugPrint('   IP地址: ${selectedPrinter.ipAddress}');
      debugPrint('   份數: $copies');
      debugPrint('   顏色: ${colorMode == "color" ? "彩色" : "黑白"}');
      debugPrint('   雙面: ${duplex ? "是" : "否"}');
      if (duplex) {
        debugPrint('   雙面類型: ${duplexType == "long-edge" ? "長邊翻轉" : "短邊翻轉"}');
      }
      debugPrint('   總頁數: $totalPages');
      debugPrint('───────────────────────────────────────────────────────');

      // 關閉當前對話框
      if (mounted) {
        debugPrint('🔄 [打印流程] 關閉打印設置對話框');
        Navigator.of(context).pop();
      }

      debugPrint('🚀 [打印流程] 啟動後台打印任務...');
      debugPrint('═══════════════════════════════════════════════════════');

      // 在後台執行打印流程
      _executePrintInBackground(
        selectedPrinter,
        copies,
        colorMode,
        duplex,
        duplexType,
        totalPages,
      );
    } catch (e) {
      debugPrint('❌ [打印流程] 打印流程啟動失敗: $e');
      debugPrint('═══════════════════════════════════════════════════════');
      _logger.e('打印流程啟動失敗: $e');
    }
  }

  ///4, 在後台執行完整打印流程
  void _executePrintInBackground(
    PrinterInfo printer,
    int copies,
    String colorMode,
    bool duplex,
    String duplexType,
    int totalPages,
  ) {
    Future.delayed(Duration.zero, () async {
      try {
        debugPrint('');
        debugPrint('╔═══════════════════════════════════════════════════════╗');
        debugPrint('║          開始後台打印流程                            ║');
        debugPrint('╚═══════════════════════════════════════════════════════╝');
        _logger.i('🖨️ 開始後台打印流程...');

        // 步驟1: 測試打印機連接
        debugPrint('');
        debugPrint('┌─ 步驟1: 測試打印機連接 ─────────────────────────────┐');
        debugPrint('│ 打印機IP: ${printer.ipAddress}');
        debugPrint('│ 打印機名稱: ${printer.displayName}');
        _logger.i('🔌 測試打印機連接: ${printer.ipAddress}');

        final isConnected =
            await _printerProvider?.testPrinterConnection(printer.ipAddress);

        if (isConnected != true) {
          debugPrint('│ ❌ 連接失敗！');
          debugPrint(
              '└──────────────────────────────────────────────────────┘');
          debugPrint(
              '╔═══════════════════════════════════════════════════════╗');
          debugPrint('║          打印流程結束 (連接失敗)                     ║');
          debugPrint(
              '╚═══════════════════════════════════════════════════════╝');
          _logger.e('❌ 打印機連接失敗: ${printer.displayName}');
          return;
        }

        debugPrint('│ ✅ 連接成功！');
        debugPrint('└──────────────────────────────────────────────────────┘');
        _logger.i('✅ 打印機連接成功');

        // 步驟2: 讀取PDF文件並轉換為Base64
        debugPrint('');
        debugPrint('┌─ 步驟2: 處理PDF文件 ─────────────────────────────────┐');
        debugPrint('│ PDF路徑: ${widget.localFilePath}');
        _logger.i('📄 讀取PDF文件...');

        final file = File(widget.localFilePath!);
        if (!await file.exists()) {
          debugPrint('│ ❌ 文件不存在！');
          debugPrint(
              '└──────────────────────────────────────────────────────┘');
          debugPrint(
              '╔═══════════════════════════════════════════════════════╗');
          debugPrint('║          打印流程結束 (文件不存在)                   ║');
          debugPrint(
              '╚═══════════════════════════════════════════════════════╝');
          _logger.e('❌ PDF文件不存在');
          return;
        }

        debugPrint('│ ✅ 文件存在');
        debugPrint('│ 🔄 開始轉換為Base64...');
        _logger.i('🔄 轉換PDF為Base64...');

        // 讀取PDF文件的原始字節數據（與PowerShell的ReadAllBytes相同）
        final bytes = await file.readAsBytes();
        debugPrint('│ 📊 原始字節數: ${bytes.length}');

        // 驗證PDF文件頭（應該以 %PDF- 開始）
        if (bytes.length > 4) {
          final header = String.fromCharCodes(bytes.sublist(0, 5));
          debugPrint(
              '│ 📄 文件頭: $header (${header == '%PDF-' ? '✅ 有效PDF' : '❌ 無效PDF'})');
        }

        // 轉換為Base64（與PowerShell的ToBase64String相同）
        final base64Data = base64Encode(bytes);
        final fileSizeKB = (bytes.length / 1024).toStringAsFixed(2);

        debugPrint('│ ✅ 轉換完成');
        debugPrint('│ 📊 文件大小: $fileSizeKB KB');
        debugPrint('│ 📊 Base64長度: ${base64Data.length} 字符');
        debugPrint(
            '│ 📝 Base64前100字符: ${base64Data.length > 100 ? base64Data.substring(0, 100) : base64Data}');
        debugPrint('└──────────────────────────────────────────────────────┘');
        _logger.i('📄 PDF文件大小: $fileSizeKB KB');

        // 步驟3: 構建打印設置（符合API格式2）
        debugPrint('');
        debugPrint('┌─ 步驟3: 構建打印設置 ───────────────────────────────┐');

        // 根據API文檔，可選參數只在有值時才發送
        final printSettings = PrintSettings(
          copies: copies,
          colorMode: colorMode,
          media: 'a4',
          duplex: duplex,
          duplexType: duplex ? duplexType : null,
          quality: 'normal',
          orientation: 'portrait',
          pageRange: null, // 不發送頁碼範圍，讓打印機打印全部
        );

        debugPrint('│ 打印機IP: ${printer.ipAddress}');
        debugPrint('│ 份數: $copies');
        debugPrint('│ 顏色模式: $colorMode');
        debugPrint('│ 紙張: a4');
        debugPrint('│ 雙面: ${duplex ? "是" : "否"}');
        if (duplex) {
          debugPrint('│ 雙面類型: $duplexType');
        }
        debugPrint('│ 品質: normal');
        debugPrint('│ 方向: portrait');
        debugPrint('│ 頁碼範圍: 不指定（打印全部）');
        debugPrint('│');
        debugPrint('│ 📝 API 格式2 請求參數:');
        debugPrint('│    printer_ip: ${printer.ipAddress}');
        debugPrint('│    copies: $copies');
        debugPrint('│    color_mode: $colorMode');
        debugPrint('│    media: a4');
        debugPrint('│    duplex: $duplex');
        if (duplex && duplexType.isNotEmpty) {
          debugPrint('│    duplex_type: $duplexType');
        }
        debugPrint('│    quality: normal');
        debugPrint('└──────────────────────────────────────────────────────┘');

        // 步驟4: 調用Base64打印服務
        debugPrint('');
        debugPrint('┌─ 步驟4: 發送打印任務 ───────────────────────────────┐');
        final filename = widget.localFilePath?.split('/').last ??
            widget.announcement.file.url.split('/').last;

        debugPrint('│ 文件名: $filename');
        debugPrint('│ 標題: ${widget.announcement.title}');
        debugPrint('│ 📤 正在發送到打印機...');
        _logger.i('📤 發送打印任務到打印機...');

        final response = await _printerProvider?.printPdfBase64(
          printerIp: printer.ipAddress,
          base64Data: base64Data,
          filename: filename,
          title: widget.announcement.title,
          settings: printSettings,
        );

        debugPrint('│ 📨 收到響應: ${response != null ? "有響應" : "null"}');
        if (response == null) {
          debugPrint('│ ❌ 響應為 null - 可能原因:');
          debugPrint('│    1. PrintApiClient 未初始化');
          debugPrint('│    2. 網絡請求異常');
          debugPrint('│    3. API調用拋出異常');
          debugPrint(
              '└──────────────────────────────────────────────────────┘');
          debugPrint(
              '╔═══════════════════════════════════════════════════════╗');
          debugPrint('║          打印流程結束 (響應為null)                   ║');
          debugPrint(
              '╚═══════════════════════════════════════════════════════╝');
          _logger.e('❌ 打印任務提交失敗: 響應為null');
          return;
        }

        debugPrint('│ 📝 響應詳情:');
        debugPrint('│    success: ${response.success}');
        debugPrint('│    message: ${response.message}');
        debugPrint('│    jobId: ${response.jobId}');
        debugPrint('│    cupsJobId: ${response.cupsJobId}');

        if (response.success != true) {
          debugPrint('│ ❌ 提交失敗: ${response.message}');
          debugPrint(
              '└──────────────────────────────────────────────────────┘');
          debugPrint(
              '╔═══════════════════════════════════════════════════════╗');
          debugPrint('║          打印流程結束 (提交失敗)                     ║');
          debugPrint(
              '╚═══════════════════════════════════════════════════════╝');
          _logger.e('❌ 打印任務提交失敗: ${response.message}');
          return;
        }

        final cupsJobId = response.cupsJobId!;
        debugPrint('│ ✅ 任務已提交！');
        debugPrint('│ 📝 Job ID: ${response.jobId}');
        debugPrint('│ 📝 CUPS Job ID: $cupsJobId');
        debugPrint('└──────────────────────────────────────────────────────┘');
        _logger
            .i('✅ 打印任務已提交: Job ID ${response.jobId}, CUPS Job ID $cupsJobId');
        _logger.i('   打印機: ${printer.displayName}');
        _logger.i('   份數: $copies');
        _logger.i('   顏色: ${colorMode == "color" ? "彩色" : "黑白"}');
        _logger.i('   雙面: ${duplex ? "是" : "否"}');
        if (totalPages > 0) {
          _logger.i('   頁碼: 1-$totalPages');
        }

        // 步驟5: 後台監控打印作業
        debugPrint('');
        debugPrint('┌─ 步驟5: 監控打印作業 ───────────────────────────────┐');
        debugPrint('│ 👀 開始監控作業狀態...');
        debugPrint('│ ⏱️  等待時間: ${copies < 3 ? "3" : "5"} 分鐘');
        _logger.i('👀 開始監控打印作業狀態...');

        final success = await _printerProvider?.monitorPrintJob(
          printer.ipAddress,
          cupsJobId,
          copies,
        );

        if (success == true) {
          debugPrint('│ ✅ 打印作業完成！');
          debugPrint(
              '└──────────────────────────────────────────────────────┘');
          debugPrint('');
          debugPrint(
              '╔═══════════════════════════════════════════════════════╗');
          debugPrint('║          打印流程成功完成                            ║');
          debugPrint(
              '╚═══════════════════════════════════════════════════════╝');
          debugPrint('');
          _logger.i('✅ 打印作業完成！');
        } else {
          debugPrint('│ ⚠️  打印作業異常');
          debugPrint(
              '└──────────────────────────────────────────────────────┘');
          debugPrint('');
          debugPrint(
              '╔═══════════════════════════════════════════════════════╗');
          debugPrint('║          打印流程結束 (作業異常)                     ║');
          debugPrint(
              '╚═══════════════════════════════════════════════════════╝');
          debugPrint('');
          _logger.w('⚠️ 打印作業異常');
        }
      } catch (e) {
        debugPrint('');
        debugPrint('╔═══════════════════════════════════════════════════════╗');
        debugPrint('║          打印流程異常終止                            ║');
        debugPrint('╚═══════════════════════════════════════════════════════╝');
        debugPrint('❌ 錯誤: $e');
        debugPrint('');
        _logger.e('❌ 後台打印流程失敗: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 禁止通過返回鍵關閉
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Container(
          width: 450,
          constraints: const BoxConstraints(maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 標題欄
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.print, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '列印文件',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 內容區域
              Flexible(
                child: _isLoading
                    ? const SizedBox(
                        height: 150,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 文件信息
                            _buildFileInfo(),
                            const SizedBox(height: 20),

                            // 打印機選擇
                            _buildPrinterSelection(),
                            const SizedBox(height: 16),

                            // 打印參數設置
                            _buildPrintSettings(),
                            const SizedBox(height: 16),

                            // 列印密碼
                            _buildPasswordInput(),
                          ],
                        ),
                      ),
              ),

              // 按鈕區域
              if (!_isLoading) _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  ///10, 構建文件信息
  Widget _buildFileInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.announcement.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _totalPages > 0 ? 'PDF 文件 · $_totalPages 頁' : 'PDF 文件',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ///11, 構建打印機選擇
  Widget _buildPrinterSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '選擇列印機:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<PrinterInfo>(
            value: _printers.any((p) => p.id == _selectedPrinter?.id)
                ? _selectedPrinter
                : null,
            hint: const Text('請選擇列印機'),
            isExpanded: true,
            underline: const SizedBox(),
            items: _printers.map((printer) {
              return DropdownMenuItem<PrinterInfo>(
                value: printer,
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: printer.isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.print,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        printer.displayName,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    if (!printer.isOnline)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '離線',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (PrinterInfo? value) {
              setState(() {
                _selectedPrinter = value;
              });
            },
          ),
        ),
        if (_printers.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '未找到列印機',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  ///12, 構建打印參數設置
  Widget _buildPrintSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '列印設置:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 12),

        // 份數
        Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text('份數:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed:
                        _copies > 1 ? () => setState(() => _copies--) : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Container(
                    width: 50,
                    alignment: Alignment.center,
                    child: Text('$_copies',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed:
                        _copies < 99 ? () => setState(() => _copies++) : null,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 顏色模式
        Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text('顏色:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'color', label: Text('彩色')),
                  ButtonSegment(value: 'monochrome', label: Text('黑白')),
                ],
                selected: {_colorMode},
                onSelectionChanged: (Set<String> selection) {
                  setState(() {
                    _colorMode = selection.first;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 雙面打印
        Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text('雙面:', style: TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: Row(
                children: [
                  Switch(
                    value: _duplex,
                    onChanged: (value) {
                      setState(() {
                        _duplex = value;
                      });
                    },
                  ),
                  Text(_duplex ? '開啟' : '關閉',
                      style: const TextStyle(fontSize: 13)),
                  if (_duplex) ...[
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: _duplexType,
                      items: const [
                        DropdownMenuItem(
                          value: 'long-edge',
                          child: Text('長邊翻轉', style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: 'short-edge',
                          child: Text('短邊翻轉', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _duplexType = value;
                          });
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 頁碼範圍（顯示）
        Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text('頁碼:', style: TextStyle(fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _totalPages > 0 ? '1-$_totalPages (共 $_totalPages 頁)' : '全部',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // 固定 A4
        Row(
          children: [
            const SizedBox(
              width: 80,
              child: Text('紙張:', style: TextStyle(fontSize: 13)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('A4', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ],
    );
  }

  ///13, 構建密碼輸入
  Widget _buildPasswordInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '列印密碼:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _codeController,
          obscureText: true,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            hintText: '請輸入列印碼',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onChanged: (_) {
            if (_hasCodeError) {
              setState(() {
                _hasCodeError = false;
              });
            }
          },
        ),
        SizedBox(
          height: 20,
          child: Visibility(
            visible: _hasCodeError,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '請輸入正確的列印密碼',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  ///14, 構建操作按鈕
  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _startPrint,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.print, size: 18),
                SizedBox(width: 8),
                Text('開始列印'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
