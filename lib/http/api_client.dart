import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

// Custom exception class for API-related errors
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  final dynamic errorData;

  ApiException({this.statusCode, required this.message, this.errorData});

  @override
  String toString() {
    return 'ApiException: $message (Status Code: $statusCode)'
        '${errorData != null ? "\nError Data: $errorData" : ""}';
  }
}

class ApiClient {
  final String _baseUrl;
  String? _token;
  final Logger _logger = Logger();

  // 網絡請求配置
  static const Duration _requestTimeout = Duration(seconds: 30); // 30秒超時
  static const int _maxRetryAttempts = 1; // 最大重試1次
  static const Duration _retryDelay = Duration(seconds: 3); // 重試間隔3秒

  // For managing token refresh
  bool _isRefreshingToken = false; // True if a refresh operation is active
  Future<String?>?
      _tokenRefreshFuture; // Future for the active refresh operation

  Future<String?> Function()? onNeedsTokenRefresh;

  ApiClient({required String baseUrl, this.onNeedsTokenRefresh})
      : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl;

  void setAuthToken(String? token) {
    _token = token;
    if (token != null && token.isNotEmpty) {
      // _logger.i('Auth token set in ApiClient.');
    } else {
      // _logger.i('Auth token cleared in ApiClient.');
    }
  }

  Uri _buildUri(String pathOrFullUrl, Map<String, String>? queryParameters) {
    String fullUrl;
    if (pathOrFullUrl.startsWith('http://') ||
        pathOrFullUrl.startsWith('https://')) {
      fullUrl = pathOrFullUrl;
    } else {
      final path =
          pathOrFullUrl.startsWith('/') ? pathOrFullUrl : '/$pathOrFullUrl';
      fullUrl = '$_baseUrl$path';
    }

    if (queryParameters != null && queryParameters.isNotEmpty) {
      return Uri.parse(fullUrl).replace(queryParameters: queryParameters);
    }
    return Uri.parse(fullUrl);
  }

  Map<String, String> _getHeaders(
      {bool requiresAuth = false, String? contentType}) {
    final headers = <String, String>{};
    if (contentType != null) {
      headers['Content-Type'] = contentType;
    }
    // Use the internal _token for authorization
    if (requiresAuth && _token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  ///2, 處理返回數組數據的HTTP響應
  Future<List<Map<String, dynamic>>> _handleArrayResponse(
      http.Response response, String apiName) async {
    final String decodedBody = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // _logger.i('$apiName successful (Status: ${response.statusCode})');
      if (decodedBody.isEmpty) {
        return []; // Return empty list for empty successful response
      }
      try {
        final decoded = json.decode(decodedBody);

        // 檢查是否是服務端返回的錯誤響應
        if (decoded is Map &&
            decoded.containsKey('status') &&
            decoded['status'] == 'error') {
          final errorMessage = decoded['message'] ?? 'Unknown server error';
          _logger.e('Server returned error for $apiName: $errorMessage');
          throw ApiException(
            statusCode: response.statusCode,
            message: errorMessage,
            errorData: decodedBody,
          );
        }

        if (decoded is List) {
          return decoded
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        } else if (decoded is Map &&
            decoded.containsKey('data') &&
            decoded['data'] is List) {
          return (decoded['data'] as List)
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
        } else {
          throw Exception(
              'Expected array response but got: ${decoded.runtimeType}');
        }
      } catch (e, stackTrace) {
        _logger.e(
            'Failed to decode JSON array for $apiName. Body: $decodedBody',
            error: e,
            stackTrace: stackTrace);
        throw ApiException(
          statusCode: response.statusCode,
          message:
              'Successfully received response for $apiName, but failed to decode JSON array.',
          errorData: decodedBody,
        );
      }
    } else {
      _logger.w(
          '$apiName failed (Status: ${response.statusCode}), Body: $decodedBody');
      dynamic errorData;
      try {
        errorData = decodedBody.isNotEmpty ? json.decode(decodedBody) : null;
      } catch (_) {
        errorData = decodedBody;
      }
      throw ApiException(
        statusCode: response.statusCode,
        message: '$apiName failed',
        errorData: errorData,
      );
    }
  }

  Future<Map<String, dynamic>> _handleResponse(
      http.Response response, String apiName) async {
    final String decodedBody = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // _logger.i('$apiName successful (Status: ${response.statusCode})');
      if (decodedBody.isEmpty) {
        return {}; // Return empty map for empty successful response
      }
      try {
        return json.decode(decodedBody) as Map<String, dynamic>;
      } catch (e, stackTrace) {
        _logger.e('Failed to decode JSON for $apiName. Body: $decodedBody',
            error: e, stackTrace: stackTrace);
        throw ApiException(
          statusCode: response.statusCode,
          message:
              'Successfully received response for $apiName, but failed to decode JSON.',
          errorData: decodedBody,
        );
      }
    } else {
      _logger.w('$apiName 失敗 (狀態: ${response.statusCode}), 響應體: $decodedBody');
      dynamic errorData;
      try {
        errorData = decodedBody.isNotEmpty ? json.decode(decodedBody) : null;
      } catch (_) {
        errorData = decodedBody; // 如果錯誤響應不是 JSON，則使用原始響應體
      }
      throw ApiException(
        statusCode: response.statusCode,
        message: 'API 請求 $apiName 失敗，狀態碼為 ${response.statusCode}',
        errorData: errorData,
      );
    }
  }

