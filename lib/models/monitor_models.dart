import 'package:json_annotation/json_annotation.dart';

part 'monitor_models.g.dart';

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