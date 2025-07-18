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
    return AdModel(
      id: json['id'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
      title: json['title'] as String,
      description: json['description'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      duration: json['duration'] as int,
      priority: json['priority'] as int,
      startTime: DateTime.parse(json['startTime'] as String),
      endTime: DateTime.parse(json['endTime'] as String),
      display: _parseDisplayType(json['display'] as String),
      fileId: json['fileId'] as int,
      file: FileModel.fromJson(json['file'] as Map<String, dynamic>),
      isPublic: json['isPublic'] as bool,
    );
  }

  static AdDisplayType _parseDisplayType(String display) {
    switch (display.toLowerCase()) {
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
