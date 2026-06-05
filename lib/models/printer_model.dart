/// 1, 打印機狀態枚舉
enum PrinterState {
  idle, // 空閒
  processing, // 處理中
  stopped, // 已停止
  offline, // 離線
  unknown, // 未知
}

/// 2, 打印機協議類型
enum PrinterProtocol {
  ipp, // IPP協議
  ipps, // IPPS安全協議
  appSocket, // AppSocket協議
}

/// 3, 打印機驅動模型
enum PrinterModel {
  everywhere, // IPP Everywhere (推薦)
  raw, // Raw驅動
  generic, // 通用驅動
}

/// 4, 打印機基本信息模型
class PrinterInfo {
  final int id;
  final String name;
  final String displayName;
  final String state;
  final bool acceptingJobs;
  final String uri;
  final String ipAddress;
  final String? location;
  final String? description;
  final bool enabled;
  final String type;
  final DateTime? createdAt;
  final String? status;
  final String? reason;

  const PrinterInfo({
    required this.id,
    required this.name,
    required this.displayName,
    required this.state,
    required this.acceptingJobs,
    required this.uri,
    required this.ipAddress,
    this.location,
    this.description,
    required this.enabled,
    required this.type,
    this.createdAt,
    this.status,
    this.reason,
  });

  factory PrinterInfo.fromJson(Map<String, dynamic> json) {
    return PrinterInfo(
      id: _parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      state: json['state']?.toString() ?? 'unknown',
      acceptingJobs: _parseBool(json['accepting_jobs']),
      uri: json['uri']?.toString() ?? '',
      ipAddress: json['ip_address']?.toString() ?? '',
      location: json['location']?.toString(),
      description: json['description']?.toString(),
      enabled: _parseBool(json['enabled'], defaultValue: true),
      type: json['type']?.toString() ?? 'network',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      status: json['status']?.toString(),
      reason: json['reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'display_name': displayName,
      'state': state,
      'accepting_jobs': acceptingJobs,
      'uri': uri,
      'ip_address': ipAddress,
      if (location != null) 'location': location,
      if (description != null) 'description': description,
      'enabled': enabled,
      'type': type,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (status != null) 'status': status,
      if (reason != null) 'reason': reason,
    };
  }

  PrinterInfo copyWith({
    int? id,
    String? name,
    String? displayName,
    String? state,
    bool? acceptingJobs,
    String? uri,
    String? ipAddress,
    String? location,
    String? description,
    bool? enabled,
    String? type,
    DateTime? createdAt,
    String? status,
    String? reason,
  }) {
    return PrinterInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      state: state ?? this.state,
      acceptingJobs: acceptingJobs ?? this.acceptingJobs,
      uri: uri ?? this.uri,
      ipAddress: ipAddress ?? this.ipAddress,
      location: location ?? this.location,
      description: description ?? this.description,
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      reason: reason ?? this.reason,
    );
  }

  PrinterState get printerState {
    switch (state.toLowerCase()) {
      case 'idle':
        return PrinterState.idle;
      case 'processing':
        return PrinterState.processing;
      case 'stopped':
        return PrinterState.stopped;
      case 'offline':
        return PrinterState.offline;
      default:
        return PrinterState.unknown;
    }
  }

  bool get isOnline => enabled && acceptingJobs && state == 'idle';

  /// 獲取實際狀態(優先使用 status 字段)
  String get actualStatus => status ?? (isOnline ? 'online' : 'offline');

  /// 是否有實際狀態記錄
  bool get hasActualStatus => status != null;
}

/// 5, 打印機詳細信息模型
class PrinterDetails {
  final int id;
  final String name;
  final String displayName;
  final String? description;
  final String? location;
  final String? makeAndModel;
  final String state;
  final int stateCode;
  final bool acceptingJobs;
  final String uri;
  final String ipAddress;
  final bool enabled;
  final PrinterStatus status;
  final DateTime? createdAt;
  final String type;

  const PrinterDetails({
    required this.id,
    required this.name,
    required this.displayName,
    this.description,
    this.location,
    this.makeAndModel,
    required this.state,
    required this.stateCode,
    required this.acceptingJobs,
    required this.uri,
    required this.ipAddress,
    required this.enabled,
    required this.status,
    this.createdAt,
    required this.type,
  });

