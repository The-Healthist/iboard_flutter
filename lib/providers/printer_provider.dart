import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/http/api_print.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/printer_model.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局打印機提供者 - 基於香橙派打印服務API
class PrinterProvider extends ChangeNotifier {
  static final PrinterProvider _instance = PrinterProvider._internal();
  factory PrinterProvider() => _instance;
  PrinterProvider._internal();

  final Logger _logger = Logger();
  PrintApiClient? _printApiClient;
  ApiClient? _apiClient;

  static const String _printerListKey = 'api_saved_printers';
  static const String _defaultPrinterIdKey = 'api_default_printer_id';

  List<PrinterInfo> _printers = [];
  PrinterInfo? _defaultPrinter;
  bool _isInitialized = false;
  bool _isServiceAvailable = false;
  String _orangePiIp = '';

  final Map<String, Map<String, dynamic>> _statusPrint = {};

  Timer? _healthCheckTimer;

  List<PrinterInfo> get printers => List.unmodifiable(_printers);
  PrinterInfo? get defaultPrinter => _defaultPrinter;
  bool get isInitialized => _isInitialized;
  bool get isServiceAvailable => _isServiceAvailable;
  String get orangePiIp => _orangePiIp;
  Map<String, Map<String, dynamic>> get statusPrint =>
      Map.unmodifiable(_statusPrint);

  /// 設置後端API客戶端
  void setApiClient(ApiClient? apiClient) {
    _apiClient = apiClient;
  }

  /// 1, 初始化打印機提供者
  Future<void> initialize({String? orangePiIp}) async {
    try {
      _logger.i('🖨️ 初始化打印機提供者...');

      // 如果提供了IP,更新配置
      if (orangePiIp != null && orangePiIp.isNotEmpty) {
        _orangePiIp = orangePiIp;
        _printApiClient = PrintApiClient(orangePiIp: orangePiIp);
        _logger.i('🖨️ 使用香橙派IP: $orangePiIp');
      } else if (_orangePiIp.isEmpty) {
        _logger.w('⚠️ 香橙派IP地址未配置,請在設置中配置');
        _isInitialized = true;
        notifyListeners();
        return;
      }

      // 載入本地緩存的打印機列表
      await _loadCachedPrinters();

      // 檢查服務可用性
      if (_printApiClient != null) {
        _isServiceAvailable = await _printApiClient!.isServiceAvailable();

        if (_isServiceAvailable) {
          // 從API獲取最新的打印機列表
          await refreshPrinters();
        } else {
          _logger.w('⚠️ 打印服務不可用,使用緩存數據');
        }
      }

      _isInitialized = true;
      notifyListeners();

      _logger.i('🖨️ 打印機提供者初始化完成,載入 ${_printers.length} 個打印機');
    } catch (e) {
      _logger.e('❌ 初始化打印機提供者失敗: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// 2, 更新香橙派IP地址
  Future<void> updateOrangePiIp(String orangePiIp) async {
    try {
      if (orangePiIp.isEmpty) {
        _logger.w('⚠️ IP地址為空');
        return;
      }

      _orangePiIp = orangePiIp;
      _printApiClient = PrintApiClient(orangePiIp: orangePiIp);
      _isServiceAvailable = await _printApiClient!.isServiceAvailable();

      if (_isServiceAvailable) {
        await refreshPrinters();
      }

      notifyListeners();
      _logger.i('✅ 香橙派IP更新為: $orangePiIp');
    } catch (e) {
      _logger.e('❌ 更新IP失敗: $e');
    }
  }

  /// 3, 刷新打印機列表
  Future<void> refreshPrinters() async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return;
    }

    try {
      _logger.i('🔄 刷新打印機列表...');
      final response = await _printApiClient!.getPrintersList();

      if (response.success) {
        _printers = response.printers;
        await _savePrintersToCache();

        // 更新默認打印機狀態
        if (_defaultPrinter != null) {
          final updatedDefault = _printers.firstWhere(
            (p) => p.id == _defaultPrinter!.id,
            orElse: () =>
                _printers.isNotEmpty ? _printers.first : _defaultPrinter!,
          );
          _defaultPrinter = updatedDefault;
        } else if (_printers.isNotEmpty) {
          // 如果沒有默認打印機,設置第一個為默認
          _defaultPrinter = _printers.first;
          await _saveDefaultPrinterId(_defaultPrinter!.id);
        }

        notifyListeners();
        _logger.i('✅ 刷新完成,共 ${_printers.length} 個打印機');
      }
    } catch (e) {
      _logger.e('❌ 刷新打印機列表失敗: $e');
    }
  }

  /// 4, 添加新打印機
  Future<bool> addPrinter({
    required String printerIp,
    String? name,
    String? description,
    String? location,
  }) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return false;
    }

