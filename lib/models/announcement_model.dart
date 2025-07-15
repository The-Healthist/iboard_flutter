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

  static AnnouncementTypeUi _mapApiTypeToUiType(String apiType) {
    switch (apiType.toLowerCase()) {
      case 'normal':
        return AnnouncementTypeUi.general;
      case 'emergency': // Assuming API might send 'emergency'
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
    final apiTypeString = json['type'] as String;
    return AnnouncementModel(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'] as String),
      title: json['title'] as String,
      description: json['description'] as String,
      apiType: apiTypeString,
      uiType: _mapApiTypeToUiType(apiTypeString),
      isPublic: json['isPublic'] as bool,
      isIsmartNotice: json['isIsmartNotice'] as bool,
      priority: json['priority'] as int,
      status: json['status'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      fileId: json['fileId'] as int,
      file: FileModel.fromJson(json['file'] as Map<String, dynamic>),
      fileType: json['fileType'] as String,
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
