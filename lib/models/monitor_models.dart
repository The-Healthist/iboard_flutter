// ignore_for_file: non_constant_identifier_names

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
      MonitorResponse(
        success: _boolFromJson(json['success']),
        data: MonitorData.fromJson(_mapFromJson(json['data']) ?? const {}),
      );

  factory MonitorResponse.fromJsonObject(Object? value) {
    final json = _mapFromJson(value);
    if (json == null) {
      return MonitorResponse(
        success: false,
        data: MonitorData(orangepis: const []),
      );
    }
    return MonitorResponse.fromJson(json);
  }

  Map<String, dynamic> toJson() => _$MonitorResponseToJson(this);
}

@JsonSerializable()
class MonitorData {
  final List<Orangepi> orangepis;

  MonitorData({required this.orangepis});

  factory MonitorData.fromJson(Map<String, dynamic> json) => MonitorData(
        orangepis: _listFromJson(json['orangepis'])
            .map(_mapFromJson)
            .whereType<Map<String, dynamic>>()
            .map(Orangepi.fromJson)
            .where((orangepi) => orangepi.urls.isNotEmpty)
            .toList(),
      );

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

  factory Orangepi.fromJson(Map<String, dynamic> json) => Orangepi(
        orangepi_id: _intFromJson(json['orangepi_id']),
        orangepi_name: _stringFromJson(json['orangepi_name']),
        is_active: _boolFromJson(json['is_active']),
        token: _stringFromJson(json['token']),
        urls: _stringListFromJson(json['urls']),
      );

  Map<String, dynamic> toJson() => _$OrangepiToJson(this);
}

@JsonSerializable()
class MonitorRequest {
  @JsonKey(name: 'ismartid')
  final String ismartId;
  @JsonKey(name: 'is_staff')
  final bool isStaff;

  MonitorRequest({required this.ismartId, required this.isStaff});

  factory MonitorRequest.fromJson(Map<String, dynamic> json) => MonitorRequest(
        ismartId: _stringFromJson(json['ismartid']),
        isStaff: _boolFromJson(json['is_staff']),
      );

  Map<String, dynamic> toJson() => _$MonitorRequestToJson(this);
}

Map<String, dynamic>? _mapFromJson(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

List<Object?> _listFromJson(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

String _stringFromJson(Object? value) {
  return value?.toString() ?? '';
}

int _intFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

bool _boolFromJson(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
  }
  return false;
}

List<String> _stringListFromJson(Object? value) {
  if (value is! List) return const [];
  return value
      .map(_stringFromJson)
      .where((url) => url.trim().isNotEmpty)
      .toList();
}
