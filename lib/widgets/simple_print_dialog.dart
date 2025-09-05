import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iboard_app/utils/wifi_printer_service.dart';
import 'package:iboard_app/providers/printer_provider.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';
import 'package:printing/printing.dart';

/// 簡化版打印對話框
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

  List<PrinterDevice> _printers = [];
  PrinterDevice? _selectedPrinter;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _printerProvider = Provider.of<PrinterProvider>(context, listen: false);
    _initializeDialog();
  }

  /// 1, 初始化對話框
  Future<void> _initializeDialog() async {
    try {
      if (_printerProvider != null) {
        await _printerProvider!.initialize();
        _printers = _printerProvider!.printers;
        _selectedPrinter = _printerProvider!.defaultPrinter;

        if (_printers.isEmpty) {
          await _printerProvider!.refreshPrinterStatus();
          _printers = _printerProvider!.printers;
          _selectedPrinter = _printerProvider!.defaultPrinter;
        }
      }

      setState(() {
        _isLoading = false;
      });

      _logger.i('🖨️ 簡化打印對話框初始化完成，載入 ${_printers.length} 個打印機');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _logger.e('初始化簡化打印對話框失敗: $e');
    }
  }

  /// 2, 開始打印 - 直接調用系統打印服務
  Future<void> _startPrint() async {
    if (_selectedPrinter == null) {
      _showErrorDialog('請選擇打印機');
      return;
    }

    if (widget.localFilePath == null) {
      _showErrorDialog('文件未準備就緒，請稍後再試');
      return;
    }

    try {
      // 關閉當前對話框
      Navigator.of(context).pop();

      // 讀取PDF文件
      final file = File(widget.localFilePath!);
      final pdfBytes = await file.readAsBytes();

      // 直接調用系統打印服務，不顯示任何成功/失敗提示
      await Printing.layoutPdf(
        onLayout: (format) async => pdfBytes,
        name: widget.announcement.title,
      );

      _logger.i('🖨️ 已調用系統打印服務: ${widget.announcement.title}');
    } catch (e) {
      // 即使出錯也不顯示錯誤對話框，只記錄日誌
      _logger.e('調用系統打印服務失敗: $e');
    }
  }

  /// 3, 顯示錯誤對話框（僅在選擇打印機或文件問題時顯示）
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打印提示'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        constraints: const BoxConstraints(maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題欄
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.print, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '打印文件',
                      style: TextStyle(
                        color: Colors.white,
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
                            '選擇打印機:',
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
                            child: DropdownButton<PrinterDevice>(
                              value: _selectedPrinter,
                              hint: const Text('請選擇打印機'),
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: _printers.map((printer) {
                                return DropdownMenuItem<PrinterDevice>(
                                  value: printer,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.print,
                                        color: printer.isConnected
                                            ? Colors.green
                                            : Colors.grey,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          printer.name,
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                                      if (!printer.isConnected)
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
                              onChanged: (value) {
                                setState(() {
                                  _selectedPrinter = value;
                                });
                              },
                            ),
                          ),

                          // 如果沒有打印機的提示
                          if (_printers.isEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: Colors.orange.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      color: Colors.orange.shade600, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '未找到打印機，請先在設置中添加',
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),

            // 按鈕區域
            if (!_isLoading)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
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
                      onPressed: _selectedPrinter == null ? null : _startPrint,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.print, size: 18),
                          SizedBox(width: 8),
                          Text('開始打印'),
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