  // Helper to initiate or get existing refresh future
  Future<String?> _initiateAndGetTokenRefreshFuture() {
    if (!_isRefreshingToken) {
      // If no refresh is active, start one
      _isRefreshingToken = true;
      final completer = Completer<String?>();
      _tokenRefreshFuture = completer.future;

      // _logger.i('Starting new token refresh process via onNeedsTokenRefresh.');
      onNeedsTokenRefresh!().then((newToken) {
        if (newToken != null && newToken.isNotEmpty) {
          completer.complete(newToken);
        } else {
          _logger.w('令牌刷新過程完成但未返回新令牌。');
          completer.complete(null); // 如果沒有令牌，則解析為 null
        }
      }).catchError((e, stackTrace) {
        _logger.e('令牌刷新過程執行失敗。', error: e, stackTrace: stackTrace);
        completer.completeError(e); // 傳播錯誤
      }).whenComplete(() {
        _isRefreshingToken = false; // 允許在此操作完成或失敗後進行新的刷新嘗試
      });
    } else {
      _logger.i('令牌刷新已在進行中，返回現有 Future。');
    }
    return _tokenRefreshFuture!;
  }

  Future<http.Response> _sendRequest(
    Future<http.Response> Function() requestFunction, {
    required String apiNameForLog,
    bool isLoginRequest = false,
    bool isHealthTestRequest = false,
  }) async {
    // 區塊 1: 預檢健康檢查 (如果適用)
    if (!isLoginRequest &&
        !isHealthTestRequest &&
        _token != null &&
        _token!.isNotEmpty) {
      try {
        // healthTest() 本身會呼叫 _sendRequest 並將 isHealthTestRequest 設為 true
        await healthTest();
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          _logger.w('為 $apiNameForLog 進行的預檢健康檢查因 401 失敗。嘗試刷新令牌。');
          if (onNeedsTokenRefresh == null) {
            _logger.w('onNeedsTokenRefresh 為空，無法刷新令牌。重新拋出健康檢查的 401 錯誤。');
            rethrow;
          }

          try {
            final newToken = await _initiateAndGetTokenRefreshFuture();
            if (newToken != null && newToken.isNotEmpty) {
              // 令牌透過 $apiNameForLog 的健康檢查成功刷新。主請求將繼續。
              // 可選：重新運行 healthTest 以確認，但會增加延遲。
              // await healthTest();
            } else {
              _logger.w(
                  '為 $apiNameForLog 進行的 401 健康檢查後，令牌刷新未產生新令牌。重新拋出原始的 401 錯誤。');
              throw ApiException(
                  statusCode: e.statusCode,
                  message: '健康檢查 401 後刷新令牌失敗 (無新令牌)。',
                  errorData: e.errorData);
            }
          } catch (refreshError) {
            _logger.e('為 $apiNameForLog 處理 401 健康檢查後等待令牌刷新時出錯。',
                error: refreshError);
            throw ApiException(
                statusCode: e.statusCode,
                message: '健康檢查 401 後令牌刷新過程失敗: $refreshError',
                errorData: e.errorData);
          }
        } else {
          // 來自健康檢查的非 401 ApiException
          // 對於 500 錯誤等服務器端問題，我們將允許主請求繼續，而不是完全失敗。
          // 這可以防止服務器問題阻止所有請求。
          _logger.w(
              '為 $apiNameForLog 進行的預檢健康檢查因非 401 ApiException 失敗 (狀態: ${e.statusCode})。允許主請求繼續。錯誤: ${e.message}');
          // 對於非 401 錯誤，不拋出，讓主請求繼續
        }
      } catch (otherError) {
        // 捕獲來自 healthTest() 的其他非 ApiException 錯誤
        // 對於意外錯誤，我們也將允許主請求繼續
        _logger.w('為 $apiNameForLog 進行的預檢健康檢查因意外錯誤失敗。允許主請求繼續。錯誤: $otherError');
        // 對於意外錯誤，不拋出，讓主請求繼續
      }
    }

