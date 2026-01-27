class Temperature {
  final int value;
  final String unit;

  Temperature({required this.value, required this.unit});

  factory Temperature.fromJson(Map<String, dynamic> json) {
    return Temperature(
      value: json['value'] as int,
      unit: json['unit'] as String,
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
      forecastDate: json['forecastDate'] as String,
      week: json['week'] as String,
      forecastWind: json['forecastWind'] as String,
      forecastWeather: json['forecastWeather'] as String,
      forecastMaxtemp:
          Temperature.fromJson(json['forecastMaxtemp'] as Map<String, dynamic>),
      forecastMintemp:
          Temperature.fromJson(json['forecastMintemp'] as Map<String, dynamic>),
      forecastMaxrh: json['forecastMaxrh'] != null
          ? Temperature.fromJson(json['forecastMaxrh'] as Map<String, dynamic>)
          : null,
      forecastMinrh: json['forecastMinrh'] != null
          ? Temperature.fromJson(json['forecastMinrh'] as Map<String, dynamic>)
          : null,
      forecastIcon: json['ForecastIcon'] as int,
      psr: json['PSR'] as String,
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
      place: json['place'] as String,
      value: json['value'] as int,
      unit: json['unit'] as String,
      recordTime: json['recordTime'] as String,
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
      unit: json['unit'] as String,
      value: (json['value'] as num).toDouble(),
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
      place: json['place'] as String,
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String,
      recordTime: json['recordTime'] as String,
      depth: SoilTempDepth.fromJson(json['depth'] as Map<String, dynamic>),
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
    var forecastList = json['weatherForecast'] as List;
    List<WeatherForecastModel> forecasts = forecastList
        .map((i) => WeatherForecastModel.fromJson(i as Map<String, dynamic>))
        .toList();

    var soilTempList = json['soilTemp'] as List?;
    List<SoilTemp>? soilTemps;
    if (soilTempList != null) {
      soilTemps = soilTempList
          .map((i) => SoilTemp.fromJson(i as Map<String, dynamic>))
          .toList();
    }

    return WeatherData(
      generalSituation: json['generalSituation'] as String,
      weatherForecast: forecasts,
      updateTime: json['updateTime'] as String,
      seaTemp: json['seaTemp'] != null
          ? SeaTemp.fromJson(json['seaTemp'] as Map<String, dynamic>)
          : null,
      soilTemp: soilTemps,
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
