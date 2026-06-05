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
      id: json['data']?['id'] ?? 0,
      createdAt: DateTime.parse(
          json['data']?['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(
          json['data']?['updatedAt'] ?? DateTime.now().toIso8601String()),
      deletedAt: json['data']?['deletedAt'] == null
          ? null
          : DateTime.parse(json['data']['deletedAt']),
      deviceId: json['data']?['deviceId'] ?? '',
      building: Building.fromJson(json['data']?['building'] ?? {}),
      buildingId: json['data']?['buildingId'] ?? 0,
      settings: Settings.fromJson(json['data']?['settings'] ?? {}),
      status: json['data']?['status'] ?? '',
      message: json['message'] ?? '',
      token: json['token'] ?? '',
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
      id: json['id'] ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
      deletedAt:
          json['deletedAt'] == null ? null : DateTime.parse(json['deletedAt']),
      name: json['name'] ?? '',
      ismartId: json['ismartId'] ?? '',
      remark: json['remark'] ?? '',
      location: json['location'] ?? '',
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
  final int appUpdateDuration; // 應用更新時間(分鐘)
  final int advertisementPlayDuration; // 全屏廣告播放時間(秒)
  final int noticeStayDuration; // 通知停留時間
  final int bottomCarouselDuration; // 底部輪播時間(秒)
  final int paymentTableOnePageDuration; // 付款表格一頁顯示時間(秒)
  final int normalToAnnouncementCarouselDuration; // 正常到通告輪播轉換時間(秒)
  final int announcementCarouselToFullAdsCarouselDuration; // 通告輪播到全屏廣告輪播轉換時間(秒)
  final String printPassWord; // 打印密碼
  final String orangePiIp; // 香橙派IP地址(打印服務)

  Settings({
    required this.arrearageUpdateDuration,
    required this.noticeUpdateDuration,
    required this.advertisementUpdateDuration,
    required this.appUpdateDuration,
    required this.advertisementPlayDuration,
    required this.noticeStayDuration,
    required this.bottomCarouselDuration,
    required this.paymentTableOnePageDuration,
    required this.normalToAnnouncementCarouselDuration,
    required this.announcementCarouselToFullAdsCarouselDuration,
    required this.printPassWord,
    this.orangePiIp = '', // 香橙派IP地址,需在設置中配置
  });

  factory Settings.fromJson(Map<String, dynamic> json) {
    // 支持多種可能的字段名格式
    final printPassword = json['printPassWord'] ??
        json['printPassword'] ??
        json['print_password'] ??
        json['print_pass_word'] ??
        '1090119';

    return Settings(
      arrearageUpdateDuration:
          _readPositiveInt(json['arrearageUpdateDuration'], 30),
      noticeUpdateDuration: _readPositiveInt(json['noticeUpdateDuration'], 5),
      advertisementUpdateDuration:
          _readPositiveInt(json['advertisementUpdateDuration'], 10),
      appUpdateDuration: _readPositiveInt(json['appUpdateDuration'], 60),
      advertisementPlayDuration:
          _readPositiveInt(json['advertisementPlayDuration'], 10),
      noticeStayDuration: _readPositiveInt(json['noticeStayDuration'], 5),
      bottomCarouselDuration:
          _readPositiveInt(json['bottomCarouselDuration'], 10),
      paymentTableOnePageDuration:
          _readPositiveInt(json['paymentTableOnePageDuration'], 10),
      normalToAnnouncementCarouselDuration:
          _readPositiveInt(json['normalToAnnouncementCarouselDuration'], 5),
      announcementCarouselToFullAdsCarouselDuration: _readPositiveInt(
          json['announcementCarouselToFullAdsCarouselDuration'], 5),
      printPassWord: printPassword.toString(),
      orangePiIp: json['orangePiIp']?.toString().trim() ?? '',
    );
  }

  static int _readPositiveInt(dynamic value, int fallback) {
    final parsed = switch (value) {
      int v => v,
      double v => v.toInt(),
      String v => int.tryParse(v.trim()),
      _ => null,
    };

    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }
}
