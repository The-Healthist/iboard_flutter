import './file_model.dart';

enum AdDisplayType {
  top,
  full,
  topfull,
}

class AdModel {
  final String title;
  final String description;
  final Duration duration;
  final AdDisplayType display;
  final FileModel file;

  AdModel({
    required this.title,
    required this.description,
    required this.duration,
    required this.display,
    required this.file,
  });

  factory AdModel.fromJson(Map<String, dynamic> json) {
    return AdModel(
      title: json['title'] as String,
      description: json['description'] as String,
      duration: Duration(seconds: json['duration'] as int),
      display: AdDisplayType.values.firstWhere(
        (e) => e.toString() == 'AdDisplayType.${json['display']}',
        orElse: () => AdDisplayType.top, // Default value
      ),
      file: FileModel.fromJson(json['file'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'duration': duration.inSeconds,
      'display': display.toString().split('.').last, // Store enum as string
      'file': file.toJson(),
    };
  }
}