    // 區塊 2: 執行帶有超時和重試的主請求
    http.Response? response;
    Exception? lastException;

    for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
      try {
        // 應用超時到請求函數
        response = await requestFunction().timeout(
          _requestTimeout,
          onTimeout: () {
            throw Exception(
                '請求超時 (${_requestTimeout.inSeconds}秒) - $apiNameForLog');
          },
        );

        // 如果請求成功，跳出重試循環
        break;
      } catch (e, stackTrace) {
        lastException = e is Exception ? e : Exception(e.toString());

        // 詳細記錄網絡錯誤類型並生成用戶友好消息
        String errorType = 'Unknown';
        String userFriendlyMessage = '';

        if (e.toString().contains('Failed host lookup') ||
            e.toString().contains('No address associated with hostname')) {
          errorType = 'DNS解析失敗';
          userFriendlyMessage = '🌐 無法連接到伺服器，請檢查網絡連接或聯繫管理員';
        } else if (e.toString().contains('SocketException')) {
          errorType = 'Socket連接錯誤';
          userFriendlyMessage = '🔌 網絡連接異常，請檢查您的網絡設置';
        } else if (e.toString().contains('TimeoutException') ||
            e.toString().contains('請求超時')) {
          errorType = '請求超時';
          userFriendlyMessage = '⏱️ 伺服器響應超時，請稍後重試';
        } else if (e.toString().contains('ClientException')) {
          errorType = '客戶端錯誤';
          userFriendlyMessage = '📱 應用連接錯誤，請重啟應用或檢查網絡';
        } else {
          userFriendlyMessage = '❌ 網絡請求失敗，請稍後重試';
        }

        if (attempt == _maxRetryAttempts) {
          // 最後一次嘗試失敗，拋出用戶友好的異常
          _logger.e(
              '$apiNameForLog - 所有 $_maxRetryAttempts 次請求嘗試均失敗 (最後錯誤類型: $errorType)',
              error: e,
              stackTrace: stackTrace);

          // 拋出包含用戶友好消息的異常
          throw ApiException(
            message: userFriendlyMessage,
            statusCode: null,
            errorData: e.toString(),
          );
        } else {
          // 還有重試機會，記錄警告並等待
          _logger.w(
              '$apiNameForLog - 第 $attempt 次請求失敗 ($errorType)，${_retryDelay.inSeconds}秒後重試');
          await Future.delayed(_retryDelay);
        }
      }
    }

    // 如果 response 仍然為 null，說明所有重試都失敗了
    if (response == null) {
      throw lastException ?? Exception('請求失敗，未知錯誤 - $apiNameForLog');
    }

    // 區塊 3: 處理主請求的 401 (重試邏輯)
    if (response.statusCode == 401 && !isLoginRequest) {
      _logger.w('為實際請求 $apiNameForLog 收到 401。嘗試刷新令牌。');
      if (onNeedsTokenRefresh == null) {
        _logger.w(
            'onNeedsTokenRefresh 為空，無法為 $apiNameForLog 刷新令牌。原始 401 將由 _handleResponse 處理。');
        return response; // 讓 _handleResponse 處理 401
      }

      try {
        final newToken = await _initiateAndGetTokenRefreshFuture();
        if (newToken != null && newToken.isNotEmpty) {
          // 令牌為 $apiNameForLog 成功刷新。重試原始請求。
          response = await requestFunction(); // 重試原始請求函數
        } else {
          _logger.w('為 $apiNameForLog 刷新令牌未產生新令牌。原始 401 響應將被處理。');
          // 讓原始 401 響應返回給 _handleResponse
        }
      } catch (refreshError) {
        _logger.e('為 $apiNameForLog 處理主請求 401 時等待令牌刷新出錯。', error: refreshError);
        // 讓原始 401 響應返回給 _handleResponse
      }
    }
    return response!;
  }

  // --- API Methods based on httpapi.json ---

  // 1. Login
  // Endpoint: POST <<baseUrl>>/api/device/login
  // Body: { "deviceId": "string" }
  Future<Map<String, dynamic>> login({required String deviceId}) async {
    const String endpointPath = '/api/device/login';
    final Uri url = _buildUri(endpointPath, null);
    final String requestBody = json.encode({'deviceId': deviceId});
    final Map<String, String> headers =
        _getHeaders(requiresAuth: false, contentType: 'application/json');

    // _logger.i('Attempting login for deviceId: $deviceId');

    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        isLoginRequest: true, // Mark as login request
        apiNameForLog: 'login');

    final Map<String, dynamic> responseData =
        await _handleResponse(response, 'login');

    if (responseData.containsKey('token') &&
        responseData['token'] is String &&
        (responseData['token'] as String).isNotEmpty) {
      setAuthToken(responseData['token'] as String);
      // _logger.i('Login successful, token stored in ApiClient.');
    } else {
      _logger.w(
          'Login response did not contain a valid token. Clearing any existing token in ApiClient.');
      setAuthToken(null);
    }
    return responseData;
  }

  // 2. Get Advertisements for Building
  // Endpoint: GET <<baseUrl>>/api/device/client/advertisements
  // Future<Map<String, dynamic>> getAdvertisementsBuilding() async {
  //   const String endpointPath = '/api/device/client/advertisements';
  //   final Uri url = _buildUri(endpointPath, null);
  //   final Map<String, String> headers =
  //       _getHeaders(requiresAuth: true, contentType: 'application/json');

  //   // _logger.i('Fetching advertisements for building.');
  //   final http.Response response = await _sendRequest(
  //       () => http.get(url, headers: headers),
  //       apiNameForLog: 'getAdvertisementsBuilding');
  //   return _handleResponse(response, 'getAdvertisementsBuilding');
  // }

  // 3. Get Notices for Building
  // Endpoint: GET <<baseUrl>>/api/device/client/notices
  // Future<Map<String, dynamic>> getNoticesBuilding() async {
  //   const String endpointPath = '/api/device/client/notices';
  //   final Uri url = _buildUri(endpointPath, null);
  //   final Map<String, String> headers =
  //       _getHeaders(requiresAuth: true, contentType: 'application/json');

  //   // _logger.i('Fetching notices for building.');
  //   final http.Response response = await _sendRequest(
  //       () => http.get(url, headers: headers),
  //       apiNameForLog: 'getNoticesBuilding');
  //   return _handleResponse(response, 'getNoticesBuilding');
  // }

  // 4. Health Test
  // Endpoint: POST <<baseUrl>>/api/device/client/health_test
  // Body: "" (empty string), ContentType: "application/json"
  Future<Map<String, dynamic>> healthTest() async {
    const String endpointPath = '/api/device/client/health_test';
    final Uri url = _buildUri(endpointPath, null);
    // Health test requires auth to check the token itself.
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    // _logger.i('Performing health test.');
    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: ""),
        apiNameForLog: 'healthTest',
        isHealthTestRequest:
            true // Mark as health test request to prevent pre-flight check on itself
        );
    return _handleResponse(response, 'healthTest');
  }

  // 5. Get Building Notices by ID (named "notice get" in JSON)
  // Endpoint: POST https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-notices
  // Body: {"blg_id":"string"}
  Future<Map<String, dynamic>> getBuildingNotices(
      {required String blgId}) async {
    const String fullUrl =
        'https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-notices';
    final Uri url = _buildUri(fullUrl, null);
    final String requestBody = json.encode({'blg_id': blgId});
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    // _logger.i('Fetching building notices for blgId: $blgId');
    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        apiNameForLog: 'getBuildingNotices');
    return _handleResponse(response, 'getBuildingNotices');
  }

  // 6. Admin login (using email/password)
  // Endpoint: POST <<baseUrl>>/api/admin/login
  // Body: { "email": "string", "password": "string" }
  Future<Map<String, dynamic>> adminLogin({
    required String email,
    required String password,
  }) async {
    const String endpointPath = '/api/admin/login';
    final Uri url = _buildUri(endpointPath, null);
    final String requestBody =
        json.encode({'email': email, 'password': password});

    // 使用固定的 Authorization header
    final Map<String, String> headers = {
      'Authorization':
          'Basic OmV5SmhiR2NpT2lKSVV6STFOaUlzSW5SNWNDSTZJa3BYVkNKOS5leUpsYldGcGJDSTZJbUZrYldsdVFHVjRZVzF3YkdVdVkyOXRJaXdpWlhod0lqb3hOelExTnpZMU5UQTVMQ0pwWkNJNk1Td2lhWE5CWkcxcGJpSTZkSEoxWlgwLm9XcExTV1BLOTNSWlNKVFotbTE1bUt6R3BaMTJlZExKa0RTR3Q0cUVZS2M=',
      'Content-Type': 'application/json',
    };

    // _logger.i('Attempting admin login for email: $email');
    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        isLoginRequest: true,
        apiNameForLog: 'adminLogin');

    final Map<String, dynamic> responseData =
        await _handleResponse(response, 'adminLogin');

    // _logger.i('Admin login successful for email: $email');
    return responseData;
  }

  // 7. Create device
  // Endpoint: POST <<baseUrl>>/api/admin/device
  // Body: { "deviceId": "string", "buildingId": number, "settings": {...} }
  Future<Map<String, dynamic>> createDevice({
    required String deviceId,
    required String adminToken,
    int buildingId = 20,
    Map<String, dynamic>? settings,
  }) async {
    const String endpointPath = '/api/admin/device';
    final Uri url = _buildUri(endpointPath, null);

    // 默認設置
    final defaultSettings = {
      "arrearageUpdateDuration": 5,
      "noticeUpdateDuration": 10,
      "advertisementUpdateDuration": 15,
      "advertisementPlayDuration": 30,
      "noticeStayDuration": 10,
      "normalToAnnouncementCarouselDuration": 10,
      "announcementCarouselToFullAdsCarouselDuration": 10,
      "printPassWord": "1090119",
    };

    final String requestBody = json.encode({
      'deviceId': deviceId,
      'buildingId': buildingId,
      'settings': settings ?? defaultSettings,
    });

    final Map<String, String> headers = {
      'Authorization': 'Bearer $adminToken',
      'Content-Type': 'application/json',
    };

    // _logger.i('Creating device with deviceId: $deviceId');
    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        apiNameForLog: 'createDevice');

    final Map<String, dynamic> responseData =
        await _handleResponse(response, 'createDevice');

    // _logger.i('Device created successfully: $deviceId');
    return responseData;
  }

  /// 8. 獲取欠費數據
  /// Endpoint: POST https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-mf-table
  /// Body: {"blg_id": "string", "ptype": "mf"}
  // Future<List<Map<String, dynamic>>> getArrearage({String? buildingId}) async {
  //   // 驗證Building ID格式
  //   if (buildingId != null && !_isValidBuildingId(buildingId)) {
  //     throw ApiException(
  //       statusCode: 400,
  //       message: 'Building ID 格式無效，只能包含數字和英文字母',
  //       errorData: 'Invalid building ID: $buildingId',
  //     );
  //   }

  //   const String fullUrl =
  //       'https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-mf-table';
  //   final Uri url = _buildUri(fullUrl, null);
  //   final Map<String, dynamic> requestBodyMap = {
  //     'ptype': 'mf',
  //     if (buildingId != null) 'blg_id': buildingId,
  //   };
  //   final String requestBody = json.encode(requestBodyMap);
  //   final Map<String, String> headers =
  //       _getHeaders(requiresAuth: true, contentType: 'application/json');

  //   _logger.i('獲取欠費數據，樓宇ID: $buildingId');
  //   final http.Response response = await _sendRequest(
  //       () => http.post(url, headers: headers, body: requestBody),
  //       apiNameForLog: 'getArrearage');
  //   return _handleArrayResponse(response, 'getArrearage');
  // }

  ///9, 驗證Building ID格式
  bool _isValidBuildingId(String buildingId) {
    // Building ID只能包含數字和英文字母
    final RegExp validPattern = RegExp(r'^[a-zA-Z0-9]+$');
    return validPattern.hasMatch(buildingId) && buildingId.isNotEmpty;
  }

  ///10. 獲取全屏廣告列表
  // Future<List<Map<String, dynamic>>> getFullAdvertisementsBuilding() async {
  //   const String endpointPath = '/api/device/client/full_advertisements';
  //   final Uri url = _buildUri(endpointPath, null);
  //   final Map<String, String> headers =
  //       _getHeaders(requiresAuth: true, contentType: 'application/json');

  //   final http.Response response = await _sendRequest(
  //       () => http.get(url, headers: headers),
  //       apiNameForLog: 'getFullAdvertisementsBuilding');
  //   return _handleArrayResponse(response, 'getFullAdvertisementsBuilding');
  // }

  ///11. 獲取頂端廣告列表
  // Future<List<Map<String, dynamic>>> getTopAdvertisementsBuilding() async {
  //   const String endpointPath = '/api/device/client/top_advertisements';
  //   final Uri url = _buildUri(endpointPath, null);
  //   final Map<String, String> headers =
  //       _getHeaders(requiresAuth: true, contentType: 'application/json');

  //   final http.Response response = await _sendRequest(
  //       () => http.get(url, headers: headers),
  //       apiNameForLog: 'getTopAdvertisementsBuilding');
  //   return _handleArrayResponse(response, 'getTopAdvertisementsBuilding');
  // }

  ///12. 輪播頂端廣告順序
  Future<List<Map<String, dynamic>>> getCarouselTopAdvertisements() async {
    const String endpointPath =
        '/api/device/client/carousel/top_advertisements';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getCarouselTopAdvertisements');
    return _handleArrayResponse(response, 'getCarouselTopAdvertisements');
  }

  ///13. 輪播完整廣告列表
  Future<List<Map<String, dynamic>>> getCarouselFullAdvertisements() async {
    const String endpointPath =
        '/api/device/client/carousel/full_advertisements';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getCarouselFullAdvertisements');
    return _handleArrayResponse(response, 'getCarouselFullAdvertisements');
  }

  ///14. 輪播通知列表
  Future<List<Map<String, dynamic>>> getCarouselNotices() async {
    const String endpointPath = '/api/device/client/carousel/notices';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getCarouselNotices');
    return _handleArrayResponse(response, 'getCarouselNotices');
  }

  ///15. 獲取應用版本資訊
  Future<Map<String, dynamic>> getAppVersion() async {
    const String endpointPath = '/api/app/version';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: false, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getAppVersion');
    return _handleResponse(response, 'getAppVersion');
  }

  ///16. 獲取香港特區政府新聞公報RSS
  /// Endpoint: GET http://www.info.gov.hk/gia/rss/general_zh.xml
  Future<List<Map<String, dynamic>>> getNewsAnnouncements() async {
    const String fullUrl = 'http://www.info.gov.hk/gia/rss/general_zh.xml';
    final Uri url = _buildUri(fullUrl, null);

    // RSS介面不需要認證，使用基本headers
    final Map<String, String> headers = {
      'Content-Type': 'application/xml; charset=utf-8',
      'User-Agent': 'iBoard_Flutter/1.0',
    };

    _logger.i('獲取香港特區政府新聞公報RSS數據');

    try {
      final http.Response response = await _sendRequest(
          () => http.get(url, headers: headers),
          apiNameForLog: 'getNewsAnnouncements');

      // 處理XML響應
      return _handleRssXmlResponse(response, 'getNewsAnnouncements');
    } catch (e) {
      _logger.e('獲取新聞公報失敗: $e');
      rethrow;
    }
  }

  ///16.1. 獲取香港電台財經新聞RSS
  /// Endpoint: GET https://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cfinance.xml
  Future<List<Map<String, dynamic>>> getRthkNews() async {
    const String fullUrl =
        'https://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cfinance.xml';
    final Uri url = _buildUri(fullUrl, null);

    // RSS介面不需要認證，使用基本headers
    final Map<String, String> headers = {
      'Content-Type': 'application/xml; charset=utf-8',
      'User-Agent': 'iBoard_Flutter/1.0',
      'Accept': 'application/xml, text/xml, */*',
      'Cache-Control': 'no-cache',
    };

    _logger.i('🌐 開始獲取香港電台財經新聞RSS數據');

    try {
      // 增加超時時間到60秒
      final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers).timeout(
          const Duration(seconds: 60), // 增加到60秒
          onTimeout: () {
            throw Exception('RTHK新聞RSS請求超時 (60秒)');
          },
        ),
        apiNameForLog: 'getRthkNews',
      );

      // 處理XML響應
      return _handleRssXmlResponse(response, 'getRthkNews');
    } catch (e) {
      _logger.e('❌ 獲取RTHK新聞失敗: $e');

      // 如果是超時錯誤，提供更友好的錯誤信息
      if (e.toString().contains('超時')) {
        throw ApiException(
          statusCode: null,
          message: '❌ RTHK新聞RSS請求超時，請檢查網絡連接或稍後重試',
          errorData: 'TimeoutException: ${e.toString()}',
        );
      }

      rethrow;
    }
  }

  ///17. 處理RSS XML響應
  Future<List<Map<String, dynamic>>> _handleRssXmlResponse(
      http.Response response, String apiName) async {
    final String decodedBody = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _logger.i('$apiName 成功 (狀態碼: ${response.statusCode})');

      if (decodedBody.isEmpty) {
        return [];
      }

      try {
        // 簡單的XML解析，提取item元素
        final List<Map<String, dynamic>> items = [];

        // 使用正則表達式提取item標籤內容
        final RegExp itemRegex = RegExp(
          r'<item>(.*?)</item>',
          dotAll: true,
          multiLine: true,
        );

        final RegExp titleRegex = RegExp(r'<title>(.*?)</title>', dotAll: true);
        final RegExp guidRegex = RegExp(r'<guid>(.*?)</guid>', dotAll: true);
        final RegExp linkRegex = RegExp(r'<link>(.*?)</link>', dotAll: true);
        final RegExp pubDateRegex =
            RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true);
        final RegExp descriptionRegex =
            RegExp(r'<description>(.*?)</description>', dotAll: true);

        final matches = itemRegex.allMatches(decodedBody);

        for (final match in matches) {
          final itemContent = match.group(1)!;

          final title = titleRegex.firstMatch(itemContent)?.group(1) ?? '';
          final guid = guidRegex.firstMatch(itemContent)?.group(1) ?? '';
          final link = linkRegex.firstMatch(itemContent)?.group(1) ?? '';
          final pubDate = pubDateRegex.firstMatch(itemContent)?.group(1) ?? '';
          final description =
              descriptionRegex.firstMatch(itemContent)?.group(1) ?? '';

          if (title.isNotEmpty && guid.isNotEmpty) {
            items.add({
              'title': title,
              'guid': guid,
              'link': link,
              'pubDate': pubDate,
              'description': description,
            });
          }
        }

        _logger.i('成功解析 ${items.length} 條新聞公報');
        return items;
      } catch (e, stackTrace) {
        _logger.e('解析RSS XML失敗: $e', error: e, stackTrace: stackTrace);
        throw ApiException(
          statusCode: response.statusCode,
          message: '成功接收響應，但解析RSS XML失敗',
          errorData: decodedBody,
        );
      }
    } else {
      _logger.w('$apiName 失敗 (狀態碼: ${response.statusCode}), 響應體: $decodedBody');
      throw ApiException(
        statusCode: response.statusCode,
        message: '$apiName 失敗',
        errorData: decodedBody,
      );
    }
  }

  ///18. 獲取物業管理費用
  /// Endpoint: POST https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-management-fee-status
  /// Body: {"ptype": "mf", "blg_id": "string"}
  Future<Map<String, dynamic>> getManagementFeeStatus(
      {String? buildingId}) async {
    // 驗證Building ID格式
    if (buildingId != null && !_isValidBuildingId(buildingId)) {
      throw ApiException(
        statusCode: 400,
        message: 'Building ID 格式無效，只能包含數字和英文字母',
        errorData: 'Invalid building ID: $buildingId',
      );
    }

    const String fullUrl =
        'https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-management-fee-status';
    final Uri url = _buildUri(fullUrl, null);
    final Map<String, dynamic> requestBodyMap = {
      'ptype': 'mf',
      if (buildingId != null) 'blg_id': buildingId,
    };
    final String requestBody = json.encode(requestBodyMap);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        apiNameForLog: 'getManagementFeeStatus');
    return _handleResponse(response, 'getManagementFeeStatus');
  }

  ///19. 獲取物業其他費用
  /// Endpoint: POST https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-other-fee-status
  /// Body: {"ptype": "mf", "blg_id": "string"}
  Future<Map<String, dynamic>> getOtherFeeStatus({String? buildingId}) async {
    // 驗證Building ID格式
    if (buildingId != null && !_isValidBuildingId(buildingId)) {
      throw ApiException(
        statusCode: 400,
        message: 'Building ID 格式無效，只能包含數字和英文字母',
        errorData: 'Invalid building ID: $buildingId',
      );
    }

    const String fullUrl =
        'https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-other-fee-status';
    final Uri url = _buildUri(fullUrl, null);
    final Map<String, dynamic> requestBodyMap = {
      'ptype': 'mf',
      if (buildingId != null) 'blg_id': buildingId,
    };
    final String requestBody = json.encode(requestBodyMap);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        apiNameForLog: 'getOtherFeeStatus');
    return _handleResponse(response, 'getOtherFeeStatus');
  }
}
