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

  Timer? _autoCloseTimer;
  bool _isPrinting = false;
  String? _printStatus; // 打印狀態消息
  bool _printSuccess = false; // 打印是否成功

  @override
  void initState() {
    super.initState();
    _printerProvider = Provider.of<PrinterProvider>(context, listen: false);
    _initializeDialog();
    _getTotalPages();

    // 30秒後自動關閉對話框（如果未開始打印）
    _autoCloseTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && !_isPrinting && Navigator.of(context).canPop()) {
        FocusScope.of(context).unfocus();
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
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
          _logger.w(' 香橙派IP未配置，嘗試從設備設置獲取');
          final appDataProvider =
              Provider.of<AppDataProvider>(context, listen: false);
          final settingsIp = appDataProvider.deviceSettings?.orangePiIp ?? '';

          if (settingsIp.isNotEmpty) {
            _logger.i(' 從設備設置獲取香橙派IP: $settingsIp');
            await _printerProvider!.updateOrangePiIp(settingsIp);
          } else {
            _logger.e(' 無法獲取香橙派IP地址');
            setState(() {
              _isLoading = false;
            });
            return;
          }
        }

        // 直接從香橙派獲取打印機列表
        try {
          _logger.i(' 正在從香橙派獲取打印機列表...');
          await _printerProvider!
              .refreshPrinters()
              .timeout(const Duration(seconds: 5));

          _printers = _printerProvider!.printers;
          _selectedPrinter = _printers.isNotEmpty ? _printers.first : null;

          _logger.i(' 成功獲取 ${_printers.length} 個打印機');
        } on TimeoutException {
          _logger.w(' 獲取打印機列表超時 (5s)');
          _printers = [];
          _selectedPrinter = null;
        } catch (e) {
          _logger.e(' 獲取打印機列表失敗: $e');
          _printers = [];
          _selectedPrinter = null;
        }
      }

      setState(() {
        _isLoading = false;
      });

      _logger.i(' 列印對話框初始化完成，載入 ${_printers.length} 個列印機');
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

      _logger.i(' PDF總頁數: $_totalPages');
    } catch (e) {
      _logger.w('獲取PDF頁數失敗: $e');
      setState(() {
        _totalPages = 0;
      });
    }
  }

  ///3, 開始列印 - 完整流程（使用Base64打印）
  Future<void> _startPrint() async {
    if (widget.localFilePath == null) {
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
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      final expected =
          appDataProvider.deviceSettings?.printPassWord ?? '1090119';
      final input = _codeController.text.trim();

      if (input.isEmpty || input != expected) {
        _logger.w(' 列印密碼驗證失敗');
        setState(() {
          _hasCodeError = true;
        });
        return;
      }

      _logger.i(' 列印密碼驗證成功');

      // 保存打印參數
      final selectedPrinter = _selectedPrinter!;
      final copies = _copies;
      final colorMode = _colorMode;
      final duplex = _duplex;
      final duplexType = _duplexType;
      final totalPages = _totalPages;

      _logger.i(
          ' [打印流程] 準備打印: printer=${selectedPrinter.displayName}, copies=$copies, color=$colorMode, duplex=$duplex, pages=$totalPages');

      // 標記為正在打印
      setState(() {
        _isPrinting = true;
        _printStatus = null; // 清除之前的狀態
      });

      // 取消30秒自動關閉（將在打印完成後自動關閉）
      _autoCloseTimer?.cancel();

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
      _logger.e('打印流程啟動失敗: $e');
    }
  }

  ///4, 在後台執行完整打印流程（優化版）
  void _executePrintInBackground(
    PrinterInfo printer,
    int copies,
    String colorMode,
    bool duplex,
    String duplexType,
    int totalPages,
  ) {
    Future.delayed(Duration.zero, () async {
      int? jobId;
      try {
        _logger.i(' [打印流程] 開始');

        // 步驟1: 健康檢查香橙派服務
        if (mounted) setState(() => _printStatus = '正在檢查香橙派服務...');
        final healthOk = await _checkOrangePiHealth();
        if (!healthOk) {
          if (mounted) {
            setState(() {
              _printStatus = ' 香橙派服務離線，無法打印';
              _printSuccess = false;
              _isPrinting = false;
            });
          }
          _logger.e(' [打印流程] 香橙派服務離線');
          await _sendPrintCallback(printer, false, '香橙派服務離線', null);
          _scheduleAutoClose(10);
          return;
        }

        // 步驟2: 獲取打印前的作業列表
        if (mounted) setState(() => _printStatus = '正在準備打印任務...');
        final jobsBefore = await _getAllJobs(printer.ipAddress);
        final jobIdsBefore = jobsBefore.keys.toSet();
        _logger.i(' [打印流程] 打印前作業數: ${jobIdsBefore.length}');

        // 步驟3: 讀取並發送PDF
        final file = File(widget.localFilePath!);
        if (!await file.exists()) {
          if (mounted) {
            setState(() {
              _printStatus = ' PDF文件不存在';
              _printSuccess = false;
              _isPrinting = false;
            });
          }
          _logger.e(' [打印流程] PDF文件不存在');
          _scheduleAutoClose(10);
          return;
        }

        final bytes = await file.readAsBytes();
        final base64Data = base64Encode(bytes);
        final filename = widget.localFilePath?.split('/').last ??
            widget.announcement.file.url.split('/').last;

        final printSettings = PrintSettings(
          copies: copies,
          colorMode: colorMode,
          media: 'a4',
          duplex: duplex,
          duplexType: duplex ? duplexType : null,
        );

        if (mounted) setState(() => _printStatus = '正在發送打印任務...');
        _logger.i(' [打印流程] 發送打印任務到 ${printer.displayName}');
        final response = await _printerProvider?.printPdfBase64(
          printerIp: printer.ipAddress,
          base64Data: base64Data,
          filename: filename,
          title: widget.announcement.title,
          settings: printSettings,
        );

        if (response == null || !response.success) {
          final errorMsg = '打印任務提交失敗: ${response?.message ?? "未知錯誤"}';
          if (mounted) {
            setState(() {
              _printStatus = ' $errorMsg';
              _printSuccess = false;
              _isPrinting = false;
            });
          }
          _logger.e(' [打印流程] $errorMsg');
          await _sendPrintCallback(printer, false, response?.message, null);
          _scheduleAutoClose(10);
          return;
        }

        jobId = response.cupsJobId!;
        _logger.i(' [打印流程] 任務已提交 (Job ID: $jobId)');

        // 步驟4: 獲取新增的作業
        await Future.delayed(const Duration(seconds: 1));
        final jobsAfter = await _getAllJobs(printer.ipAddress);
        final newJobId = _findNewJob(jobIdsBefore, jobsAfter);

        if (newJobId == null) {
          _logger.w(' [打印流程] 未找到新作業，使用返回的Job ID: $jobId');
        } else {
          _logger.i(' [打印流程] 找到新作業 ID: $newJobId');
          jobId = newJobId;
        }

        // 步驟5: 智能監控打印作業
        if (mounted) {
          setState(() => _printStatus = '正在打印作業 $jobId，請稍候...');
        }
        _logger.i(' [打印流程] 開始監控作業 $jobId');
        final printSuccess = await _monitorPrintJobSmart(
          printer,
          jobId,
          copies,
          jobsAfter,
        );

        // 步驟6: 獲取打印機狀態信息
        _logger.i(' [打印流程] 獲取打印機狀態信息...');
        final statusInfo = await _getPrinterStatusInfo(printer.ipAddress);
        String? markerLevels;
        String? stateReasons;

        if (statusInfo != null) {
          markerLevels = statusInfo['marker_levels'];
          stateReasons = statusInfo['state_reasons'];
          _logger.i(' [打印流程] 墨盒信息: $markerLevels');
          _logger.i(' [打印流程] 狀態原因: $stateReasons');
        }

        // 步驟7: 發送回調
        if (printSuccess) {
          _logger.i(' [打印流程] 打印任務 $jobId 成功完成');
          if (mounted) {
            setState(() {
              _printStatus = ' 打印任務 $jobId 成功！';
              _printSuccess = true;
              _isPrinting = false;
            });
          }
          await _sendPrintCallback(
            printer,
            true,
            stateReasons,
            markerLevels,
          );
          _scheduleAutoClose(10);
        } else {
          _logger.w(' [打印流程] 打印任務 $jobId 失敗或超時');

          // 步驟7a: 取消所有活動作業,避免半死不活的job
          _logger.i(' [打印流程] 取消所有活動作業...');
          try {
            final cancelSuccess =
                await _printerProvider?.cancelAllJobs(printer.ipAddress);
            if (cancelSuccess == true) {
              _logger.i(' [打印流程] 成功取消所有活動作業');
            }
          } catch (e) {
            _logger.e(' [打印流程] 取消作業失敗: $e');
          }

          final reason = await _getPrinterErrorReason(printer);
          if (mounted) {
            setState(() {
              _printStatus = ' 任務 $jobId: $reason';
              _printSuccess = false;
              _isPrinting = false;
            });
          }
          await _sendPrintCallback(
            printer,
            false,
            stateReasons ?? reason,
            markerLevels,
          );
          _scheduleAutoClose(10);
        }
      } catch (e) {
        _logger.e(' [打印流程] 異常: $e');

        // 異常情況下也取消所有活動作業
        _logger.i(' [打印流程] 異常情況,取消所有活動作業...');
        try {
          final cancelSuccess =
              await _printerProvider?.cancelAllJobs(printer.ipAddress);
          if (cancelSuccess == true) {
            _logger.i(' [打印流程] 成功取消所有活動作業');
          }
        } catch (cancelError) {
          _logger.e(' [打印流程] 取消作業失敗: $cancelError');
        }

        if (mounted) {
          setState(() {
            _printStatus = ' 打印流程異常: $e';
            _printSuccess = false;
            _isPrinting = false;
          });
        }
        await _sendPrintCallback(printer, false, e.toString(), null);
        _scheduleAutoClose(10);
      }
    });
  }

  ///4a, 調度自動關閉
  void _scheduleAutoClose(int seconds) {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(Duration(seconds: seconds), () {
      if (mounted && Navigator.of(context).canPop()) {
        // 先讓輸入框失焦,避免鍵盤/焦點問題導致無法關閉
        FocusScope.of(context).unfocus();
        // 稍微延遲確保失焦完成
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
      }
    });
  }

  ///5, 檢查香橙派健康狀態
  Future<bool> _checkOrangePiHealth() async {
    try {
      return await _printerProvider?.checkServiceHealth() ?? false;
    } catch (e) {
      _logger.e(' [健康檢查] 失敗: $e');
      return false;
    }
  }

  ///6, 智能監控打印作業（優化版）
  Future<bool> _monitorPrintJobSmart(
    PrinterInfo printer,
    int cupsJobId,
    int copies,
    Map<String, dynamic> initialJobs,
  ) async {
    try {
      // 第一次等待: (份數+2)/2 分鐘
      final firstWait = Duration(minutes: (copies + 2) ~/ 2);
      _logger.i(' [監控] 第一次等待 ${firstWait.inMinutes} 分鐘...');
      await Future.delayed(firstWait);

      // 從完整作業列表檢查狀態
      var jobState =
          await _getJobStateFromAllJobs(printer.ipAddress, cupsJobId);
      if (jobState == 'completed') {
        return true;
      }

      if (jobState == 'processing' || jobState == 'pending') {
        // 第二次等待: (份數+2)/3 分鐘
        final secondWait = Duration(minutes: (copies + 2) ~/ 3);
        _logger.i(' [監控] 作業處理中，第二次等待 ${secondWait.inMinutes} 分鐘...');
        await Future.delayed(secondWait);

        jobState = await _getJobStateFromAllJobs(printer.ipAddress, cupsJobId);
        if (jobState == 'completed') {
          return true;
        }
      }

      return false;
    } catch (e) {
      _logger.e(' [監控] 失敗: $e');
      return false;
    }
  }

  ///7, 獲取所有作業
  Future<Map<String, dynamic>> _getAllJobs(String printerIp) async {
    try {
      final allJobs = await _printerProvider?.getPrintJobs(printerIp);
      return (allJobs?['jobs'] as Map<String, dynamic>?) ?? {};
    } catch (e) {
      return {};
    }
  }

  ///7a, 從所有作業中獲取狀態
  Future<String> _getJobStateFromAllJobs(
      String printerIp, int cupsJobId) async {
    try {
      final jobs = await _getAllJobs(printerIp);

      for (final entry in jobs.entries) {
        final job = entry.value as Map<String, dynamic>;
        if (job['cups_job_id'] == cupsJobId || job['job_id'] == cupsJobId) {
          final completed = job['completed'] as bool?;
          if (completed == true) {
            return 'completed';
          }
          final stateCode = job['state_code'] as int?;
          if (stateCode == 9) return 'completed';
          if (stateCode == 5) return 'processing';
          return job['status'] as String? ?? 'unknown';
        }
      }
      return 'unknown';
    } catch (e) {
      return 'unknown';
    }
  }

  ///7b, 找到新增的作業
  int? _findNewJob(Set<String> oldJobIds, Map<String, dynamic> newJobs) {
    for (final entry in newJobs.entries) {
      if (!oldJobIds.contains(entry.key)) {
        final job = entry.value as Map<String, dynamic>;
        return job['cups_job_id'] as int? ?? job['job_id'] as int?;
      }
    }
    return null;
  }

  ///8, 獲取打印機錯誤原因
  Future<String> _getPrinterErrorReason(PrinterInfo printer) async {
    try {
      final options =
          await _printerProvider?.getPrinterOptions(printer.ipAddress);
      if (options == null) return '打印機狀態未知';

      final stateReasons = options.options['printer-state-reasons'] ?? 'none';
      final reasons = stateReasons.split(',').map((e) => e.trim()).toList();

      // 檢查是否有error級別的原因
      for (final reason in reasons) {
        final info = _getReasonInfo(reason);
        if (info['severity'] == 'error') {
          return info['message']!;
        }
      }

      // 沒有error級別，返回通用錯誤
      return '打印機出現錯誤，請聯繫管理人員';
    } catch (e) {
      return '無法獲取打印機狀態';
    }
  }

  ///9, 獲取狀態原因信息（簡化版）
  Map<String, String> _getReasonInfo(String reason) {
    const reasons = {
      'media-empty': {'severity': 'error', 'message': ' 紙張已用完'},
      'media-jam': {'severity': 'error', 'message': ' 打印機卡紙'},
      'marker-supply-empty': {'severity': 'error', 'message': ' 墨盒/碳粉已用完'},
      'toner-empty': {'severity': 'error', 'message': ' 碳粉已用完'},
      'door-open': {'severity': 'error', 'message': ' 打印機門未關閉'},
      'cover-open': {'severity': 'error', 'message': ' 打印機蓋子打開'},
      'offline': {'severity': 'error', 'message': ' 打印機離線'},
    };

    return reasons[reason] ?? {'severity': 'info', 'message': ' 未知狀態: $reason'};
  }

  ///10, 獲取打印機狀態信息(墨盒+狀態原因)
  Future<Map<String, String?>?> _getPrinterStatusInfo(String printerIp) async {
    try {
      final options = await _printerProvider?.getPrinterOptions(printerIp);
      if (options == null) return null;

      return {
        'marker_levels': options.options['marker-levels'],
        'state_reasons': options.options['printer-state-reasons'],
      };
    } catch (e) {
      _logger.w(' [狀態信息] 獲取失敗: $e');
      return null;
    }
  }

  ///10a, 發送打印回調（帶墨盒信息）
  Future<void> _sendPrintCallback(
    PrinterInfo printer,
    bool success,
    String? reason,
    String? markerLevels,
  ) async {
    try {
      _logger.i('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      _logger.i(' [打印回調] 準備上報打印結果');
      _logger.i('   打印機: ${printer.displayName} (${printer.ipAddress})');
      _logger.i('   結果: ${success ? " 成功" : " 失敗"}');
      if (reason != null && reason.isNotEmpty) {
        _logger.i('   原因: $reason');
      }
      if (markerLevels != null && markerLevels.isNotEmpty) {
        _logger.i('   墨盒信息: $markerLevels');
      }

      await _printerProvider?.printCallbackWithMarkerLevels(
        printer.ipAddress,
        success,
        reason,
        markerLevels,
      );

      _logger.i(' [打印回調] 上報成功');
      _logger.i('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    } catch (e) {
      _logger.e(' [打印回調] 失敗: $e');
      _logger.i('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => true, // 允許返回鍵關閉
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

                            // 打印狀態顯示
                            if (_printStatus != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _printSuccess
                                      ? Colors.green.shade50
                                      : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _printSuccess
                                        ? Colors.green.shade200
                                        : Colors.orange.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _printSuccess
                                          ? Icons.check_circle
                                          : Icons.info_outline,
                                      color: _printSuccess
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _printStatus!,
                                        style: TextStyle(
                                          color: _printSuccess
                                              ? Colors.green.shade700
                                              : Colors.orange.shade700,
                                          fontSize: 13,
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
                        color: Colors.blue,
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
          keyboardType: TextInputType.number,
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
            onPressed: _isPrinting ? null : _startPrint,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isPrinting
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('打印中...'),
                    ],
                  )
                : const Row(
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
