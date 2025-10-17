import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/printer_model.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:iboard_app/providers/app_data_provider.dart';

/// 簡化版列印對話框
class SimplePrintDialog extends StatefulWidget {
  final AnnouncementModel announcement;
  final String? localFilePath;

  const SimplePrintDialog({
    super.key,
    required this.announcement,
    this.localFilePath,
  });

  @override
  SimplePrintDialogState createState() => SimplePrintDialogState();
}

class SimplePrintDialogState extends State<SimplePrintDialog> {
  final Logger _logger = Logger();
  PrinterProvider? _printerProvider;

  List<PrinterInfo> _printers = [];
  PrinterInfo? _selectedPrinter;
  bool _isLoading = true;
  final TextEditingController _codeController = TextEditingController();
  bool _hasCodeError = false;

  @override
  void initState() {
    super.initState();
    _printerProvider = Provider.of<PrinterProvider>(context, listen: false);
    _initializeDialog();

    // 20秒後自動關閉對話框
    Future.delayed(const Duration(seconds: 20), () {
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

  /// 1, 初始化對話框
  Future<void> _initializeDialog() async {
    try {
      if (_printerProvider != null) {
        // 刷新打印機列表 (3s 超時)
        try {
          await _printerProvider!
              .refreshPrinters()
              .timeout(const Duration(seconds: 3));
        } on TimeoutException {
          _logger.w('🕒 列印對話框: 刷新列印機狀態超時 (3s)');
        }
        _printers = _printerProvider!.printers;
        _selectedPrinter = _printers.isNotEmpty ? _printers.first : null;
      }

      setState(() {
        _isLoading = false;
        // 掃描完成後，若當前選中不在列表中，糾正為第一個或空
        if (_selectedPrinter != null &&
            !_printers.any((p) => p.id == _selectedPrinter!.id)) {
          _selectedPrinter = _printers.isNotEmpty ? _printers.first : null;
        }
      });

      _logger.i('🖨️ 簡化列印對話框初始化完成，載入 ${_printers.length} 個列印機');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _logger.e('初始化簡化列印對話框失敗: $e');
    }
  }

  /// 2, 開始列印 - 校驗列印碼後調用打印服務
  Future<void> _startPrint() async {
    if (widget.localFilePath == null) {
      // 內聯錯誤顯示：維持當前對話框
      setState(() {
        _hasCodeError = true;
      });
      return;
    }

    if (_selectedPrinter == null) {
      setState(() {
        _hasCodeError = true;
      });
      return;
    }

    try {
      final expected = Provider.of<AppDataProvider>(context, listen: false)
              .deviceSettings
              ?.printPassWord ??
          '1090119';
      final input = _codeController.text.trim();
      if (input.isEmpty || input != expected) {
        setState(() {
          _hasCodeError = true;
        });
        return;
      }

      // 關閉當前對話框
      Navigator.of(context).pop();

      // 讀取PDF文件
      final file = File(widget.localFilePath!);

      // 打印設置
      const printSettings = PrintSettings(
        copies: 1,
        colorMode: 'color',
        media: 'a4',
        duplex: false,
        quality: 'normal',
      );

      // 調用打印服務
      final response = await _printerProvider?.printPdf(
        printerIp: _selectedPrinter!.ipAddress,
        pdfFile: file,
        title: widget.announcement.title,
        settings: printSettings,
      );

      if (response?.success == true) {
        _logger.i('🖨️ 已發送打印任務: ${widget.announcement.title}');
      } else {
        _logger.w('⚠️ 打印任務失敗: ${response?.message}');
      }
    } catch (e) {
      // 即使出錯也不顯示錯誤對話框，只記錄日誌
      _logger.e('調用打印服務失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 460),
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
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 文件信息
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.picture_as_pdf,
                                      color: Colors.red, size: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                          'PDF 文件',
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
                            ),

                            const SizedBox(height: 20),

                            // 打印機選擇
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButton<PrinterInfo>(
                                value: _printers.any(
                                        (p) => p.id == _selectedPrinter?.id)
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
                                            color: printer.isOnline
                                                ? Colors.green
                                                : Colors.grey,
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
                                            style:
                                                const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                        if (!printer.isOnline)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
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

                            // 僅在未找到列印機時顯示提示
                            if (_printers.isEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  // color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  // border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: Colors.blue.shade600, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '未找到列印機，將使用系統列印服務',
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 16),

                            // 列印碼輸入（移至打印機列表下方）
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
                                // 使用下方自定義錯誤行，不使用內建 errorText
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
                        ),
                      ),
                    ),
            ),

            // 按鈕區域
            if (!_isLoading)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
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
              ),
          ],
        ),
      ),
    );
  }
}
