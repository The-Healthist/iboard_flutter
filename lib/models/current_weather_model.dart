class LightningDataModel {
  final String place;
  final bool occur;

  LightningDataModel({required this.place, required this.occur});

  factory LightningDataModel.fromJson(Map<String, dynamic> json) {
    return LightningDataModel(
      place: _parseString(json['place']),
      occur: _parseBool(json['occur']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place': place,
      'occur': occur.toString(),
    };
  }
}

class LightningInfoModel {
  final List<LightningDataModel> data;
  final String? startTime;
  final String? endTime;

  LightningInfoModel({required this.data, this.startTime, this.endTime});

  factory LightningInfoModel.fromJson(Map<String, dynamic> json) {
    return LightningInfoModel(
      data: _parseObjectList(json['data'], LightningDataModel.fromJson),
      startTime: _parseNullableString(json['startTime']),
      endTime: _parseNullableString(json['endTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.map((d) => d.toJson()).toList(),
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

class RainfallDataModel {
  final String unit;
  final String place;
  final num max; // API sends 0, not 0.0 for some reason, num handles int/double
  final String main;
  final num? min;

  RainfallDataModel({
    required this.unit,
    required this.place,
    required this.max,
    required this.main,
    this.min,
  });

  factory RainfallDataModel.fromJson(Map<String, dynamic> json) {
    return RainfallDataModel(
      unit: _parseString(json['unit']),
      place: _parseString(json['place']),
      max: _parseNum(json['max']),
      main: _parseString(json['main']),
      min: _parseNullableNum(json['min']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'unit': unit,
      'place': place,
      'max': max,
      'main': main,
      'min': min,
    };
  }
}

class RainfallInfoModel {
  final List<RainfallDataModel> data;
  final String? startTime;
  final String? endTime;

  RainfallInfoModel({required this.data, this.startTime, this.endTime});

  factory RainfallInfoModel.fromJson(Map<String, dynamic> json) {
    return RainfallInfoModel(
      data: _parseObjectList(json['data'], RainfallDataModel.fromJson),
      startTime: _parseNullableString(json['startTime']),
      endTime: _parseNullableString(json['endTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.map((d) => d.toJson()).toList(),
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

class CurrentTemperatureDataModel {
  final String place;
  final int value;
  final String unit;

  CurrentTemperatureDataModel(
      {required this.place, required this.value, required this.unit});

  factory CurrentTemperatureDataModel.fromJson(Map<String, dynamic> json) {
    return CurrentTemperatureDataModel(
      place: _parseString(json['place']),
      value: _parseInt(json['value']),
      unit: _parseString(json['unit']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place': place,
      'value': value,
      'unit': unit,
    };
  }
}

class CurrentTemperatureInfoModel {
  final List<CurrentTemperatureDataModel> data;
  final String recordTime;

  CurrentTemperatureInfoModel({required this.data, required this.recordTime});

  factory CurrentTemperatureInfoModel.fromJson(Map<String, dynamic> json) {
    return CurrentTemperatureInfoModel(
      data:
          _parseObjectList(json['data'], CurrentTemperatureDataModel.fromJson),
      recordTime: _parseString(json['recordTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.map((d) => d.toJson()).toList(),
      'recordTime': recordTime,
    };
  }
}

class HumidityDataModel {
  final String unit;
  final int value;
  final String place;

  HumidityDataModel(
      {required this.unit, required this.value, required this.place});

  factory HumidityDataModel.fromJson(Map<String, dynamic> json) {
    return HumidityDataModel(
      unit: _parseString(json['unit']),
      value: _parseInt(json['value']),
      place: _parseString(json['place']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'unit': unit,
      'value': value,
      'place': place,
    };
  }
}

class HumidityInfoModel {
  final String recordTime;
  final List<HumidityDataModel> data;

  HumidityInfoModel({required this.recordTime, required this.data});

  factory HumidityInfoModel.fromJson(Map<String, dynamic> json) {
    return HumidityInfoModel(
      recordTime: _parseString(json['recordTime']),
      data: _parseObjectList(json['data'], HumidityDataModel.fromJson),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'recordTime': recordTime,
      'data': data.map((d) => d.toJson()).toList(),
    };
  }
}

class UvIndexDataModel {
  final String place;
  final double value;
  final String desc;

  UvIndexDataModel({
    required this.place,
    required this.value,
    required this.desc,
  });

  ///1, 从JSON数据创建UvIndexDataModel实例，支持double和int类型的value
  factory UvIndexDataModel.fromJson(Map<String, dynamic> json) {
    return UvIndexDataModel(
      place: _parseString(json['place']),
      value: _parseNum(json['value']).toDouble(),
      desc: _parseString(json['desc']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place': place,
      'value': value,
      'desc': desc,
    };
  }
}

class UvIndexInfoModel {
  final List<UvIndexDataModel> data;
  final String recordDesc;

  UvIndexInfoModel({
    required this.data,
    required this.recordDesc,
  });

  factory UvIndexInfoModel.fromJson(Map<String, dynamic> json) {
    return UvIndexInfoModel(
      data: _parseObjectList(json['data'], UvIndexDataModel.fromJson),
      recordDesc: _parseString(json['recordDesc']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data.map((d) => d.toJson()).toList(),
      'recordDesc': recordDesc,
    };
  }
}

class CurrentWeatherDataModel {
  final LightningInfoModel? lightning;
  final RainfallInfoModel? rainfall;
  final List<String>? warningMessage;
  final List<int>? icon;
  final String? iconUpdateTime;
  final String updateTime;
  final CurrentTemperatureInfoModel? temperature;
  final List<String>? tcmessage; // Note: API shows "tcmessage", not "tcMessage"
  final String? mintempFrom00To09;
  final String? rainfallFrom00To12;
  final String? rainfallLastMonth;
  final String? rainfallJanuaryToLastMonth;
  final HumidityInfoModel? humidity;
  final UvIndexInfoModel? uvindex;

  CurrentWeatherDataModel({
    this.lightning,
    this.rainfall,
    this.warningMessage,
    this.icon,
    this.iconUpdateTime,
    required this.updateTime,
    this.temperature,
    this.tcmessage,
    this.mintempFrom00To09,
    this.rainfallFrom00To12,
    this.rainfallLastMonth,
    this.rainfallJanuaryToLastMonth,
    this.humidity,
    this.uvindex,
  });

  ///1，解析tcmessage字段 - 处理空字符串和List类型
  static List<String>? _parseTcMessage(dynamic value) {
    if (value == null || value == "") {
      return null;
    }
    if (value is List) {
      return _parseStringList(value);
    }
    if (value is String && value.isNotEmpty) {
      return [value];
    }
    return null;
  }

  ///2，解析空字符串字段 - 将空字符串转换为null
  static String? _parseEmptyString(dynamic value) {
    if (value == null || value == "") {
      return null;
    }
    return value.toString();
  }

  factory CurrentWeatherDataModel.fromJson(Map<String, dynamic> json) {
    dynamic rawWarningMessage = json['warningMessage'];
    List<String>? parsedWarningMessage;
    if (rawWarningMessage == null || rawWarningMessage == "") {
      parsedWarningMessage = null;
    } else if (rawWarningMessage is List) {
      parsedWarningMessage = _parseStringList(rawWarningMessage);
    } else if (rawWarningMessage is String) {
      if (rawWarningMessage.trim().isEmpty) {
        parsedWarningMessage = null;
      } else {
        // If a non-empty string could be a single warning message
        parsedWarningMessage = <String>[rawWarningMessage];
      }
    } else {
      // If it's some other unexpected type, treat as null or empty list
      parsedWarningMessage = null;
    }

    return CurrentWeatherDataModel(
      lightning: json['lightning'] != null
          ? LightningInfoModel.fromJson(_parseMap(json['lightning']))
          : null,
      rainfall: json['rainfall'] != null
          ? RainfallInfoModel.fromJson(_parseMap(json['rainfall']))
          : null,
      warningMessage: parsedWarningMessage, // Use the safely parsed value
      icon: _parseIntList(json['icon']),
      iconUpdateTime: _parseEmptyString(json['iconUpdateTime']),
      updateTime: _parseString(json['updateTime']),
      temperature: json['temperature'] != null
          ? CurrentTemperatureInfoModel.fromJson(_parseMap(json['temperature']))
          : null,
      tcmessage: _parseTcMessage(json['tcmessage']),
      mintempFrom00To09: _parseEmptyString(json['mintempFrom00To09']),
      rainfallFrom00To12: _parseEmptyString(json['rainfallFrom00To12']),
      rainfallLastMonth: _parseEmptyString(json['rainfallLastMonth']),
      rainfallJanuaryToLastMonth:
          _parseEmptyString(json['rainfallJanuaryToLastMonth']),
      humidity: json['humidity'] != null
          ? HumidityInfoModel.fromJson(_parseMap(json['humidity']))
          : null,
      uvindex: json['uvindex'] != null && json['uvindex'] != ""
          ? UvIndexInfoModel.fromJson(_parseMap(json['uvindex']))
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lightning': lightning?.toJson(),
      'rainfall': rainfall?.toJson(),
      'warningMessage': warningMessage,
      'icon': icon,
      'iconUpdateTime': iconUpdateTime,
      'updateTime': updateTime,
      'temperature': temperature?.toJson(),
      'tcmessage': tcmessage,
      'mintempFrom00To09': mintempFrom00To09,
      'rainfallFrom00To12': rainfallFrom00To12,
      'rainfallLastMonth': rainfallLastMonth,
      'rainfallJanuaryToLastMonth': rainfallJanuaryToLastMonth,
      'humidity': humidity?.toJson(),
      'uvindex': uvindex?.toJson(),
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

String _parseString(Object? value) {
  return value?.toString() ?? '';
}

String? _parseNullableString(Object? value) {
  if (value == null || value == '') {
    return null;
  }
  return value.toString();
}

int _parseInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

num _parseNum(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value) ?? 0;
  }
  return 0;
}

num? _parseNullableNum(Object? value) {
  if (value == null || value == '') {
    return null;
  }
  return _parseNum(value);
}

bool _parseBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

List<String>? _parseStringList(Object? value) {
  if (value is! List) {
    return null;
  }
  return value
      .map((item) => item?.toString() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

List<int>? _parseIntList(Object? value) {
  if (value is! List) {
    return null;
  }
  return value.map(_parseInt).toList();
}
