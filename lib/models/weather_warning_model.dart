class WeatherWarningModel {
  final Map<String, WeatherWarningInfo> warnings;

  WeatherWarningModel({required this.warnings});

  factory WeatherWarningModel.fromJson(Map<String, dynamic> json) {
    Map<String, WeatherWarningInfo> warnings = {};

    json.forEach((key, value) {
      final warning = _nullableMap(value);
      if (warning != null) {
        warnings[key] = WeatherWarningInfo.fromJson(warning);
      }
    });

    return WeatherWarningModel(warnings: warnings);
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> result = {};
    warnings.forEach((key, value) {
      result[key] = value.toJson();
    });
    return result;
  }

  // 获取警告描述的映射
  static const Map<String, String> warningDescriptions = {
    'WFIRE': '火災危險警告',
    'WFROST': '霜凍警告',
    'WHOT': '酷熱天氣警告',
    'WCOLD': '寒冷天氣警告',
    'WMSGNL': '強烈季候風信號',
    'WRAIN': '暴雨警告信號',
    'WFNTSA': '新界北部水浸特別報告',
    'WL': '山泥傾瀉警告',
    'WTCSGNL': '熱帶氣旋警告信號',
    'WTMW': '海嘯警告',
    'WTS': '雷暴警告',
  };

  // 获取当前有效的警告（过滤掉已取消的警告）
  Map<String, WeatherWarningInfo> getActiveWarnings() {
    Map<String, WeatherWarningInfo> activeWarnings = {};
    warnings.forEach((code, info) {
      // 只包含未取消的警告
      if (info.actionCode.toUpperCase() != 'CANCEL') {
        activeWarnings[code] = info;
      }
    });
    return activeWarnings;
  }

  // 获取所有警告描述列表（不过滤actionCode）
  List<String> getActiveWarningDescriptions() {
    List<String> allWarnings = [];
    warnings.forEach((code, info) {
      String description = warningDescriptions[code] ?? code;
      allWarnings.add(description);
    });
    return allWarnings;
  }
}

class WeatherWarningInfo {
  final String name;
  final String code;
  final String actionCode;
  final String issueTime;
  final String updateTime;
  final String? type; // 添加type字段（如黃色、紅色等）
  final String? expireTime; // 添加过期时间字段

  WeatherWarningInfo({
    required this.name,
    required this.code,
    required this.actionCode,
    required this.issueTime,
    required this.updateTime,
    this.type,
    this.expireTime,
  });

  factory WeatherWarningInfo.fromJson(Map<String, dynamic> json) {
    return WeatherWarningInfo(
      name: _parseString(json['name']),
      code: _parseString(json['code']),
      actionCode: _parseString(json['actionCode']),
      issueTime: _parseString(json['issueTime']),
      updateTime: _parseString(json['updateTime']),
      type: _parseNullableString(json['type']), // 可选字段
      expireTime: _parseNullableString(json['expireTime']), // 可选字段
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {
      'name': name,
      'code': code,
      'actionCode': actionCode,
      'issueTime': issueTime,
      'updateTime': updateTime,
    };
    if (type != null) result['type'] = type;
    if (expireTime != null) result['expireTime'] = expireTime;
    return result;
  }
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

String _parseString(Object? value) {
  return value?.toString() ?? '';
}

String? _parseNullableString(Object? value) {
  if (value == null || value == '') {
    return null;
  }
  return value.toString();
}
