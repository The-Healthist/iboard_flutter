class Temperature {
  final int value;
  final String unit;

  Temperature({required this.value, required this.unit});

  factory Temperature.fromJson(Map<String, dynamic> json) {
    return Temperature(
      value: _parseInt(json['value']),
      unit: _parseString(json['unit']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'unit': unit,
    };
  }
}

class WeatherForecastModel {
  final String forecastDate;
  final String week;
  final String forecastWind;
  final String forecastWeather;
  final Temperature forecastMaxtemp;
  final Temperature forecastMintemp;
  final Temperature? forecastMaxrh;
  final Temperature? forecastMinrh;
  final int forecastIcon;
  final String psr;

  WeatherForecastModel({
    required this.forecastDate,
    required this.week,
    required this.forecastWind,
    required this.forecastWeather,
    required this.forecastMaxtemp,
    required this.forecastMintemp,
    this.forecastMaxrh,
    this.forecastMinrh,
    required this.forecastIcon,
    required this.psr,
  });

  factory WeatherForecastModel.fromJson(Map<String, dynamic> json) {
    return WeatherForecastModel(
      forecastDate: _parseString(json['forecastDate']),
      week: _parseString(json['week']),
      forecastWind: _parseString(json['forecastWind']),
      forecastWeather: _parseString(json['forecastWeather']),
      forecastMaxtemp: Temperature.fromJson(_parseMap(json['forecastMaxtemp'])),
      forecastMintemp: Temperature.fromJson(_parseMap(json['forecastMintemp'])),
      forecastMaxrh: json['forecastMaxrh'] != null
          ? Temperature.fromJson(_parseMap(json['forecastMaxrh']))
          : null,
      forecastMinrh: json['forecastMinrh'] != null
          ? Temperature.fromJson(_parseMap(json['forecastMinrh']))
          : null,
      forecastIcon: _parseInt(json['ForecastIcon']),
      psr: _parseString(json['PSR']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'forecastDate': forecastDate,
      'week': week,
      'forecastWind': forecastWind,
      'forecastWeather': forecastWeather,
      'forecastMaxtemp': forecastMaxtemp.toJson(),
      'forecastMintemp': forecastMintemp.toJson(),
      'forecastMaxrh': forecastMaxrh?.toJson(),
      'forecastMinrh': forecastMinrh?.toJson(),
      'ForecastIcon': forecastIcon,
      'PSR': psr,
    };
  }
}

class SeaTemp {
  final String place;
  final int value;
  final String unit;
  final String recordTime;

  SeaTemp({
    required this.place,
    required this.value,
    required this.unit,
    required this.recordTime,
  });

  factory SeaTemp.fromJson(Map<String, dynamic> json) {
    return SeaTemp(
      place: _parseString(json['place']),
      value: _parseInt(json['value']),
      unit: _parseString(json['unit']),
      recordTime: _parseString(json['recordTime']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place': place,
      'value': value,
      'unit': unit,
      'recordTime': recordTime,
    };
  }
}

class SoilTempDepth {
  final String unit;
  final double value;

  SoilTempDepth({required this.unit, required this.value});

  factory SoilTempDepth.fromJson(Map<String, dynamic> json) {
    return SoilTempDepth(
      unit: _parseString(json['unit']),
      value: _parseDouble(json['value']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'unit': unit,
      'value': value,
    };
  }
}

class SoilTemp {
  final String place;
  final double value;
  final String unit;
  final String recordTime;
  final SoilTempDepth depth;

  SoilTemp({
    required this.place,
    required this.value,
    required this.unit,
    required this.recordTime,
    required this.depth,
  });

  factory SoilTemp.fromJson(Map<String, dynamic> json) {
    return SoilTemp(
      place: _parseString(json['place']),
      value: _parseDouble(json['value']),
      unit: _parseString(json['unit']),
      recordTime: _parseString(json['recordTime']),
      depth: SoilTempDepth.fromJson(_parseMap(json['depth'])),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'place': place,
      'value': value,
      'unit': unit,
      'recordTime': recordTime,
      'depth': depth.toJson(),
    };
  }
}

class WeatherData {
  final String generalSituation;
  final List<WeatherForecastModel> weatherForecast;
  final String updateTime;
  final SeaTemp?
      seaTemp; // Made nullable as it might not always be present or needed
  final List<SoilTemp>? soilTemp; // Made nullable

  WeatherData({
    required this.generalSituation,
    required this.weatherForecast,
    required this.updateTime,
    this.seaTemp,
    this.soilTemp,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      generalSituation: _parseString(json['generalSituation']),
      weatherForecast: _parseObjectList(
          json['weatherForecast'], WeatherForecastModel.fromJson),
      updateTime: _parseString(json['updateTime']),
      seaTemp: json['seaTemp'] != null
          ? SeaTemp.fromJson(_parseMap(json['seaTemp']))
          : null,
      soilTemp: json['soilTemp'] is List
          ? _parseObjectList(json['soilTemp'], SoilTemp.fromJson)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'generalSituation': generalSituation,
      'weatherForecast': weatherForecast.map((f) => f.toJson()).toList(),
      'updateTime': updateTime,
      'seaTemp': seaTemp?.toJson(),
      'soilTemp': soilTemp?.map((s) => s.toJson()).toList(),
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

double _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value) ?? 0;
  }
  return 0;
}
