import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/models/file_model.dart';

///實時監控虛擬廣告Model - 用於集成到頂部廣告輪播系統
class LiveMonitorAdModel extends AdModel {
  LiveMonitorAdModel()
      : super(
          id: -1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          deletedAt: null,
          title: '實時監控',
          description: '四路監控畫面',
          type: 'live_monitor',
          status: 'active',
          duration: 60,
          priority: 999,
          startTime: DateTime(2000),
          endTime: DateTime(2099),
          display: AdDisplayType.top,
          fileId: -1,
          file: FileModel(
            id: -1,
            mimeType: 'application/live-monitor',
            md5: 'live_monitor_internal',
            url: 'live_monitor://internal',
            fileSize: 0,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            deletedAt: null,
            localFilePath: null,
          ),
          isPublic: true,
        );

  ///判斷是否為實時監控
  static bool isLiveMonitor(AdModel ad) {
    return ad.type == 'live_monitor' || ad.id == -1;
  }
}