  factory PrinterDetails.fromJson(Map<String, dynamic> json) {
    return PrinterDetails(
      id: _parseInt(json['id']),
      name: json['name']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      description: json['description']?.toString(),
      location: json['location']?.toString(),
      makeAndModel: json['make_and_model']?.toString(),
      state: json['state']?.toString() ?? 'unknown',
      stateCode: _parseInt(json['state_code']),
      acceptingJobs: _parseBool(json['accepting_jobs']),
      uri: json['uri']?.toString() ?? '',
      ipAddress: json['ip_address']?.toString() ?? '',
      enabled: _parseBool(json['enabled'], defaultValue: true),
      status: _nullableMap(json['status']) != null
          ? PrinterStatus.fromJson(_parseMap(json['status']))
          : PrinterStatus.defaultStatus(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : null,
      type: json['type']?.toString() ?? 'network',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'display_name': displayName,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      if (makeAndModel != null) 'make_and_model': makeAndModel,
      'state': state,
      'state_code': stateCode,
      'accepting_jobs': acceptingJobs,
      'uri': uri,
      'ip_address': ipAddress,
      'enabled': enabled,
      'status': status.toJson(),
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      'type': type,
    };
  }
}

/// 6, 打印機狀態模型
class PrinterStatus {
  final bool connected;
  final String status;
  final bool isOnline;
  final bool acceptingJobs;
  final String message;

  const PrinterStatus({
    required this.connected,
    required this.status,
    required this.isOnline,
    required this.acceptingJobs,
    required this.message,
  });

  factory PrinterStatus.fromJson(Map<String, dynamic> json) {
    return PrinterStatus(
      connected: _parseBool(json['connected']),
      status: json['status']?.toString() ?? 'unknown',
      isOnline: _parseBool(json['is_online']),
      acceptingJobs: _parseBool(json['accepting_jobs']),
      message: json['message']?.toString() ?? '',
    );
  }

  factory PrinterStatus.defaultStatus() {
    return const PrinterStatus(
      connected: false,
      status: 'unknown',
      isOnline: false,
      acceptingJobs: false,
      message: ' 打印機狀態未知',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'connected': connected,
      'status': status,
      'is_online': isOnline,
      'accepting_jobs': acceptingJobs,
      'message': message,
    };
  }
}

/// 7, 打印機選項配置模型
class PrinterOptions {
  final String printerName;
  final Map<String, String> options;
  final String? rawOutput;
  final DateTime? queryTime;
  final String method;

  const PrinterOptions({
    required this.printerName,
    required this.options,
    this.rawOutput,
    this.queryTime,
    required this.method,
  });

  factory PrinterOptions.fromJson(Map<String, dynamic> json) {
    return PrinterOptions(
      printerName: json['printer_name']?.toString() ?? '',
      options: _parseStringMap(json['options']),
      rawOutput: json['raw_output']?.toString(),
      queryTime: json['query_time'] != null
          ? DateTime.tryParse(json['query_time'].toString())
          : null,
      method: json['method']?.toString() ?? 'lpoptions',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'printer_name': printerName,
      'options': options,
      if (rawOutput != null) 'raw_output': rawOutput,
      if (queryTime != null) 'query_time': queryTime!.toIso8601String(),
      'method': method,
    };
  }

  String? getOption(String key) => options[key];

  String? get printerInfo => options['printer-info'];
  String? get makeAndModel => options['printer-make-and-model'];
  String? get markerLevels => options['marker-levels'];
  String? get markerNames => options['marker-names'];
  String? get colorMode => options['print-color-mode'];
  String? get printerState => options['printer-state'];
  String? get stateReasons => options['printer-state-reasons'];
  String? get deviceUri => options['device-uri'];
}

/// 8, 打印設置模型
class PrintSettings {
  final int copies;
  final String colorMode;
  final String media;
  final bool duplex;
  final String? duplexType;
  final String quality;
  final String orientation;
  final String? pageRange;
  final int numberUp;
  final int priority;
  final String? holdJob;
  final String? banner;

  const PrintSettings({
    this.copies = 1,
    this.colorMode = 'color',
    this.media = 'a4',
    this.duplex = false,
    this.duplexType,
    this.quality = 'normal',
    this.orientation = 'portrait',
    this.pageRange,
    this.numberUp = 1,
    this.priority = 50,
    this.holdJob,
    this.banner,
  });

