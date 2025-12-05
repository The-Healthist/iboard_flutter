// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'monitor_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MonitorResponse _$MonitorResponseFromJson(Map<String, dynamic> json) =>
    MonitorResponse(
      success: json['success'] as bool,
      data: MonitorData.fromJson(json['data'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$MonitorResponseToJson(MonitorResponse instance) =>
    <String, dynamic>{
      'success': instance.success,
      'data': instance.data,
    };

MonitorData _$MonitorDataFromJson(Map<String, dynamic> json) => MonitorData(
      orangepis: (json['orangepis'] as List<dynamic>)
          .map((e) => Orangepi.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$MonitorDataToJson(MonitorData instance) =>
    <String, dynamic>{
      'orangepis': instance.orangepis,
    };

Orangepi _$OrangepiFromJson(Map<String, dynamic> json) => Orangepi(
      orangepi_id: (json['orangepi_id'] as num).toInt(),
      orangepi_name: json['orangepi_name'] as String,
      is_active: json['is_active'] as bool,
      token: json['token'] as String,
      urls: (json['urls'] as List<dynamic>).map((e) => e as String).toList(),
    );

Map<String, dynamic> _$OrangepiToJson(Orangepi instance) => <String, dynamic>{
      'orangepi_id': instance.orangepi_id,
      'orangepi_name': instance.orangepi_name,
      'is_active': instance.is_active,
      'token': instance.token,
      'urls': instance.urls,
    };

MonitorRequest _$MonitorRequestFromJson(Map<String, dynamic> json) =>
    MonitorRequest(
      ismartId: json['ismartid'] as String,
      isStaff: json['is_staff'] as bool,
    );

Map<String, dynamic> _$MonitorRequestToJson(MonitorRequest instance) =>
    <String, dynamic>{
      'ismartid': instance.ismartId,
      'is_staff': instance.isStaff,
    };
