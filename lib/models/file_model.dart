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
      id: json['id'] as int,
      mimeType: json['mimeType'] as String,
      md5: json['md5'] as String,
      url: json['path'] as String, // API uses 'path' for URL
      fileSize: json['size'] as int, // API uses 'size' for fileSize
      oss: json['oss'] as String?,
      uploader: json['uploader'] as String?,
      uploaderId: json['uploaderId'] as int?,
      uploaderType: json['uploaderType'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'] as String)
          : null,
      localFilePath: json['localFilePath']
          as String?, // Assuming this might still be used locally
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
