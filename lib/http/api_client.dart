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

  // 网络请求配置
  static const Duration _requestTimeout = Duration(seconds: 30); // 30秒超时
  static const int _maxRetryAttempts = 1; // 最大重试1次
  static const Duration _retryDelay = Duration(seconds: 3); // 重试间隔3秒

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

  ///2, 处理返回数组数据的HTTP响应
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

        // 检查是否是服务端返回的错误响应
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
      _logger.w(
          '$apiName failed (Status: ${response.statusCode}), Body: $decodedBody');
      dynamic errorData;
      try {
        errorData = decodedBody.isNotEmpty ? json.decode(decodedBody) : null;
      } catch (_) {
        errorData =
            decodedBody; // If error response is not JSON, use the raw body
      }
      // Do not throw ApiException for 401 here if it's handled by _sendRequest retry logic.
      // The _sendRequest will throw if retry fails or is not applicable.
      // However, _handleResponse is also called by the login method directly after _sendRequest.
      // So, if it's a 401 and it wasn't retried (e.g. login call itself, or refresh failed), it should be thrown.
      // The current _sendRequest logic re-throws or throws original if refresh fails.
      // This means _handleResponse will receive the final response (either success, or failure after retry attempt).
      throw ApiException(
        statusCode: response.statusCode,
        message:
            'API request $apiName failed with status code ${response.statusCode}',
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
          // _logger.i(
          //     'Token refresh process completed successfully with a new token.');
          completer.complete(newToken);
        } else {
          _logger.w(
              'Token refresh process completed but no new token was returned.');
          completer.complete(null); // Resolve with null if no token
        }
      }).catchError((e, stackTrace) {
        _logger.e('Token refresh process failed execution.',
            error: e, stackTrace: stackTrace);
        completer.completeError(e); // Propagate error
      }).whenComplete(() {
        _isRefreshingToken =
            false; // Allow new refresh attempts after this one completes or fails
      });
    } else {
      _logger
          .i('Token refresh already in progress, returning existing future.');
    }
    return _tokenRefreshFuture!;
  }

  Future<http.Response> _sendRequest(
    Future<http.Response> Function() requestFunction, {
    required String apiNameForLog,
    bool isLoginRequest = false,
    bool isHealthTestRequest = false, // New flag for healthTest itself
    int maxRetries = 0, // 0 means no retry
    Duration retryDelay = const Duration(seconds: 0),
  }) async {
    // Section 1: Pre-flight health check (if applicable)
    if (!isLoginRequest &&
        !isHealthTestRequest &&
        _token != null &&
        _token!.isNotEmpty) {
      // _logger.i('Performing pre-request health check for $apiNameForLog.');
      try {
        // healthTest() itself calls _sendRequest with isHealthTestRequest = true
        await healthTest();
        // _logger.i('Pre-request health check successful for $apiNameForLog.');
      } on ApiException catch (e) {
        if (e.statusCode == 401) {
          _logger.w(
              'Pre-request health check for $apiNameForLog failed with 401. Attempting token refresh.');
          if (onNeedsTokenRefresh == null) {
            _logger.w(
                'onNeedsTokenRefresh is null, cannot refresh token. Rethrowing 401 from health check.');
            throw e;
          }

          try {
            final newToken = await _initiateAndGetTokenRefreshFuture();
            if (newToken != null && newToken.isNotEmpty) {
              // _logger.i(
              //     'Token refreshed successfully via health check for $apiNameForLog. Main request will proceed.');
              // Optionally, re-run healthTest to confirm, but adds latency.
              // await healthTest();
            } else {
              _logger.w(
                  'Token refresh after health check 401 for $apiNameForLog did not yield a new token. Rethrowing original 401 from health check.');
              throw ApiException(
                  statusCode: e.statusCode,
                  message:
                      'Failed to refresh token after health check 401 (no new token).',
                  errorData: e.errorData);
            }
          } catch (refreshError) {
            _logger.e(
                'Error awaiting token refresh after health check 401 for $apiNameForLog.',
                error: refreshError);
            throw ApiException(
                statusCode: e.statusCode,
                message:
                    'Token refresh process failed after health check 401: $refreshError',
                errorData: e.errorData);
          }
        } else {
          // Non-401 ApiException from health check
          // For server-side issues like 500 errors, we'll allow the main request to proceed
          // rather than failing completely. This prevents server issues from blocking all requests.
          _logger.w(
              'Pre-request health check for $apiNameForLog failed with non-401 ApiException (Status: ${e.statusCode}). Allowing main request to proceed. Error: ${e.message}');
          // Don't throw for non-401 errors, let the main request proceed
        }
      } catch (otherError) {
        // Catch other non-ApiException errors from healthTest()
        // For unexpected errors, we'll also allow the main request to proceed
        _logger.w(
            'Pre-request health check for $apiNameForLog failed with an unexpected error. Allowing main request to proceed. Error: $otherError');
        // Don't throw for unexpected errors, let the main request proceed
      }
    }

    // Section 2: Execute the main request with timeout and retry
    http.Response? response;
    Exception? lastException;

    for (int attempt = 1; attempt <= _maxRetryAttempts; attempt++) {
      try {
        // _logger.i('$apiNameForLog - 尝试第 $attempt/$_maxRetryAttempts 次请求');

        // 应用超时到请求函数
        response = await requestFunction().timeout(
          _requestTimeout,
          onTimeout: () {
            throw Exception(
                '请求超时 (${_requestTimeout.inSeconds}秒) - $apiNameForLog');
          },
        );

        // 如果请求成功，跳出重试循环
        // _logger.i(
        //     '$apiNameForLog - 第 $attempt 次请求成功 (状态码: ${response.statusCode})');
        break;
      } catch (e, stackTrace) {
        lastException = e is Exception ? e : Exception(e.toString());

        // 详细记录网络错误类型并生成用户友好消息
        String errorType = 'Unknown';
        String userFriendlyMessage = '';

        if (e.toString().contains('Failed host lookup') ||
            e.toString().contains('No address associated with hostname')) {
          errorType = 'DNS解析失敗';
          userFriendlyMessage = '🌐 無法連接到服務器,請檢查網絡連接或聯繫管理員';
        } else if (e.toString().contains('SocketException')) {
          errorType = 'Socket連接錯誤';
          userFriendlyMessage = '🔌 網絡連接異常，請檢查您的網絡設置';
        } else if (e.toString().contains('TimeoutException') ||
            e.toString().contains('請求超時')) {
          errorType = '請求超時';
          userFriendlyMessage = '⏱️ 服務器響應超時，請稍後重試';
        } else if (e.toString().contains('ClientException')) {
          errorType = '客戶端錯誤';
          userFriendlyMessage = '📱 應用連接錯誤，請重啟應用或檢查網絡';
        } else {
          userFriendlyMessage = '❌ 網絡請求失敗，請稍後重試';
        }

        if (attempt == _maxRetryAttempts) {
          // 最后一次尝试失败，抛出用户友好的异常
          _logger.e(
              '$apiNameForLog - 所有 $_maxRetryAttempts 次請求嘗試均失敗 (最後錯誤類型: $errorType)',
              error: e,
              stackTrace: stackTrace);

          // 抛出包含用户友好消息的异常
          throw ApiException(
            message: userFriendlyMessage,
            statusCode: null,
            errorData: e.toString(),
          );
        } else {
          // 还有重试机会，记录警告并等待
          _logger.w(
              '$apiNameForLog - 第 $attempt 次請求失敗 ($errorType)，${_retryDelay.inSeconds}秒後重試');
          await Future.delayed(_retryDelay);
        }
      }
    }

    // 如果response仍然为null，说明所有重试都失败了
    if (response == null) {
      throw lastException ?? Exception('请求失败，未知错误 - $apiNameForLog');
    }

    // Section 3: Handle 401 for the main request (retry logic)
    if (response.statusCode == 401 && !isLoginRequest) {
      _logger.w(
          'Received 401 for actual request $apiNameForLog. Attempting token refresh.');
      if (onNeedsTokenRefresh == null) {
        _logger.w(
            'onNeedsTokenRefresh is null, cannot refresh token for $apiNameForLog. Original 401 will be processed by _handleResponse.');
        return response; // Let _handleResponse deal with the 401
      }

      try {
        final newToken = await _initiateAndGetTokenRefreshFuture();
        if (newToken != null && newToken.isNotEmpty) {
          // _logger.i(
          //     'Token refreshed successfully for $apiNameForLog. Retrying original request.');
          response =
              await requestFunction(); // Retry the original request function
        } else {
          _logger.w(
              'Token refresh for $apiNameForLog did not yield a new token. Original 401 response will be processed.');
          // Let the original 401 response be returned to _handleResponse
        }
      } catch (refreshError) {
        _logger.e(
            'Error awaiting token refresh for $apiNameForLog during main request 401 handling.',
            error: refreshError);
        // Let the original 401 response be returned to _handleResponse
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
  Future<Map<String, dynamic>> getAdvertisementsBuilding() async {
    const String endpointPath = '/api/device/client/advertisements';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    // _logger.i('Fetching advertisements for building.');
    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getAdvertisementsBuilding');
    return _handleResponse(response, 'getAdvertisementsBuilding');
  }

  // 3. Get Notices for Building
  // Endpoint: GET <<baseUrl>>/api/device/client/notices
  Future<Map<String, dynamic>> getNoticesBuilding() async {
    const String endpointPath = '/api/device/client/notices';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    // _logger.i('Fetching notices for building.');
    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getNoticesBuilding');
    return _handleResponse(response, 'getNoticesBuilding');
  }

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

    // 默认设置
    final defaultSettings = {
      "arrearageUpdateDuration": 5,
      "noticeUpdateDuration": 10,
      "advertisementUpdateDuration": 15,
      "advertisementPlayDuration": 30,
      "noticePlayDuration": 30,
      "spareDuration": 10,
      "noticeStayDuration": 10,
      "normalToAnnouncementCarouselDuration": 10,
      "announcementCarouselToFullAdsCarouselDuration": 10
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

  /// 8. 获取欠费数据
  /// Endpoint: POST https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-mf-table
  /// Body: {"blg_id": "string", "ptype": "mf"}
  Future<List<Map<String, dynamic>>> getArrearage({String? buildingId}) async {
    // 验证Building ID格式
    if (buildingId != null && !_isValidBuildingId(buildingId)) {
      throw ApiException(
        statusCode: 400,
        message: 'Building ID 格式无效，只能包含数字和英文字母',
        errorData: 'Invalid building ID: $buildingId',
      );
    }

    const String fullUrl =
        'https://uqf0jqfm77.execute-api.ap-east-1.amazonaws.com/prod/v1/building_board/building-mf-table';
    final Uri url = _buildUri(fullUrl, null);
    final Map<String, dynamic> requestBodyMap = {
      'ptype': 'mf',
      if (buildingId != null) 'blg_id': buildingId,
    };
    final String requestBody = json.encode(requestBodyMap);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    _logger.i('获取欠费数据，楼宇ID: $buildingId');
    final http.Response response = await _sendRequest(
        () => http.post(url, headers: headers, body: requestBody),
        apiNameForLog: 'getArrearage');
    return _handleArrayResponse(response, 'getArrearage');
  }

  ///9, 验证Building ID格式
  bool _isValidBuildingId(String buildingId) {
    // Building ID只能包含数字和英文字母
    final RegExp validPattern = RegExp(r'^[a-zA-Z0-9]+$');
    return validPattern.hasMatch(buildingId) && buildingId.isNotEmpty;
  }

  ///10. 获取全屏广告列表
  Future<List<Map<String, dynamic>>> getFullAdvertisementsBuilding() async {
    const String endpointPath = '/api/device/client/full_advertisements';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getFullAdvertisementsBuilding');
    return _handleArrayResponse(response, 'getFullAdvertisementsBuilding');
  }

  ///11. 获取顶端广告列表
  Future<List<Map<String, dynamic>>> getTopAdvertisementsBuilding() async {
    const String endpointPath = '/api/device/client/top_advertisements';
    final Uri url = _buildUri(endpointPath, null);
    final Map<String, String> headers =
        _getHeaders(requiresAuth: true, contentType: 'application/json');

    final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers),
        apiNameForLog: 'getTopAdvertisementsBuilding');
    return _handleArrayResponse(response, 'getTopAdvertisementsBuilding');
  }

  ///12. 轮播顶端广告顺序
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

  ///13. 轮播完整广告列表
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

  ///14. 轮播通知列表
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

  ///15. 获取应用版本信息
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

  ///16. 获取香港特区政府新闻公报RSS
  /// Endpoint: GET http://www.info.gov.hk/gia/rss/general_zh.xml
  Future<List<Map<String, dynamic>>> getNewsAnnouncements() async {
    const String fullUrl = 'http://www.info.gov.hk/gia/rss/general_zh.xml';
    final Uri url = _buildUri(fullUrl, null);

    // RSS接口不需要认证，使用基本headers
    final Map<String, String> headers = {
      'Content-Type': 'application/xml; charset=utf-8',
      'User-Agent': 'iBoard_Flutter/1.0',
    };

    _logger.i('获取香港特区政府新闻公报RSS数据');

    try {
      final http.Response response = await _sendRequest(
          () => http.get(url, headers: headers),
          apiNameForLog: 'getNewsAnnouncements');

      // 处理XML响应
      return _handleRssXmlResponse(response, 'getNewsAnnouncements');
    } catch (e) {
      _logger.e('获取新闻公报失败: $e');
      rethrow;
    }
  }

  ///16.1. 获取香港电台财经新闻RSS
  /// Endpoint: GET https://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cfinance.xml
  Future<List<Map<String, dynamic>>> getRthkNews() async {
    const String fullUrl =
        'https://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cfinance.xml';
    final Uri url = _buildUri(fullUrl, null);

    // RSS接口不需要认证，使用基本headers
    final Map<String, String> headers = {
      'Content-Type': 'application/xml; charset=utf-8',
      'User-Agent': 'iBoard_Flutter/1.0',
      'Accept': 'application/xml, text/xml, */*',
      'Cache-Control': 'no-cache',
    };

    _logger.i('🌐 开始获取香港电台财经新闻RSS数据');

    try {
      // 增加超时时间到60秒
      final http.Response response = await _sendRequest(
        () => http.get(url, headers: headers).timeout(
          const Duration(seconds: 60), // 增加到60秒
          onTimeout: () {
            throw Exception('RTHK新闻RSS请求超时 (60秒)');
          },
        ),
        apiNameForLog: 'getRthkNews',
      );

      // 处理XML响应
      return _handleRssXmlResponse(response, 'getRthkNews');
    } catch (e) {
      _logger.e('❌ 获取RTHK新闻失败: $e');

      // 如果是超时错误，提供更友好的错误信息
      if (e.toString().contains('超时')) {
        throw ApiException(
          statusCode: null,
          message: '❌ RTHK新闻RSS请求超时，请检查网络连接或稍后重试',
          errorData: 'TimeoutException: ${e.toString()}',
        );
      }

      rethrow;
    }
  }

  ///17. 处理RSS XML响应
  Future<List<Map<String, dynamic>>> _handleRssXmlResponse(
      http.Response response, String apiName) async {
    final String decodedBody = utf8.decode(response.bodyBytes);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      _logger.i('$apiName 成功 (状态码: ${response.statusCode})');

      if (decodedBody.isEmpty) {
        return [];
      }

      try {
        // 简单的XML解析，提取item元素
        final List<Map<String, dynamic>> items = [];

        // 使用正则表达式提取item标签内容
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

        _logger.i('成功解析 ${items.length} 条新闻公报');
        return items;
      } catch (e, stackTrace) {
        _logger.e('解析RSS XML失败: $e', error: e, stackTrace: stackTrace);
        throw ApiException(
          statusCode: response.statusCode,
          message: '成功接收响应，但解析RSS XML失败',
          errorData: decodedBody,
        );
      }
    } else {
      _logger.w('$apiName 失败 (状态码: ${response.statusCode}), 响应体: $decodedBody');
      throw ApiException(
        statusCode: response.statusCode,
        message: '$apiName 失败',
        errorData: decodedBody,
      );
    }
  }
}
