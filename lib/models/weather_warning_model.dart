class WeatherWarningModel {
  final Map<String, WeatherWarningInfo> warnings;

  WeatherWarningModel({required this.warnings});

  factory WeatherWarningModel.fromJson(Map<String, dynamic> json) {
    Map<String, WeatherWarningInfo> warnings = {};

    json.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        warnings[key] = WeatherWarningInfo.fromJson(value);
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

  // 获取当前有效的警告描述列表
  List<String> getActiveWarningDescriptions() {
    List<String> activeWarnings = [];
    warnings.forEach((code, info) {
      String description = warningDescriptions[code] ?? code;
      activeWarnings.add(description);
    });
    return activeWarnings;
  }
}

class WeatherWarningInfo {
  final String name;
  final String code;
  final String actionCode;
  final String issueTime;
  final String updateTime;

  WeatherWarningInfo({
    required this.name,
    required this.code,
    required this.actionCode,
    required this.issueTime,
    required this.updateTime,
  });

  factory WeatherWarningInfo.fromJson(Map<String, dynamic> json) {
    return WeatherWarningInfo(
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      actionCode: json['actionCode'] ?? '',
      issueTime: json['issueTime'] ?? '',
      updateTime: json['updateTime'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'actionCode': actionCode,
      'issueTime': issueTime,
      'updateTime': updateTime,
    };
  }
}
