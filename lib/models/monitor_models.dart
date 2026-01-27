import 'package:json_annotation/json_annotation.dart';

part 'monitor_models.g.dart';

/// 監控布局類型
enum MonitorLayoutType {
  hidden(0, '不顯示'),
  grid1(1, '1宮格'),
  grid4(4, '4宮格'),
  grid6(6, '6宮格'),
  grid8(8, '8宮格');

  final int count;
  final String label;

  const MonitorLayoutType(this.count, this.label);

  int get rows => this == hidden ? 0 : (this == grid1 ? 1 : 2);

  int get columns {
    switch (this) {
      case hidden:
        return 0;
      case grid1:
        return 1;
      case grid4:
        return 2;
      case grid6:
        return 3;
      case grid8:
        return 4;
    }
  }

  static MonitorLayoutType fromString(String value) {
    return MonitorLayoutType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MonitorLayoutType.grid4,
    );
  }
}

@JsonSerializable()
class MonitorResponse {
  final bool success;
  final MonitorData data;

  MonitorResponse({required this.success, required this.data});

  factory MonitorResponse.fromJson(Map<String, dynamic> json) =>
      _$MonitorResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MonitorResponseToJson(this);
}

@JsonSerializable()
class MonitorData {
  final List<Orangepi> orangepis;

  MonitorData({required this.orangepis});

  factory MonitorData.fromJson(Map<String, dynamic> json) =>
      _$MonitorDataFromJson(json);

  Map<String, dynamic> toJson() => _$MonitorDataToJson(this);
}

@JsonSerializable()
class Orangepi {
  final int orangepi_id;
  final String orangepi_name;
  final bool is_active;
  final String token;
  final List<String> urls;

  Orangepi({
    required this.orangepi_id,
    required this.orangepi_name,
    required this.is_active,
    required this.token,
    required this.urls,
  });

  factory Orangepi.fromJson(Map<String, dynamic> json) =>
      _$OrangepiFromJson(json);

  Map<String, dynamic> toJson() => _$OrangepiToJson(this);
}

@JsonSerializable()
class MonitorRequest {
  @JsonKey(name: 'ismartid')
  final String ismartId;
  @JsonKey(name: 'is_staff')
  final bool isStaff;

  MonitorRequest({required this.ismartId, required this.isStaff});

  factory MonitorRequest.fromJson(Map<String, dynamic> json) =>
      _$MonitorRequestFromJson(json);

  Map<String, dynamic> toJson() => _$MonitorRequestToJson(this);
}
