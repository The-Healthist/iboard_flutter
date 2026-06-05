import './file_model.dart';

// Enum to match existing UI, mapping from API string types
enum AnnouncementTypeUi {
  all, // New type to show all announcements
  emergency, // 緊急
  general, // 一般 (maps from API 'normal')
  government, // 政府
  corporation // 法團 (maps from API 'building')
}

class AnnouncementModel {
  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String title;
  final String description;
  final String apiType; // Raw type from API e.g., "normal", "building"
  final AnnouncementTypeUi uiType; // Mapped type for UI
  final bool isPublic;
  final bool isIsmartNotice;
  final int priority;
  final String status;
  final DateTime startTime;
  final DateTime endTime;
  final int fileId;
  final FileModel file;
  final String fileType; // e.g., "pdf"

  AnnouncementModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.title,
    required this.description,
    required this.apiType,
    required this.uiType,
    required this.isPublic,
    required this.isIsmartNotice,
    required this.priority,
    required this.status,
    required this.startTime,
    required this.endTime,
    required this.fileId,
    required this.file,
    required this.fileType,
  });

  static AnnouncementTypeUi _mapApiTypeToUiType(String? apiType) {
    switch (apiType?.toLowerCase()) {
      case 'normal':
        return AnnouncementTypeUi.general;
      case 'urgent': // Assuming API might send 'emergency'
        return AnnouncementTypeUi.emergency;
      case 'government': // Assuming API might send 'government'
        return AnnouncementTypeUi.government;
      case 'building': // API sends 'building'
        return AnnouncementTypeUi.corporation;
      default:
        return AnnouncementTypeUi.general; // Default for unknown types
    }
  }

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final apiTypeString = json['type']?.toString() ?? '';

    return AnnouncementModel(
      id: _parseInt(json['id']),
      createdAt: _parseDate(json['createdAt']) ?? now,
      updatedAt: _parseDate(json['updatedAt']) ?? now,
      deletedAt: _parseDate(json['deletedAt']),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      apiType: apiTypeString,
      uiType: _mapApiTypeToUiType(apiTypeString),
      isPublic: _parseBool(json['isPublic']),
      isIsmartNotice: _parseBool(json['isIsmartNotice']),
      priority: _parseInt(json['priority']),
      status: json['status']?.toString() ?? '',
      startTime: _parseDate(json['startTime']) ?? now,
      endTime:
          _parseDate(json['endTime']) ?? now.add(const Duration(days: 365)),
      fileId: _parseInt(json['fileId']),
      file: FileModel.fromJson(_parseMap(json['file'])),
      fileType: json['fileType']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'title': title,
      'description': description,
      'type': apiType, // Store the original API type string
      // uiType is derived, not stored back directly unless needed
      'isPublic': isPublic,
      'isIsmartNotice': isIsmartNotice,
      'priority': priority,
      'status': status,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'fileId': fileId,
      'file': file.toJson(),
      'fileType': fileType,
    };
  }
}

// Keep the old AnnouncementType if it's used elsewhere, or rename/remove if not.
// For MainScreenWidget, we will use AnnouncementTypeUi.
// enum AnnouncementType {
//   emergency, // 緊急
//   general, // 一般
//   government, // 政府
//   corporation // 法團
// }

Map<String, dynamic> _parseMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
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
