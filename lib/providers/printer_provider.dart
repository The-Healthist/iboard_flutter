import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:iboard_app/http/api_print.dart';
import 'package:iboard_app/http/api_client.dart';
import 'package:iboard_app/models/printer_model.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 打印機提供者
class PrinterProvider extends ChangeNotifier {
  static final PrinterProvider _instance = PrinterProvider._internal();
  factory PrinterProvider() => _instance;
  PrinterProvider._internal();

  final Logger _logger = Logger();
  PrintApiClient? _printApiClient;
  ApiClient? _apiClient;

  static const String _printerListKey = 'api_saved_printers';
  static const String _defaultPrinterIdKey = 'api_default_printer_id';
  static const String _orangePiIpKey = 'orange_pi_ip';
  static const Duration _startupProbeTimeout = Duration(seconds: 2);

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

  void setApiClient(ApiClient? apiClient) => _apiClient = apiClient;

  void _setPrintApiClient(PrintApiClient? client) {
    _printApiClient?.close();
    _printApiClient = client;
  }

  /// 1, 初始化
  Future<void> initialize({
    String? orangePiIp,
    bool probeService = true,
  }) async {
    try {
      _logger.i(' 初始化打印機提供者...');

      // 優先使用傳入的IP,否則從緩存載入
      if (orangePiIp != null && orangePiIp.isNotEmpty) {
        _orangePiIp = orangePiIp;
        await _saveOrangePiIp(orangePiIp);
        _setPrintApiClient(PrintApiClient(orangePiIp: orangePiIp));
      } else {
        // 從緩存載入IP
        final cachedIp = await _loadOrangePiIp();
        if (cachedIp != null && cachedIp.isNotEmpty) {
          _orangePiIp = cachedIp;
          _setPrintApiClient(PrintApiClient(orangePiIp: cachedIp));
          _logger.i(' 從緩存載入香橙派IP: $cachedIp');
        } else {
          _logger.w(' 香橙派IP地址未配置');
          _isInitialized = true;
          notifyListeners();
          return;
        }
      }

      await _loadCachedPrinters();

      if (probeService && _printApiClient != null) {
        _isServiceAvailable = await _probeServiceAvailability(
          timeout: _startupProbeTimeout,
        );
        if (_isServiceAvailable) await refreshPrinters();
      }

      _isInitialized = true;
      notifyListeners();
      _logger.i(' 初始化完成,載入 ${_printers.length} 個打印機');
    } catch (e) {
      _logger.e(' 初始化失敗: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// 2, 更新香橙派IP
  Future<void> updateOrangePiIp(String orangePiIp) async {
    try {
      if (orangePiIp.isEmpty) return;

      _orangePiIp = orangePiIp;
      await _saveOrangePiIp(orangePiIp);
      _setPrintApiClient(PrintApiClient(orangePiIp: orangePiIp));
      _isServiceAvailable = await _probeServiceAvailability(
        timeout: _startupProbeTimeout,
      );

      if (_isServiceAvailable) await refreshPrinters();
      notifyListeners();
      _logger.i(' 香橙派IP更新: $orangePiIp');
    } catch (e) {
      _logger.e(' 更新IP失敗: $e');
    }
  }

  /// 3, 刷新打印機列表
  Future<void> refreshPrinters() async {
    if (_printApiClient == null) return;

    try {
      final response = await _printApiClient!.getPrintersList();
      if (!response.success) return;

      _printers = response.printers;
      await _savePrintersToCache();

      if (_defaultPrinter != null) {
        _defaultPrinter = _printers.firstWhere(
          (p) => p.id == _defaultPrinter!.id,
          orElse: () =>
              _printers.isNotEmpty ? _printers.first : _defaultPrinter!,
        );
      } else if (_printers.isNotEmpty) {
        _defaultPrinter = _printers.first;
        await _saveDefaultPrinterId(_defaultPrinter!.id);
      }

      notifyListeners();
      _logger.i(' 刷新完成,共 ${_printers.length} 個打印機');
    } catch (e) {
      _logger.e(' 刷新失敗: $e');
    }
  }

  /// 4, 添加打印機
  Future<bool> addPrinter({
    required String printerIp,
    String? name,
    String? description,
    String? location,
  }) async {
    if (_printApiClient == null) return false;

    try {
      final testResult =
          await _printApiClient!.testPrinterConnection(printerIp);
      if (!testResult.connected) {
        _logger.w(' 無法連接: ${testResult.message}');
        return false;
      }

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
        await refreshPrinters();
        _logger.i(' 添加成功');
        return true;
      }

      _logger.w(' 添加失敗: ${result['message']}');
      return false;
    } catch (e) {
      _logger.e(' 添加失敗: $e');
      return false;
    }
  }

  /// 5, 刪除打印機
  Future<bool> removePrinter(int printerId) async {
    if (_printApiClient == null) return false;

    try {
      final result = await _printApiClient!.deletePrinter(printerId);
      if (result['success'] != true) {
        _logger.w(' 刪除失敗: ${result['message']}');
        return false;
      }

      _printers.removeWhere((p) => p.id == printerId);

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
      _logger.i(' 刪除成功');
      return true;
    } catch (e) {
      _logger.e(' 刪除失敗: $e');
      return false;
    }
  }

  /// 6, 設置默認打印機
  Future<void> setDefaultPrinter(PrinterInfo printer) async {
    _defaultPrinter = printer;
    await _saveDefaultPrinterId(printer.id);
    notifyListeners();
  }

  /// 7, 獲取打印機詳情
  Future<PrinterDetails?> getPrinterDetails(int printerId) async {
    if (_printApiClient == null) return null;
    try {
      return await _printApiClient!.getPrinterDetails(printerId);
    } catch (e) {
      _logger.e(' 獲取詳情失敗: $e');
      return null;
    }
  }

  /// 8, 獲取打印機配置
  Future<PrinterOptions?> getPrinterOptions(String printerIp) async {
    if (_printApiClient == null) return null;
    try {
      return await _printApiClient!.getPrinterOptions(printerIp);
    } catch (e) {
      _logger.e(' 獲取配置失敗: $e');
      return null;
    }
  }

  /// 9, 打印PDF文件
  Future<PrintJobResponse?> printPdf({
    required String printerIp,
    required File pdfFile,
    String? title,
    PrintSettings? settings,
  }) async {
    if (_printApiClient == null) return null;

    try {
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

      _logger.i(response.success
          ? ' 打印成功: Job ${response.jobId}'
          : ' 打印失敗: ${response.message}');
      return response;
    } catch (e) {
      _logger.e(' 打印失敗: $e');
      return null;
    }
  }

  /// 9a, Base64打印
  Future<PrintJobResponse?> printPdfBase64({
    required String printerIp,
    required String base64Data,
    required String filename,
    required String title,
    PrintSettings? settings,
  }) async {
    if (_printApiClient == null) return null;

    try {
      final response = await _printApiClient!.printPdfBase64(
        printerIp: printerIp,
        base64Data: base64Data,
        filename: filename,
        title: title,
        settings: settings,
      );

      _logger.i(response.success
          ? ' 打印成功: Job ${response.jobId}'
          : ' 打印失敗: ${response.message}');
      return response;
    } catch (e) {
      _logger.e(' 打印失敗: $e');
      return null;
    }
  }

  /// 10, 測試連接
  Future<bool> testPrinterConnection(String printerIp) async {
    if (_printApiClient == null) return false;
    try {
      final result = await _printApiClient!.testPrinterConnection(printerIp);
      return result.connected;
    } catch (e) {
      _logger.e(' 測試失敗: $e');
      return false;
    }
  }

  /// 11, 獲取打印作業
  Future<Map<String, dynamic>?> getPrintJobs(
    String printerIp, {
    String jobType = 'all',
  }) async {
    if (_printApiClient == null) return null;
    try {
      return await _printApiClient!.getPrinterJobs(printerIp, jobType: jobType);
    } catch (e) {
      _logger.e(' 獲取作業失敗: $e');
      return null;
    }
  }

  /// 12, 取消所有作業
  Future<bool> cancelAllJobs(String printerIp) async {
    if (_printApiClient == null) return false;
    try {
      final result = await _printApiClient!.cancelAllPrinterJobs(printerIp);
      return result['success'] == true;
    } catch (e) {
      _logger.e(' 取消失敗: $e');
      return false;
    }
  }

  /// 13, 根據IP查找
  PrinterInfo? findPrinterByIp(String printerIp) {
    try {
      return _printers.firstWhere((p) => p.ipAddress == printerIp);
    } catch (e) {
      return null;
    }
  }

  /// 14, 根據ID查找
  PrinterInfo? findPrinterById(int id) {
    try {
      return _printers.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  /// 15, 獲取可用打印機
  List<PrinterInfo> getAvailablePrinters() =>
      _printers.where((p) => p.isOnline).toList();

  /// 16, 清除所有打印機
  Future<void> clearAllPrinters() async {
    try {
      for (final printer in _printers) {
        try {
          await _printApiClient?.deletePrinter(printer.id);
        } catch (e) {
          _logger.w('刪除失敗: ${printer.name}');
        }
      }

      _printers.clear();
      _defaultPrinter = null;
      await _savePrintersToCache();
      await _clearDefaultPrinter();
      notifyListeners();
      _logger.i(' 清除完成');
    } catch (e) {
      _logger.e(' 清除失敗: $e');
    }
  }

  /// 17, 強制重載
  Future<void> forceReload() async {
    _isInitialized = false;
    await initialize(orangePiIp: _orangePiIp);
  }

  /// 18, 檢查服務健康
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

  Future<bool> _probeServiceAvailability({
    Duration timeout = _startupProbeTimeout,
  }) async {
    final client = _printApiClient;
    if (client == null) return false;

    try {
      return await client.isServiceAvailable().timeout(timeout);
    } catch (e) {
      _logger.w(' 打印服務不可用，跳過打印機網絡初始化: $e');
      return false;
    }
  }

  Future<void> _loadCachedPrinters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final printersJson = prefs.getString(_printerListKey);

      if (printersJson != null) {
        final decoded = jsonDecode(printersJson);
        if (decoded is List) {
          _printers = decoded
              .whereType<Map>()
              .map((json) => PrinterInfo.fromJson(_parseMap(json)))
              .toList();
        }
      }

      final defaultPrinterId = prefs.getInt(_defaultPrinterIdKey);
      if (defaultPrinterId != null && _printers.isNotEmpty) {
        _defaultPrinter = findPrinterById(defaultPrinterId);
      }
    } catch (e) {
      _logger.e(' 載入緩存失敗: $e');
    }
  }

  Future<void> _savePrintersToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final printersJson =
          jsonEncode(_printers.map((p) => p.toJson()).toList());
      await prefs.setString(_printerListKey, printersJson);
    } catch (e) {
      _logger.e(' 保存緩存失敗: $e');
    }
  }

