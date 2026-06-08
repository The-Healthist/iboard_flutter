import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:iboard_app/models/printer_model.dart';
import 'package:logger/logger.dart';

/// WiFi打印服務API客戶端
/// 基於CUPS的打印服務API,用於管理和控制網絡打印機
class PrintApiClient {
  String _baseUrl;
  final Logger _logger = Logger();
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Duration _connectTimeout = Duration(seconds: 10);
  static const Duration _printTimeout = Duration(seconds: 60);

  PrintApiClient({
    required String orangePiIp,
    int port = 8080,
    http.Client? httpClient,
  })  : _baseUrl = 'http://$orangePiIp:$port',
        _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// 1, 更新香橙派IP地址
  void updateOrangePiIp(String orangePiIp, {int port = 8080}) {
    if (orangePiIp.isEmpty) {
      _logger.w(' 香橙派IP地址為空,請在設置中配置');
      throw Exception('請先在設置中配置香橙派IP地址');
    }
    _baseUrl = 'http://$orangePiIp:$port';
    _logger.i(' 更新打印服務地址: $_baseUrl');
  }

  /// 2, 獲取當前服務地址
  String get baseUrl => _baseUrl;

  /// 2a, 關閉由客戶端自身建立的 HTTP 連接
  void close() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  /// 3, 構建完整URL
  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    final fullPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$_baseUrl$fullPath');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      return uri.replace(queryParameters: queryParameters);
    }
    return uri;
  }

  /// 4, 處理HTTP響應
  Map<String, dynamic> _handleResponse(http.Response response, String apiName) {
    final String decodedBody = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decodedBody.isEmpty) {
        return {'success': true};
      }
      try {
        final decoded = json.decode(decodedBody);
        return _mapFromObject(decoded) ?? {};
      } catch (e) {
        _logger.e(' [$apiName] JSON解析失敗: $e');
        throw Exception('$apiName: JSON解析失敗');
      }
    } else {
      _logger.e(' [$apiName] 請求失敗 (Status: ${response.statusCode})');
      String errorMessage = response.reasonPhrase ?? '未知錯誤';
      try {
        final errorData = json.decode(decodedBody);
        final errorMap = _mapFromObject(errorData);
        if (errorMap != null) {
          errorMessage =
              (errorMap['message'] ?? errorMap['error'])?.toString() ??
                  errorMessage;
        }
      } catch (_) {
        if (decodedBody.isNotEmpty) {
          errorMessage = decodedBody;
        }
      }
      throw Exception('$apiName: $errorMessage (${response.statusCode})');
    }
  }

  /// 5, 健康檢查 - GET /api/health
  Future<HealthCheckResponse> healthCheck() async {
    try {
      _logger.i(' [健康檢查] 檢查打印服務狀態...');
      final response = await _httpClient
          .get(_buildUri('/api/health'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '健康檢查');
      final result = HealthCheckResponse.fromJson(data);

      if (result.isHealthy) {
        _logger.i(' [健康檢查] 打印服務運行正常');
      } else {
        _logger.w(' [健康檢查] 打印服務狀態異常: ${result.status}');
      }

      return result;
    } catch (e) {
      _logger.e(' [健康檢查] 失敗: $e');
      rethrow;
    }
  }

  /// 6, 測試打印機連接 - POST /api/printers/test
  Future<TestConnectionResponse> testPrinterConnection(String printerIp) async {
    try {
      _logger.i(' [測試連接] 測試打印機: $printerIp');
      final response = await _httpClient
          .post(
            _buildUri('/api/printers/test'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'printer_ip': printerIp}),
          )
          .timeout(_connectTimeout);

      final data = _handleResponse(response, '測試連接');
      final result = TestConnectionResponse.fromJson(data);

      if (result.connected) {
        _logger.i(' [測試連接] 打印機連接成功: $printerIp');
      } else {
        _logger.w(' [測試連接] 打印機連接失敗: $printerIp');
      }

      return result;
    } catch (e) {
      _logger.e(' [測試連接] 失敗: $e');
      rethrow;
    }
  }

  /// 7, 連接打印機 - POST /api/printers/connect
  Future<Map<String, dynamic>> connectPrinter(
      ConnectPrinterRequest request) async {
    try {
      _logger.i(' [連接打印機] IP: ${request.printerIp}, 名稱: ${request.name}');
      final response = await _httpClient
          .post(
            _buildUri('/api/printers/connect'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(request.toJson()),
          )
          .timeout(_connectTimeout);

      final data = _handleResponse(response, '連接打印機');

      if (data['success'] == true) {
        _logger.i(' [連接打印機] 成功: ${request.printerIp}');
      } else {
        _logger.w(' [連接打印機] 失敗: ${data['message']}');
      }

      return data;
    } catch (e) {
      _logger.e(' [連接打印機] 失敗: $e');
      rethrow;
    }
  }

  /// 8, 獲取打印機列表 - GET /api/printers
  Future<PrintersListResponse> getPrintersList() async {
    try {
      _logger.i(' [獲取列表] 獲取所有打印機...');
      final response = await _httpClient
          .get(_buildUri('/api/printers'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '獲取打印機列表');
      final result = PrintersListResponse.fromJson(data);

      _logger.i(' [獲取列表] 成功獲取 ${result.count} 個打印機');

      return result;
    } catch (e) {
      _logger.e(' [獲取列表] 失敗: $e');
      rethrow;
    }
  }

  /// 9, 獲取單個打印機詳情 - GET /api/printers/{id}
  Future<PrinterDetails> getPrinterDetails(int printerId) async {
    try {
      _logger.i(' [打印機詳情] 獲取打印機 ID: $printerId');
      final response = await _httpClient
          .get(_buildUri('/api/printers/$printerId'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '獲取打印機詳情');
      final printerData = _mapFromObject(data['printer']);

      if (data['success'] == true && printerData != null) {
        final result = PrinterDetails.fromJson(printerData);
        _logger.i(' [打印機詳情] 成功: ${result.name}');
        return result;
      } else {
        throw Exception('獲取打印機詳情失敗: 無效的響應數據');
      }
    } catch (e) {
      _logger.e(' [打印機詳情] 失敗: $e');
      rethrow;
    }
  }

  /// 10, 更新打印機信息 - PUT /api/printers/{id}
  Future<Map<String, dynamic>> updatePrinter(
    int printerId,
    Map<String, dynamic> updates,
  ) async {
    try {
      _logger.i(' [更新打印機] ID: $printerId');
      final response = await _httpClient
          .put(
            _buildUri('/api/printers/$printerId'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(updates),
          )
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '更新打印機');

      if (data['success'] == true) {
        _logger.i(' [更新打印機] 成功: $printerId');
      }

      return data;
    } catch (e) {
      _logger.e(' [更新打印機] 失敗: $e');
      rethrow;
    }
  }

  /// 11, 刪除打印機 - DELETE /api/printers/{id}
  Future<Map<String, dynamic>> deletePrinter(int printerId) async {
    try {
      _logger.i(' [刪除打印機] ID: $printerId');
      final response = await _httpClient
          .delete(_buildUri('/api/printers/$printerId'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '刪除打印機');

      if (data['success'] == true) {
        _logger.i(' [刪除打印機] 成功: $printerId');
      }

      return data;
    } catch (e) {
      _logger.e(' [刪除打印機] 失敗: $e');
      rethrow;
    }
  }

  /// 12, 獲取打印機詳細配置選項 - GET /api/printers/ip/{ip}/options
  Future<PrinterOptions> getPrinterOptions(String printerIp) async {
    try {
      _logger.i(' [打印機選項] 獲取配置: $printerIp');
      final response = await _httpClient
          .get(_buildUri('/api/printers/ip/$printerIp/options'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '獲取打印機選項');

      if (data['success'] == true) {
        final result = PrinterOptions.fromJson(data);
        _logger.i(' [打印機選項] 成功: ${result.printerName}');
        return result;
      } else {
        throw Exception('獲取打印機選項失敗: 無效的響應數據');
      }
    } catch (e) {
      _logger.e(' [打印機選項] 失敗: $e');
      rethrow;
    }
  }

  /// 13, Base64打印 - POST /api/printers/ip/{ip}/print/base64
  Future<PrintJobResponse> printPdfBase64({
    required String printerIp,
    required String base64Data,
    required String filename,
    required String title,
    PrintSettings? settings,
  }) async {
    try {
      _logger.i(
          ' [Base64打印] 準備提交打印任務: printer=$printerIp, file=$filename, bytes(base64)=${base64Data.length}');

      // 使用格式2（簡化版本）- 扁平化參數結構
      final printSettings = settings ?? const PrintSettings();
      final requestBody = {
        'printer_ip': printerIp,
        'file_data': base64Data,
        'filename': filename,
        'title': title,
        'copies': printSettings.copies,
        'color_mode': printSettings.colorMode,
        'media': printSettings.media,
        'duplex': printSettings.duplex,
      };

      // 只有啟用雙面打印時才添加 duplex_type
      if (printSettings.duplex && printSettings.duplexType != null) {
        requestBody['duplex_type'] = printSettings.duplexType!;
      }

      // 添加其他可選參數（如果有值）
      if (printSettings.quality.isNotEmpty) {
        requestBody['quality'] = printSettings.quality;
      }
      if (printSettings.orientation.isNotEmpty) {
        requestBody['orientation'] = printSettings.orientation;
      }
      if (printSettings.pageRange != null &&
          printSettings.pageRange!.isNotEmpty) {
        requestBody['page_range'] = printSettings.pageRange!;
      }

      final jsonBody = json.encode(requestBody);
      final startTime = DateTime.now();

      final response = await _httpClient
          .post(
            _buildUri('/api/printers/ip/$printerIp/print/base64'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonBody,
          )
          .timeout(_printTimeout);

      final duration = DateTime.now().difference(startTime);
      _logger.i(
          ' [Base64打印] 打印服務響應: status=${response.statusCode}, duration=${duration.inMilliseconds}ms');

      final data = _handleResponse(response, 'Base64打印');

      final result = PrintJobResponse.fromJson(data);

      if (result.success) {
        _logger.i(
            ' [Base64打印] 成功: Job ID ${result.jobId}, CUPS Job ID ${result.cupsJobId}');
      } else {
        _logger.w(' [Base64打印] 失敗: ${result.message}');
      }

      return result;
    } catch (e, stackTrace) {
      _logger.e(' [Base64打印] 失敗', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// 14, 獲取指定打印機所有作業 - GET /api/printers/ip/{ip}/jobs
  Future<Map<String, dynamic>> getPrinterJobs(
    String printerIp, {
    String jobType = 'all',
  }) async {
    try {
      _logger.i(' [打印作業] 獲取作業列表: $printerIp, 類型: $jobType');
      final queryParams = jobType != 'all' ? {'type': jobType} : null;

      final response = await _httpClient
          .get(_buildUri('/api/printers/ip/$printerIp/jobs', queryParams))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '獲取打印作業');

      if (data['success'] == true) {
        final count = data['count'] ?? 0;
        _logger.i(' [打印作業] 成功獲取 $count 個作業');
      }

      return data;
    } catch (e) {
      _logger.e(' [打印作業] 失敗: $e');
      rethrow;
    }
  }

  /// 15, 獲取指定打印機活動作業 - GET /api/printers/ip/{ip}/jobs/active
  Future<Map<String, dynamic>> getActivePrinterJobs(String printerIp) async {
    try {
      _logger.i(' [活動作業] 獲取活動作業: $printerIp');
      final response = await _httpClient
          .get(_buildUri('/api/printers/ip/$printerIp/jobs/active'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '獲取活動作業');

      if (data['success'] == true) {
        final count = data['count'] ?? 0;
        _logger.i(' [活動作業] 成功獲取 $count 個活動作業');
      }

      return data;
    } catch (e) {
      _logger.e(' [活動作業] 失敗: $e');
      rethrow;
    }
  }

  /// 16, 取消指定打印機所有活動作業 - POST /api/printers/ip/{ip}/jobs/cancel-all
  Future<Map<String, dynamic>> cancelAllPrinterJobs(String printerIp) async {
    try {
      _logger.i(' [取消作業] 取消所有活動作業: $printerIp');
      final response = await _httpClient
          .post(_buildUri('/api/printers/ip/$printerIp/jobs/cancel-all'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '取消所有作業');

      if (data['success'] == true) {
        final cancelledCount = data['cancelled_count'] ?? 0;
        _logger.i(' [取消作業] 成功取消 $cancelledCount 個作業');
      }

      return data;
    } catch (e) {
      _logger.e(' [取消作業] 失敗: $e');
      rethrow;
    }
  }

  /// 17, 檢查服務是否可用
  Future<bool> isServiceAvailable() async {
    try {
      if (_baseUrl.isEmpty || _baseUrl == 'http://:8080') {
        _logger.w(' [服務檢查] 香橙派IP地址未配置');
        return false;
      }
      final result = await healthCheck();
      return result.isHealthy;
    } catch (e) {
      _logger.w(' [服務檢查] 打印服務不可用: $e');
      return false;
    }
  }

  /// 18, 快速添加打印機（使用默認配置）
  Future<Map<String, dynamic>> quickAddPrinter({
    required String printerIp,
    String? name,
    String? description,
  }) async {
    final request = ConnectPrinterRequest(
      printerIp: printerIp,
      name: name ?? 'Printer_${printerIp.replaceAll('.', '_')}',
      description: description ?? '網絡打印機',
      location: '辦公區',
      protocol: 'ipp',
      port: 631,
      model: 'everywhere',
      testConnection: true,
    );

    return await connectPrinter(request);
  }

  /// 19, 根據IP查找打印機
  Future<PrinterInfo?> findPrinterByIp(String printerIp) async {
    try {
      final response = await getPrintersList();
      return response.printers.firstWhere(
        (printer) => printer.ipAddress == printerIp,
        orElse: () => throw Exception('未找到IP為 $printerIp 的打印機'),
      );
    } catch (e) {
      _logger.w(' [查找打印機] 未找到: $printerIp');
      return null;
    }
  }

  /// 20, 獲取打印機活動作業 - GET /api/printers/ip/{printerIp}/jobs/active
  Future<Map<String, dynamic>> getPrinterActiveJobs(String printerIp) async {
    try {
      _logger.i(' [活動作業] 獲取打印機活動作業: $printerIp');

      final response = await _httpClient
          .get(_buildUri('/api/printers/ip/$printerIp/jobs/active'))
          .timeout(_requestTimeout);

      final data = _handleResponse(response, '獲取活動作業');
      _logger.i(' [活動作業] 獲取成功: ${data['count'] ?? 0}個活動作業');

      return data;
    } catch (e) {
      _logger.e(' [活動作業] 失敗: $e');
      rethrow;
    }
  }

  /// 21, 批量測試打印機連接
  Future<List<Map<String, dynamic>>> batchTestPrinters(
    List<String> printerIps,
  ) async {
    _logger.i(' [批量測試] 測試 ${printerIps.length} 個打印機連接');

    final results = <Map<String, dynamic>>[];

    for (final ip in printerIps) {
      try {
        final testResult = await testPrinterConnection(ip);

        results.add({
          'ip_address': ip,
          'status': testResult.connected ? 'online' : 'offline',
          'reason': testResult.connected ? '' : testResult.message,
        });
      } catch (e) {
        results.add({
          'ip_address': ip,
          'status': 'offline',
          'reason': '連接失敗: $e',
        });
      }
    }

    _logger.i(' [批量測試] 完成: ${results.length}個結果');
    return results;
  }

  Map<String, dynamic>? _mapFromObject(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }
}
