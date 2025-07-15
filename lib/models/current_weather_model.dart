class LightningDataModel {
  final String place;
  final bool occur;

  LightningDataModel({required this.place, required this.occur});

  factory LightningDataModel.fromJson(Map<String, dynamic> json) {
    return LightningDataModel(
      place: json['place'] as String,
      occur: (json['occur'] as String).toLowerCase() == 'true',
    );
  }
}

class LightningInfoModel {
  final List<LightningDataModel> data;
  final String? startTime;
  final String? endTime;

  LightningInfoModel({required this.data, this.startTime, this.endTime});

  factory LightningInfoModel.fromJson(Map<String, dynamic> json) {
    var list = json['data'] as List?;
    List<LightningDataModel> dataList = list
            ?.map((i) => LightningDataModel.fromJson(i as Map<String, dynamic>))
            .toList() ??
        [];
    return LightningInfoModel(
      data: dataList,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
    );
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
      unit: json['unit'] as String,
      place: json['place'] as String,
      max: json['max'] as num,
      main: json['main'] as String,
      min: json['min'] as num?,
    );
  }
}

class RainfallInfoModel {
  final List<RainfallDataModel> data;
  final String? startTime;
  final String? endTime;

  RainfallInfoModel({required this.data, this.startTime, this.endTime});

  factory RainfallInfoModel.fromJson(Map<String, dynamic> json) {
    var list = json['data'] as List?;
    List<RainfallDataModel> dataList = list
            ?.map((i) => RainfallDataModel.fromJson(i as Map<String, dynamic>))
            .toList() ??
        [];
    return RainfallInfoModel(
      data: dataList,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
    );
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
      place: json['place'] as String,
      value: json['value'] as int,
      unit: json['unit'] as String,
    );
  }
}

class CurrentTemperatureInfoModel {
  final List<CurrentTemperatureDataModel> data;
  final String recordTime;

  CurrentTemperatureInfoModel({required this.data, required this.recordTime});

  factory CurrentTemperatureInfoModel.fromJson(Map<String, dynamic> json) {
    var list = json['data'] as List;
    List<CurrentTemperatureDataModel> dataList = list
        .map((i) =>
            CurrentTemperatureDataModel.fromJson(i as Map<String, dynamic>))
        .toList();
    return CurrentTemperatureInfoModel(
      data: dataList,
      recordTime: json['recordTime'] as String,
    );
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
      unit: json['unit'] as String,
      value: json['value'] as int,
      place: json['place'] as String,
    );
  }
}

class HumidityInfoModel {
  final String recordTime;
  final List<HumidityDataModel> data;

  HumidityInfoModel({required this.recordTime, required this.data});

  factory HumidityInfoModel.fromJson(Map<String, dynamic> json) {
    var list = json['data'] as List;
    List<HumidityDataModel> dataList = list
        .map((i) => HumidityDataModel.fromJson(i as Map<String, dynamic>))
        .toList();
    return HumidityInfoModel(
      recordTime: json['recordTime'] as String,
      data: dataList,
    );
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
  });

  factory CurrentWeatherDataModel.fromJson(Map<String, dynamic> json) {
    dynamic rawWarningMessage = json['warningMessage'];
    List<String>? parsedWarningMessage;
    if (rawWarningMessage == null) {
      parsedWarningMessage = null;
    } else if (rawWarningMessage is List) {
      parsedWarningMessage = rawWarningMessage.map((e) => e as String).toList();
    } else if (rawWarningMessage is String) {
      if (rawWarningMessage.isEmpty) {
        parsedWarningMessage = <String>[]; // Empty string becomes an empty list
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
          ? LightningInfoModel.fromJson(
              json['lightning'] as Map<String, dynamic>)
          : null,
      rainfall: json['rainfall'] != null
          ? RainfallInfoModel.fromJson(json['rainfall'] as Map<String, dynamic>)
          : null,
      warningMessage: parsedWarningMessage, // Use the safely parsed value
      icon: (json['icon'] as List<dynamic>?)?.map((e) => e as int).toList(),
      iconUpdateTime: json['iconUpdateTime'] as String?,
      updateTime: json['updateTime'] as String,
      temperature: json['temperature'] != null
          ? CurrentTemperatureInfoModel.fromJson(
              json['temperature'] as Map<String, dynamic>)
          : null,
      mintempFrom00To09: json['mintempFrom00To09'] as String?,
      rainfallFrom00To12: json['rainfallFrom00To12'] as String?,
      rainfallLastMonth: json['rainfallLastMonth'] as String?,
      rainfallJanuaryToLastMonth: json['rainfallJanuaryToLastMonth'] as String?,
      humidity: json['humidity'] != null
          ? HumidityInfoModel.fromJson(json['humidity'] as Map<String, dynamic>)
          : null,
    );
  }
}