  factory PrintSettings.fromJson(Map<String, dynamic> json) {
    return PrintSettings(
      copies: _parseInt(json['copies'], defaultValue: 1),
      colorMode: json['color_mode']?.toString() ?? 'color',
      media: json['media']?.toString() ?? 'a4',
      duplex: _parseBool(json['duplex']),
      duplexType: json['duplex_type']?.toString(),
      quality: json['quality']?.toString() ?? 'normal',
      orientation: json['orientation']?.toString() ?? 'portrait',
      pageRange: json['page_range']?.toString(),
      numberUp: _parseInt(json['number_up'], defaultValue: 1),
      priority: _parseInt(json['priority'], defaultValue: 50),
      holdJob: json['hold_job']?.toString(),
      banner: json['banner']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'copies': copies,
      'color_mode': colorMode,
      'media': media,
      'duplex': duplex,
      if (duplexType != null) 'duplex_type': duplexType,
      'quality': quality,
      'orientation': orientation,
      if (pageRange != null) 'page_range': pageRange,
      'number_up': numberUp,
      'priority': priority,
      if (holdJob != null) 'hold_job': holdJob,
      if (banner != null) 'banner': banner,
    };
  }

  PrintSettings copyWith({
    int? copies,
    String? colorMode,
    String? media,
    bool? duplex,
    String? duplexType,
    String? quality,
    String? orientation,
    String? pageRange,
    int? numberUp,
    int? priority,
    String? holdJob,
    String? banner,
  }) {
    return PrintSettings(
      copies: copies ?? this.copies,
      colorMode: colorMode ?? this.colorMode,
      media: media ?? this.media,
      duplex: duplex ?? this.duplex,
      duplexType: duplexType ?? this.duplexType,
      quality: quality ?? this.quality,
      orientation: orientation ?? this.orientation,
      pageRange: pageRange ?? this.pageRange,
      numberUp: numberUp ?? this.numberUp,
      priority: priority ?? this.priority,
      holdJob: holdJob ?? this.holdJob,
      banner: banner ?? this.banner,
    );
  }
}

/// 9, 打印作業響應模型
class PrintJobResponse {
  final bool success;
  final int? jobId;
  final int? cupsJobId;
  final String message;
  final String? printerIp;
  final String? printerName;
  final String? method;
  final String? driver;
  final FileInfo? fileInfo;

  const PrintJobResponse({
    required this.success,
    this.jobId,
    this.cupsJobId,
    required this.message,
    this.printerIp,
    this.printerName,
    this.method,
    this.driver,
    this.fileInfo,
  });

  factory PrintJobResponse.fromJson(Map<String, dynamic> json) {
    return PrintJobResponse(
      success: _parseBool(json['success']),
      jobId: _parseNullableInt(json['job_id']),
      cupsJobId: _parseNullableInt(json['cups_job_id']),
      message: json['message']?.toString() ?? '',
      printerIp: json['printer_ip']?.toString(),
      printerName: json['printer_name']?.toString(),
      method: json['method']?.toString(),
      driver: json['driver']?.toString(),
      fileInfo: _nullableMap(json['file_info']) != null
          ? FileInfo.fromJson(_parseMap(json['file_info']))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      if (jobId != null) 'job_id': jobId,
      if (cupsJobId != null) 'cups_job_id': cupsJobId,
      'message': message,
      if (printerIp != null) 'printer_ip': printerIp,
      if (printerName != null) 'printer_name': printerName,
      if (method != null) 'method': method,
      if (driver != null) 'driver': driver,
      if (fileInfo != null) 'file_info': fileInfo!.toJson(),
    };
  }
}

/// 10, 文件信息模型
class FileInfo {
  final String filename;
  final double sizeKb;
  final String format;

  const FileInfo({
    required this.filename,
    required this.sizeKb,
    required this.format,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      filename: json['filename']?.toString() ?? '',
      sizeKb: _parseDouble(json['size_kb']),
      format: json['format']?.toString() ?? 'PDF',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'size_kb': sizeKb,
      'format': format,
    };
  }
}

/// 11, 打印機連接請求模型
class ConnectPrinterRequest {
  final String printerIp;
  final String? name;
  final String? description;
  final String? location;
  final String protocol;
  final int port;
  final String model;
  final bool testConnection;

