class FileModel {
  final int id; // Added from API
  final String mimeType;
  final String md5;
  final String url;
  final int fileSize;
  final String? oss; // Added from API
  final String? uploader; // Added from API
  final int? uploaderId; // Added from API
  final String? uploaderType; // Added from API
  final DateTime? createdAt; // Added from API
  final DateTime? updatedAt; // Added from API
  final DateTime? deletedAt; // Added from API
  String? localFilePath;

  FileModel({
    required this.id,
    required this.mimeType,
    required this.md5,
    required this.url,
    required this.fileSize,
    this.oss,
    this.uploader,
    this.uploaderId,
    this.uploaderType,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.localFilePath,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      id: _parseInt(json['id']),
      mimeType: json['mimeType']?.toString() ?? '',
      md5: json['md5']?.toString() ?? '',
      url: (json['path'] ?? json['url'])?.toString() ?? '',
      fileSize: _parseInt(json['size'] ?? json['fileSize']),
      oss: json['oss']?.toString(),
      uploader: json['uploader']?.toString(),
      uploaderId: _parseNullableInt(json['uploaderId']),
      uploaderType: json['uploaderType']?.toString(),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      deletedAt: _parseDate(json['deletedAt']),
      localFilePath: json['localFilePath']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mimeType': mimeType,
      'md5': md5,
      'path': url, // Consistent with fromJson if sending back
      'size': fileSize, // Consistent with fromJson
      'oss': oss,
      'uploader': uploader,
      'uploaderId': uploaderId,
      'uploaderType': uploaderType,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'deletedAt': deletedAt?.toIso8601String(),
      'localFilePath': localFilePath,
    };
  }
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

int? _parseNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  return _parseInt(value);
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}
