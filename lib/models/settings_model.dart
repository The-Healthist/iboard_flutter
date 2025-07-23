class SettingsModel {
  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final Building building;
  final int buildingId;
  final Settings settings;
  final String status;
  final String message;
  final String token;

  SettingsModel({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.deviceId,
    required this.building,
    required this.buildingId,
    required this.settings,
    required this.status,
    required this.message,
    required this.token,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      id: json['data']['id'],
      createdAt: DateTime.parse(json['data']['createdAt']),
      updatedAt: DateTime.parse(json['data']['updatedAt']),
      deletedAt: json['data']['deletedAt'] == null
          ? null
          : DateTime.parse(json['data']['deletedAt']),
      deviceId: json['data']['deviceId'],
      building: Building.fromJson(json['data']['building']),
      buildingId: json['data']['buildingId'],
      settings: Settings.fromJson(json['data']['settings']),
      status: json['data']['status'],
      message: json['message'],
      token: json['token'],
    );
  }
}

class Building {
  final int id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String name;
  final String ismartId;
  final String remark;
  final String location;
  // Assuming devices, notices, and advertisements can be null or a list of some type.
  // For simplicity, I'm using List<dynamic>? here. You might want to create specific models for these.
  final List<dynamic>? devices;
  final List<dynamic>? notices;
  final List<dynamic>? advertisements;

  Building({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.name,
    required this.ismartId,
    required this.remark,
    required this.location,
    this.devices,
    this.notices,
    this.advertisements,
  });

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      deletedAt:
          json['deletedAt'] == null ? null : DateTime.parse(json['deletedAt']),
      name: json['name'],
      ismartId: json['ismartId'],
      remark: json['remark'],
      location: json['location'],
      devices: json['devices'],
      notices: json['notices'],
      advertisements: json['advertisements'],
    );
  }
}

class Settings {
  final int arrearageUpdateDuration; // 欠費更新時間(先不管)
  final int noticeUpdateDuration; // 通知更新時間(分鐘)
  final int advertisementUpdateDuration; // 廣告更新時間(分鐘)
  final int advertisementPlayDuration; // 全屏廣告播放時間(秒)
  final int noticePlayDuration; // 通告輪播總時間（先不管）
  final int spareDuration; // 手動操作超時時間/無操作進入全屏廣告時間(秒)
  final int noticeStayDuration; // 通知停留時間

  Settings({
    required this.arrearageUpdateDuration,
    required this.noticeUpdateDuration,
    required this.advertisementUpdateDuration,
    required this.advertisementPlayDuration,
    required this.noticePlayDuration,
    required this.spareDuration,
    required this.noticeStayDuration,
  });

  factory Settings.fromJson(Map<String, dynamic> json) {
    return Settings(
      arrearageUpdateDuration: json['arrearageUpdateDuration'],
      noticeUpdateDuration: json['noticeUpdateDuration'],
      advertisementUpdateDuration: json['advertisementUpdateDuration'],
      advertisementPlayDuration: json['advertisementPlayDuration'],
      noticePlayDuration: json['noticePlayDuration'],
      spareDuration: json['spareDuration'],
      noticeStayDuration: json['noticeStayDuration'],
    );
  }
}