    try {
      _logger.i('➕ 添加打印機: $printerIp');

      // 先測試連接
      final testResult =
          await _printApiClient!.testPrinterConnection(printerIp);
      if (!testResult.connected) {
        _logger.w('⚠️ 無法連接到打印機: ${testResult.message}');
        return false;
      }

      // 連接打印機
      final request = ConnectPrinterRequest(
        printerIp: printerIp,
        name: name ?? 'Printer_${printerIp.replaceAll('.', '_')}',
        description: description ?? '網絡打印機',
        location: location ?? '辦公區',
        protocol: 'ipp',
        port: 631,
        model: 'everywhere',
        testConnection: true,
      );

      final result = await _printApiClient!.connectPrinter(request);

      if (result['success'] == true) {
        // 刷新列表
        await refreshPrinters();
        _logger.i('✅ 成功添加打印機');
        return true;
      } else {
        _logger.w('⚠️ 添加打印機失敗: ${result['message']}');
        return false;
      }
    } catch (e) {
      _logger.e('❌ 添加打印機失敗: $e');
      return false;
    }
  }

  /// 5, 刪除打印機
  Future<bool> removePrinter(int printerId) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return false;
    }

    try {
      _logger.i('🗑️ 刪除打印機 ID: $printerId');

      final result = await _printApiClient!.deletePrinter(printerId);

      if (result['success'] == true) {
        // 從本地列表中移除
        _printers.removeWhere((p) => p.id == printerId);

        // 如果刪除的是默認打印機,清除默認設置
        if (_defaultPrinter?.id == printerId) {
          _defaultPrinter = _printers.isNotEmpty ? _printers.first : null;
          if (_defaultPrinter != null) {
            await _saveDefaultPrinterId(_defaultPrinter!.id);
          } else {
            await _clearDefaultPrinter();
          }
        }

        await _savePrintersToCache();
        notifyListeners();

        _logger.i('✅ 成功刪除打印機');
        return true;
      } else {
        _logger.w('⚠️ 刪除打印機失敗: ${result['message']}');
        return false;
      }
    } catch (e) {
      _logger.e('❌ 刪除打印機失敗: $e');
      return false;
    }
  }

  /// 6, 設置默認打印機
  Future<void> setDefaultPrinter(PrinterInfo printer) async {
    try {
      _defaultPrinter = printer;
      await _saveDefaultPrinterId(printer.id);
      notifyListeners();

      _logger.i('✅ 設置默認打印機: ${printer.name}');
    } catch (e) {
      _logger.e('❌ 設置默認打印機失敗: $e');
    }
  }

  /// 7, 獲取打印機詳情
  Future<PrinterDetails?> getPrinterDetails(int printerId) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return null;
    }

    try {
      final details = await _printApiClient!.getPrinterDetails(printerId);
      _logger.i('✅ 獲取打印機詳情: ${details.name}');
      return details;
    } catch (e) {
      _logger.e('❌ 獲取打印機詳情失敗: $e');
      return null;
    }
  }

  /// 8, 獲取打印機配置選項
  Future<PrinterOptions?> getPrinterOptions(String printerIp) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return null;
    }

    try {
      final options = await _printApiClient!.getPrinterOptions(printerIp);
      _logger.i('✅ 獲取打印機選項: ${options.printerName}');
      return options;
    } catch (e) {
      _logger.e('❌ 獲取打印機選項失敗: $e');
      return null;
    }
  }

  /// 9, 打印PDF文件 (Base64)
  Future<PrintJobResponse?> printPdf({
    required String printerIp,
    required File pdfFile,
    String? title,
    PrintSettings? settings,
  }) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return null;
    }

    try {
      _logger.i('🖨️ 開始打印: ${pdfFile.path}');

      // 讀取PDF文件並轉Base64
      final pdfBytes = await pdfFile.readAsBytes();
      final base64Data = base64Encode(pdfBytes);
      final filename = pdfFile.path.split('/').last;

      final response = await _printApiClient!.printPdfBase64(
        printerIp: printerIp,
        base64Data: base64Data,
        filename: filename,
        title: title ?? filename,
        settings: settings,
      );

      if (response.success) {
        _logger.i('✅ 打印成功: Job ID ${response.jobId}');
      } else {
        _logger.w('⚠️ 打印失敗: ${response.message}');
      }

      return response;
    } catch (e) {
      _logger.e('❌ 打印失敗: $e');
      return null;
    }
  }

  /// 9a, 直接使用Base64打印
  Future<PrintJobResponse?> printPdfBase64({
    required String printerIp,
    required String base64Data,
    required String filename,
    required String title,
    PrintSettings? settings,
  }) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      debugPrint('❌ [PrinterProvider] PrintApiClient 未初始化');
      return null;
    }

    try {
      _logger.i('🖨️ 開始Base64打印: $filename');
      debugPrint('📤 [PrinterProvider] 調用 PrintApiClient.printPdfBase64');
      debugPrint('   打印機IP: $printerIp');
      debugPrint('   文件名: $filename');
      debugPrint('   標題: $title');
      debugPrint('   Base64長度: ${base64Data.length}');
      debugPrint('   設置: ${settings?.toJson()}');

      final response = await _printApiClient!.printPdfBase64(
        printerIp: printerIp,
        base64Data: base64Data,
        filename: filename,
        title: title,
        settings: settings,
      );

      debugPrint('✅ [PrinterProvider] PrintApiClient 調用成功');
      if (response.success) {
        _logger.i('✅ Base64打印成功: Job ID ${response.jobId}');
      } else {
        _logger.w('⚠️ Base64打印失敗: ${response.message}');
      }

      return response;
    } catch (e, stackTrace) {
      _logger.e('❌ Base64打印失敗: $e');
      debugPrint('❌ [PrinterProvider] 捕獲異常:');
      debugPrint('   異常類型: ${e.runtimeType}');
      debugPrint('   異常信息: $e');
      debugPrint('   堆棧跟踪:');
      debugPrint(stackTrace.toString());
      return null;
    }
  }

  /// 10, 測試打印機連接
  Future<bool> testPrinterConnection(String printerIp) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return false;
    }

    try {
      final result = await _printApiClient!.testPrinterConnection(printerIp);
      return result.connected;
    } catch (e) {
      _logger.e('❌ 測試連接失敗: $e');
      return false;
    }
  }

  /// 11, 獲取打印作業列表
  Future<Map<String, dynamic>?> getPrintJobs(
    String printerIp, {
    String jobType = 'all',
  }) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return null;
    }

    try {
      final jobs = await _printApiClient!.getPrinterJobs(
        printerIp,
        jobType: jobType,
      );
      return jobs;
    } catch (e) {
      _logger.e('❌ 獲取打印作業失敗: $e');
      return null;
    }
  }

  /// 12, 取消所有打印作業
  Future<bool> cancelAllJobs(String printerIp) async {
    if (_printApiClient == null) {
      _logger.w('⚠️ 打印服務未初始化');
      return false;
    }

    try {
      final result = await _printApiClient!.cancelAllPrinterJobs(printerIp);
      return result['success'] == true;
    } catch (e) {
      _logger.e('❌ 取消打印作業失敗: $e');
      return false;
    }
  }

  /// 13, 根據IP查找打印機
  PrinterInfo? findPrinterByIp(String printerIp) {
    try {
      return _printers.firstWhere(
        (printer) => printer.ipAddress == printerIp,
      );
    } catch (e) {
      return null;
    }
  }

  /// 14, 根據ID查找打印機
  PrinterInfo? findPrinterById(int id) {
    try {
      return _printers.firstWhere((printer) => printer.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 15, 獲取可用的打印機(在線且接受作業)
  List<PrinterInfo> getAvailablePrinters() {
    return _printers.where((p) => p.isOnline).toList();
  }

  /// 16, 清除所有打印機
  Future<void> clearAllPrinters() async {
    try {
      // 從服務端刪除所有打印機
      for (final printer in _printers) {
        try {
          await _printApiClient?.deletePrinter(printer.id);
        } catch (e) {
          _logger.w('刪除打印機失敗: ${printer.name}');
        }
      }

      _printers.clear();
      _defaultPrinter = null;
      await _savePrintersToCache();
      await _clearDefaultPrinter();
      notifyListeners();

      _logger.i('✅ 清除所有打印機');
    } catch (e) {
      _logger.e('❌ 清除打印機失敗: $e');
    }
  }

  /// 17, 強制重新載入
  Future<void> forceReload() async {
    _isInitialized = false;
    await initialize(orangePiIp: _orangePiIp);
  }

  /// 18, 檢查服務健康狀態
  Future<bool> checkServiceHealth() async {
    if (_printApiClient == null) return false;

    try {
      final health = await _printApiClient!.healthCheck();
      _isServiceAvailable = health.isHealthy;
      notifyListeners();
      return health.isHealthy;
    } catch (e) {
      _isServiceAvailable = false;
      notifyListeners();
      return false;
    }
  }

  // ==================== 私有方法 ====================

  /// 載入緩存的打印機列表
  Future<void> _loadCachedPrinters() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 載入打印機列表
      final printersJson = prefs.getString(_printerListKey);
      if (printersJson != null) {
        final printersList = jsonDecode(printersJson) as List;
        _printers = printersList
            .map((json) => PrinterInfo.fromJson(json as Map<String, dynamic>))
            .toList();
        _logger.i('📦 從緩存載入 ${_printers.length} 個打印機');
      }

      // 載入默認打印機ID
      final defaultPrinterId = prefs.getInt(_defaultPrinterIdKey);
      if (defaultPrinterId != null && _printers.isNotEmpty) {
        _defaultPrinter = findPrinterById(defaultPrinterId);
        _logger.i('📦 從緩存載入默認打印機: ${_defaultPrinter?.name}');
      }
    } catch (e) {
      _logger.e('❌ 載入緩存失敗: $e');
    }
  }

  /// 保存打印機列表到緩存
  Future<void> _savePrintersToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final printersJson =
          jsonEncode(_printers.map((p) => p.toJson()).toList());
      await prefs.setString(_printerListKey, printersJson);
      _logger.d('💾 打印機列表已緩存');
    } catch (e) {
      _logger.e('❌ 保存緩存失敗: $e');
    }
  }

  /// 保存默認打印機ID
  Future<void> _saveDefaultPrinterId(int printerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_defaultPrinterIdKey, printerId);
      _logger.d('💾 默認打印機ID已保存');
    } catch (e) {
      _logger.e('❌ 保存默認打印機ID失敗: $e');
    }
  }

  /// 清除默認打印機
  Future<void> _clearDefaultPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_defaultPrinterIdKey);
    } catch (e) {
      _logger.e('❌ 清除默認打印機失敗: $e');
    }
  }

  /// 19, 更新打印機實際狀態
  void updatePrinterStatus(String ipAddress, String status, String? reason) {
    _statusPrint[ipAddress] = {
      'status': status,
      'reason': reason ?? '',
      'updated_at': DateTime.now().toIso8601String(),
    };
    notifyListeners();
    _logger.i('📊 更新打印機狀態: $ipAddress - $status');
  }

  /// 20, 獲取打印機實際狀態
  Map<String, dynamic>? getPrinterStatus(String ipAddress) {
    return _statusPrint[ipAddress];
  }

  /// 21, 批量測試打印機並上報健康狀態
  Future<void> batchHealthCheck() async {
    if (_apiClient == null) return;

    try {
      _logger.i('🏥 開始批量健康檢查...');

      // 準備香橙派狀態
      Map<String, dynamic> orangePiStatus;
      List<Map<String, dynamic>> printersData = [];

      if (_orangePiIp.isEmpty) {
        // 場景4: 香橙派未配置
        orangePiStatus = {
          'status': 'not_configured',
          'reason': 'Orange Pi IP not set in device settings',
        };
      } else if (_printApiClient == null) {
        // 場景3: 香橙派離線
        orangePiStatus = {
          'ip': _orangePiIp,
          'port': 8080,
          'status': 'offline',
          'reason': 'Print service client not initialized',
          'error_code': 'SERVICE_UNAVAILABLE',
        };
      } else {
        // 嘗試檢查服務健康
        try {
          final startTime = DateTime.now();
          final health = await _printApiClient!.healthCheck().timeout(
                const Duration(seconds: 5),
              );
          final responseTime =
              DateTime.now().difference(startTime).inMilliseconds;

          if (health.isHealthy) {
            // 場景1/2: 香橙派在線
            orangePiStatus = {
              'ip': _orangePiIp,
              'port': 8080,
              'status': 'online',
              'response_time': responseTime,
            };

            // 測試所有打印機
            if (_printers.isNotEmpty) {
              final results = await _printApiClient!.batchTestPrinters(
                  _printers.map((p) => p.ipAddress).toList());

              for (final result in results) {
                final ip = result['ip_address'] as String;
                final status = result['status'] as String;
                final reason = result['reason'] as String?;

                updatePrinterStatus(ip, status, reason);
              }

              // 構建打印機數據
              printersData = _printers.map((printer) {
                final statusData = _statusPrint[printer.ipAddress];
                return {
                  'display_name': printer.displayName,
                  'ip_address': printer.ipAddress,
                  'name': printer.name,
                  'state': printer.state,
                  'uri': printer.uri,
                  'status': statusData?['status'] ?? 'unknown',
                  'reason': statusData?['reason'] ?? '',
                };
              }).toList();
            }
          } else {
            orangePiStatus = {
              'ip': _orangePiIp,
              'port': 8080,
              'status': 'offline',
              'reason': 'Service unhealthy',
              'error_code': 'SERVICE_UNHEALTHY',
            };
          }
        } catch (e) {
          // 場景3: 連接失敗
          orangePiStatus = {
            'ip': _orangePiIp,
            'port': 8080,
            'status': 'offline',
            'reason': e.toString().contains('timeout')
                ? 'Connection timeout after 5s'
                : 'Connection failed: ${e.toString()}',
            'error_code': e.toString().contains('timeout')
                ? 'CONNECTION_TIMEOUT'
                : 'CONNECTION_FAILED',
          };
        }
      }

      // 上報到後端管理系統
      await _apiClient!.printersHealthCheck(
        orangePi: orangePiStatus,
        printers: printersData,
      );

      _logger.i('✅ 批量健康檢查完成');
    } catch (e) {
      _logger.e('❌ 批量健康檢查失敗: $e');
    }
  }

  /// 22, 打印後回調更新狀態
  Future<void> printCallback(
      String printerIp, bool success, String? reason) async {
    try {
      updatePrinterStatus(printerIp, success ? 'online' : 'offline', reason);

      // 使用 ApiClient 上報到後端管理系統
      if (_apiClient != null) {
        await _apiClient!.printersCallback([
          {
            'ip_address': printerIp,
            'status': success ? 'online' : 'offline',
            if (reason != null) 'reason': reason,
          }
        ]);
      }

      _logger.i('📞 打印回調完成: $printerIp');
    } catch (e) {
      _logger.e('❌ 打印回調失敗: $e');
    }
  }

  /// 23, 監控打印作業狀態
  Future<bool> monitorPrintJob(
    String printerIp,
    int cupsJobId,
    int copies,
  ) async {
    if (_printApiClient == null) return false;

    try {
      final waitTime = copies < 3 ? 180 : 300;
      _logger.i('⏱️ 等待 $waitTime 秒後檢查打印作業...');

      await Future.delayed(Duration(seconds: waitTime));

      final activeJobs = await _printApiClient!.getPrinterActiveJobs(printerIp);
      final activeCount = activeJobs['count'] as int? ?? 0;

      if (activeCount == 0) {
        final allJobs = await _printApiClient!.getPrinterJobs(printerIp);
        final jobs = allJobs['jobs'] as List? ?? [];

        if (jobs.isNotEmpty) {
          final latestJob = jobs.first as Map<String, dynamic>;
          final jobState = latestJob['state'] as String?;

          if (jobState == 'completed') {
            _logger.i('✅ 打印作業成功完成');
            await printCallback(printerIp, true, null);
            return true;
          } else {
            _logger.w('⚠️ 打印作業失敗: $jobState');

            final options = await _printApiClient!.getPrinterOptions(printerIp);
            final stateReasons = options.options['printer-state-reasons'];

            await printCallback(printerIp, false, stateReasons);
            return false;
          }
        }
      }

      _logger.i('ℹ️ 打印作業仍在處理中');
      return true;
    } catch (e) {
      _logger.e('❌ 監控打印作業失敗: $e');
      return false;
    }
  }

  /// 24, 啟動定時健康檢查
  void startPeriodicHealthCheck(
      {Duration interval = const Duration(minutes: 30)}) {
    // 停止現有的定時器
    stopPeriodicHealthCheck();

    _logger.i('🏥 啟動打印機健康檢查定時任務，間隔: ${interval.inMinutes}分鐘');

    // 立即執行一次
    batchHealthCheck();

    // 設置定時器
    _healthCheckTimer = Timer.periodic(interval, (_) {
      _logger.i('⏰ [定時任務] 執行打印機健康檢查');
      batchHealthCheck();
    });
  }

  /// 25, 停止定時健康檢查
  void stopPeriodicHealthCheck() {
    if (_healthCheckTimer != null) {
      _healthCheckTimer!.cancel();
      _healthCheckTimer = null;
      _logger.i('🛑 打印機健康檢查定時任務已停止');
    }
  }

  @override
  void dispose() {
    stopPeriodicHealthCheck();
    super.dispose();
  }
}
