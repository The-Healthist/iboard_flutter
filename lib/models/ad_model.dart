import './file_model.dart';

enum AdDisplayType {
  top,
  full,
  topfull,
}

class AdModel {
  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String title;
  final String description;
  final String type;
  final String status;
  final int duration;
  final int priority;
  final DateTime startTime;
  final DateTime endTime;
  final AdDisplayType display;
  final int fileId;
  final FileModel file;
  final bool isPublic;

  AdModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    required this.duration,
    required this.priority,
    required this.startTime,
    required this.endTime,
    required this.display,
    required this.fileId,
    required this.file,
    required this.isPublic,
  });

  // Helper getter for duration as Duration object
  Duration get durationObject => Duration(seconds: duration);

  factory AdModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();

    return AdModel(
      id: _parseInt(json['id']),
      createdAt: _parseDate(json['createdAt']) ?? now,
      updatedAt: _parseDate(json['updatedAt']) ?? now,
      deletedAt: _parseDate(json['deletedAt']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      duration: _parseInt(json['duration'], defaultValue: 10),
      priority: _parseInt(json['priority']),
      startTime: _parseDate(json['startTime']) ?? now,
      endTime:
          _parseDate(json['endTime']) ?? now.add(const Duration(days: 365)),
      display: _parseDisplayType(json['display']?.toString()),
      fileId: _parseInt(json['fileId']),
      file: FileModel.fromJson(_parseMap(json['file'])),
      isPublic: _parseBool(json['isPublic']),
    );
  }

  static AdDisplayType _parseDisplayType(String? display) {
    switch (display?.toLowerCase()) {
      case 'top':
        return AdDisplayType.top;
      case 'full':
        return AdDisplayType.full;
      case 'topfull':
        return AdDisplayType.topfull;
      default:
        return AdDisplayType.top; // Default value
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'title': title,
      'description': description,
      'type': type,
      'status': status,
      'duration': duration,
      'priority': priority,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'display': display.toString().split('.').last,
      'fileId': fileId,
      'file': file.toJson(),
      'isPublic': isPublic,
    };
  }
}

Map<String, dynamic> _parseMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

int _parseInt(Object? value, {int defaultValue = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? defaultValue;
  }
  return defaultValue;
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
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
    return normalized == 'true' || normalized == '1';
  }
  return false;
}