  Future<void> _saveDefaultPrinterId(int printerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_defaultPrinterIdKey, printerId);
    } catch (e) {
      _logger.e(' 保存ID失敗: $e');
    }
  }

  Future<void> _clearDefaultPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_defaultPrinterIdKey);
    } catch (e) {
      _logger.e(' 清除失敗: $e');
    }
  }

  Future<String?> _loadOrangePiIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_orangePiIpKey);
    } catch (e) {
      _logger.e(' 載入IP失敗: $e');
      return null;
    }
  }

  Future<void> _saveOrangePiIp(String ip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_orangePiIpKey, ip);
    } catch (e) {
      _logger.e(' 保存IP失敗: $e');
    }
  }

  /// 19, 更新狀態
  void updatePrinterStatus(String ipAddress, String status, String? reason) {
    _statusPrint[ipAddress] = {
      'status': status,
      'reason': reason ?? '',
      'updated_at': DateTime.now().toIso8601String(),
    };
    notifyListeners();
  }

  /// 20, 獲取狀態
  Map<String, dynamic>? getPrinterStatus(String ipAddress) =>
      _statusPrint[ipAddress];

  /// 21, 批量健康檢查 - 30分鐘定時任務核心邏輯
  Future<void> batchHealthCheck() async {
    if (_apiClient == null) {
      _logger.w(' [健康檢查] ApiClient未設置');
      return;
    }

    try {
      _logger.i(' [健康檢查] 開始執行...');
      Map<String, dynamic> orangePiStatus;
      List<Map<String, dynamic>> printersData = [];

      if (_orangePiIp.isEmpty) {
        _logger.w(' [健康檢查] 香橙派未配置');
        orangePiStatus = {
          'status': 'not_configured',
          'reason': 'Orange Pi IP not set',
        };
      } else if (_printApiClient == null) {
        _logger.w(' [健康檢查] 打印服務未初始化');
        orangePiStatus = {
          'ip': _orangePiIp,
          'port': 8080,
          'status': 'offline',
          'reason': 'Service not initialized',
          'error_code': 'SERVICE_UNAVAILABLE',
        };
      } else {
        try {
          final startTime = DateTime.now();
          final health = await _printApiClient!
              .healthCheck()
              .timeout(const Duration(seconds: 5));
          final responseTime =
              DateTime.now().difference(startTime).inMilliseconds;

          if (health.isHealthy) {
            _logger.i(' [健康檢查] 香橙派在線 (響應: ${responseTime}ms)');
            orangePiStatus = {
              'ip': _orangePiIp,
              'port': 8080,
              'status': 'online',
              'response_time': responseTime,
            };

            try {
              final printersList = await _printApiClient!.getPrintersList();
              if (printersList.success && printersList.printers.isNotEmpty) {
                _logger.i(' [健康檢查] 獲取到 ${printersList.printers.length} 個打印機');

                final printerIps =
                    printersList.printers.map((p) => p.ipAddress).toList();
                final testResults =
                    await _printApiClient!.batchTestPrinters(printerIps);

                for (final result in testResults) {
                  final ipAddress = result['ip_address']?.toString() ?? '';
                  if (ipAddress.isEmpty) continue;
                  updatePrinterStatus(
                    ipAddress,
                    result['status']?.toString() ?? 'unknown',
                    result['reason']?.toString(),
                  );
                }

                printersData = printersList.printers.map((printer) {
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

                _logger.i(' [健康檢查] 完成 ${printersData.length} 個打印機測試');
              } else {
                _logger.w(' [健康檢查] 未獲取到打印機列表');
              }
            } catch (e) {
              _logger.e(' [健康檢查] 獲取打印機列表失敗: $e');
            }
          } else {
            _logger.w(' [健康檢查] 香橙派服務異常');
            orangePiStatus = {
              'ip': _orangePiIp,
              'port': 8080,
              'status': 'offline',
              'reason': 'Service unhealthy',
              'error_code': 'SERVICE_UNHEALTHY',
            };
          }
        } catch (e) {
          final isTimeout = e.toString().contains('timeout');
          _logger.e(' [健康檢查] 香橙派連接失敗: ${isTimeout ? "超時" : e.toString()}');
          orangePiStatus = {
            'ip': _orangePiIp,
            'port': 8080,
            'status': 'offline',
            'reason': isTimeout
                ? 'Connection timeout after 5s'
                : 'Connection failed: $e',
            'error_code':
                isTimeout ? 'CONNECTION_TIMEOUT' : 'CONNECTION_FAILED',
          };
        }
      }

      _logger.i(' [健康檢查] 上報健康狀態到後台...');
      await _apiClient!.printersHealthCheck(
        orangePi: orangePiStatus,
        printers: printersData,
      );
      _logger.i(' [健康檢查] 完成並上報成功');
    } catch (e) {
      _logger.e(' [健康檢查] 失敗: $e');
    }
  }

  /// 22, 打印回調 - 上報打印結果到後台
  Future<void> printCallback(
      String printerIp, bool success, String? reason) async {
    await printCallbackWithMarkerLevels(printerIp, success, reason, null);
  }

  /// 22a, 打印回調（帶墨盒信息）
  Future<void> printCallbackWithMarkerLevels(
    String printerIp,
    bool success,
    String? reason,
    String? markerLevels,
  ) async {
    if (_apiClient == null) {
      _logger.w(' [打印回調] ApiClient未設置');
      return;
    }

    try {
      updatePrinterStatus(printerIp, success ? 'online' : 'offline', reason);

      Map<String, dynamic> orangePiStatus;
      List<Map<String, dynamic>> printersData = [];

      if (_orangePiIp.isEmpty) {
        orangePiStatus = {
          'status': 'not_configured',
          'reason': 'Orange Pi IP not set',
        };
        _logger.i(' [打印回調] 香橙派狀態: not_configured');
      } else if (_printApiClient == null) {
        orangePiStatus = {
          'ip': _orangePiIp,
          'port': 8080,
          'status': 'offline',
          'reason': 'Service not initialized',
        };
        _logger.i(' [打印回調] 香橙派狀態: offline (未初始化)');
      } else {
        try {
          final startTime = DateTime.now();
          final health = await _printApiClient!
              .healthCheck()
              .timeout(const Duration(seconds: 5));
          final responseTime =
              DateTime.now().difference(startTime).inMilliseconds;

          orangePiStatus = {
            'ip': _orangePiIp,
            'port': 8080,
            'status': health.isHealthy ? 'online' : 'offline',
            'response_time': responseTime,
          };
          _logger.i(
              ' [打印回調] 香橙派狀態: ${health.isHealthy ? "online" : "offline"} (響應: ${responseTime}ms)');
        } catch (e) {
          orangePiStatus = {
            'ip': _orangePiIp,
            'port': 8080,
            'status': 'offline',
            'reason': e.toString().contains('timeout')
                ? 'Connection timeout after 5s'
                : 'Connection failed',
          };
          _logger.i(' [打印回調] 香橙派狀態: offline (連接失敗)');
        }
      }

      final printer = findPrinterByIp(printerIp);
      if (printer != null) {
        final printerData = {
          'display_name': printer.displayName,
          'ip_address': printer.ipAddress,
          'name': printer.name,
          'state': printer.state,
          'uri': printer.uri,
          'status': success ? 'online' : 'offline',
          'reason': reason ?? '',
        };

        if (markerLevels != null && markerLevels.isNotEmpty) {
          printerData['marker_levels'] = markerLevels;
        }

        printersData = [printerData];

        _logger.i(' [打印回調] 打印機數據:');
        _logger.i('   名稱: ${printer.displayName}');
        _logger.i('   IP: ${printer.ipAddress}');
        _logger.i('   狀態: ${success ? "online" : "offline"}');
        _logger.i('   原因: ${reason ?? "無"}');
        if (markerLevels != null && markerLevels.isNotEmpty) {
          _logger.i('   墨盒: $markerLevels');
        }
      } else {
        final printerData = {
          'ip_address': printerIp,
          'status': success ? 'online' : 'offline',
          'reason': reason ?? '',
        };

        if (markerLevels != null && markerLevels.isNotEmpty) {
          printerData['marker_levels'] = markerLevels;
        }

        printersData = [printerData];

        _logger.i(' [打印回調] 打印機數據 (簡化):');
        _logger.i('   IP: $printerIp');
        _logger.i('   狀態: ${success ? "online" : "offline"}');
        _logger.i('   原因: ${reason ?? "無"}');
      }

      _logger.i(' [打印回調] 發送回調請求到後台...');
      await _apiClient!.printersCallback(
        orangePi: orangePiStatus,
        printers: printersData,
      );
      _logger.i(' [打印回調] 後台接收成功');
    } catch (e) {
      _logger.e(' [打印回調] 失敗: $e');
    }
  }

  /// 23, 監控打印作業
  Future<bool> monitorPrintJob(
      String printerIp, int cupsJobId, int copies) async {
    if (_printApiClient == null) return false;

    try {
      final waitTime = copies < 3 ? 180 : 300;
      await Future.delayed(Duration(seconds: waitTime));

      final activeJobs = await _printApiClient!.getPrinterActiveJobs(printerIp);
      final activeCount = _parseInt(activeJobs['count']);

      if (activeCount == 0) {
        final allJobs = await _printApiClient!.getPrinterJobs(printerIp);
        final jobs = allJobs['jobs'] as List? ?? [];

        if (jobs.isNotEmpty) {
          final latestJob = _nullableMap(jobs.first);
          final jobState = latestJob?['state']?.toString();

          if (jobState == 'completed') {
            await printCallback(printerIp, true, null);
            return true;
          } else {
            final options = await _printApiClient!.getPrinterOptions(printerIp);
            final stateReasons = options.options['printer-state-reasons'];
            await printCallback(printerIp, false, stateReasons);
            return false;
          }
        }
      }
      return true;
    } catch (e) {
      _logger.e(' 監控失敗: $e');
      return false;
    }
  }

  /// 24, 啟動定時健康檢查
  Future<void> startPeriodicHealthCheck(
      {Duration interval = const Duration(minutes: 30)}) async {
    stopPeriodicHealthCheck();
    final shouldStart = await _probeServiceAvailability(
      timeout: _startupProbeTimeout,
    );
    if (!shouldStart) {
      _isServiceAvailable = false;
      _logger.w(' 香橙派不可用，不啟動打印機定時健康檢查');
      notifyListeners();
      return;
    }

    unawaited(batchHealthCheck());
    _healthCheckTimer = Timer.periodic(interval, (_) => batchHealthCheck());
  }

  /// 25, 停止定時健康檢查
  void stopPeriodicHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  @override
  void dispose() {
    stopPeriodicHealthCheck();
    _setPrintApiClient(null);
    super.dispose();
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

int _parseInt(Object? value, {int defaultValue = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? defaultValue;
  }
  return defaultValue;
}