  const ConnectPrinterRequest({
    required this.printerIp,
    this.name,
    this.description,
    this.location,
    this.protocol = 'ipp',
    this.port = 631,
    this.model = 'everywhere',
    this.testConnection = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'printer_ip': printerIp,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (location != null) 'location': location,
      'protocol': protocol,
      'port': port,
      'model': model,
      'test_connection': testConnection,
    };
  }
}

/// 12, 打印請求模型
class PrintRequest {
  final String fileData; // Base64編碼的PDF數據
  final String filename;
  final String title;
  final PrintSettings options;

  const PrintRequest({
    required this.fileData,
    required this.filename,
    required this.title,
    required this.options,
  });

  Map<String, dynamic> toJson() {
    return {
      'file_data': fileData,
      'filename': filename,
      'title': title,
      'options': options.toJson(),
    };
  }
}

/// 13, 打印機列表響應模型
class PrintersListResponse {
  final bool success;
  final List<PrinterInfo> printers;
  final int count;

  const PrintersListResponse({
    required this.success,
    required this.printers,
    required this.count,
  });

  factory PrintersListResponse.fromJson(Map<String, dynamic> json) {
    final printersList =
        _parseObjectList(json['printers'], PrinterInfo.fromJson);

    return PrintersListResponse(
      success: _parseBool(json['success']),
      printers: printersList,
      count: _parseInt(json['count'], defaultValue: printersList.length),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'printers': printers.map((p) => p.toJson()).toList(),
      'count': count,
    };
  }
}

/// 14, 健康檢查響應模型
class HealthCheckResponse {
  final String status;
  final DateTime timestamp;
  final String service;

  const HealthCheckResponse({
    required this.status,
    required this.timestamp,
    required this.service,
  });

  factory HealthCheckResponse.fromJson(Map<String, dynamic> json) {
    return HealthCheckResponse(
      status: json['status']?.toString() ?? 'unknown',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      service: json['service']?.toString() ?? 'WiFi Print Service API',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'timestamp': timestamp.toIso8601String(),
      'service': service,
    };
  }

  bool get isHealthy => status.toLowerCase() == 'healthy';
}

/// 15, 測試連接響應模型
class TestConnectionResponse {
  final bool success;
  final bool connected;
  final String? printerIp;
  final Map<String, bool>? protocols;
  final String? recommendedUri;
  final String message;
  final String? errorCode;

  const TestConnectionResponse({
    required this.success,
    required this.connected,
    this.printerIp,
    this.protocols,
    this.recommendedUri,
    required this.message,
    this.errorCode,
  });

  factory TestConnectionResponse.fromJson(Map<String, dynamic> json) {
    return TestConnectionResponse(
      success: _parseBool(json['success']),
      connected: _parseBool(json['connected']),
      printerIp: json['printer_ip']?.toString(),
      protocols: _parseBoolMap(json['protocols']),
      recommendedUri: json['recommended_uri']?.toString(),
      message: json['message']?.toString() ?? '',
      errorCode: json['error_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'connected': connected,
      if (printerIp != null) 'printer_ip': printerIp,
      if (protocols != null) 'protocols': protocols,
      if (recommendedUri != null) 'recommended_uri': recommendedUri,
      'message': message,
      if (errorCode != null) 'error_code': errorCode,
    };
  }
}

List<T> _parseObjectList<T>(
  Object? value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! List) {
    return [];
  }

  final items = <T>[];
  for (final item in value) {
    final map = _nullableMap(item);
    if (map != null) {
      items.add(fromJson(map));
    }
  }
  return items;
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

Map<String, String> _parseStringMap(Object? value) {
  final map = _nullableMap(value);
  if (map == null) {
    return {};
  }
  return map.map((key, value) => MapEntry(key, value.toString()));
}

Map<String, bool>? _parseBoolMap(Object? value) {
  final map = _nullableMap(value);
  if (map == null) {
    return null;
  }
  return map.map((key, value) => MapEntry(key, _parseBool(value)));
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

int? _parseNullableInt(Object? value) {
  if (value == null || value == '') {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

double _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0.0;
  }
  return 0.0;
}

bool _parseBool(Object? value, {bool defaultValue = false}) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
  }
  return defaultValue;
}
