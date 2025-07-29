import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/providers/top_ad_carousel_provider.dart';
import 'package:iboard_app/widgets/carousel_widget.dart';
import 'package:provider/provider.dart';
import 'package:iboard_app/utils/debug_cache_util.dart';

class CarouselSettingsPage extends StatefulWidget {
  const CarouselSettingsPage({Key? key}) : super(key: key);

  @override
  _CarouselSettingsPageState createState() => _CarouselSettingsPageState();
}

class _CarouselSettingsPageState extends State<CarouselSettingsPage> {
  ///1，恢复所有轮播和计时器
  void _resumeAllCarouselsFromSettings() {
    // 强制发送媒体恢复通知，确保所有视频都恢复播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        MediaResumeNotification().dispatch(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 在返回前恢复所有轮播
        _resumeAllCarouselsFromSettings();
        return true; // 允许返回
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                // 顶部标题区域
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.05),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          // 在返回前恢复所有轮播
                          _resumeAllCarouselsFromSettings();
                          Navigator.pop(context);
                        },
                        icon: Icon(Icons.arrow_back, size: 28),
                      ),
                      SizedBox(width: 16),
                      Icon(
                        Icons.view_carousel,
                        size: 32,
                        color: Colors.blue.shade600,
                      ),
                      SizedBox(width: 16),
                      Text(
                        '輪播順序設置',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: () async {
                          await DebugCacheUtil.testCarouselOrderPersistence();
                          await DebugCacheUtil.checkAllCarouselOrders();
                          await DebugCacheUtil.checkRawDataCache();
                        },
                        icon: Icon(Icons.bug_report, color: Colors.blue),
                        tooltip: '调试缓存',
                      ),
                    ],
                  ),
                ),

                // 主要内容区域
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 通告轮播设置
                        _buildAnnouncementCarouselSettings(),

                        SizedBox(height: 24),

                        // 顶部广告轮播设置
                        _buildTopAdCarouselSettings(),

                        SizedBox(height: 24),

                        // 全屏广告轮播设置
                        _buildFullscreenAdCarouselSettings(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ///2，构建通告轮播设置组件
  Widget _buildAnnouncementCarouselSettings() {
    return Consumer2<AnnouncementProvider, AnnouncementCarouselProvider>(
      builder: (context, announcementProvider, carouselProvider, child) {
        final announcements = announcementProvider.carouselAnnouncements;
        final currentOrder = carouselProvider.carouselAnnouncements;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.announcement,
                      color: Colors.green.shade600,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    '通告輪播順序',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '${currentOrder.length} 個通告',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              if (currentOrder.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '暫無通告數據',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
              else
                _buildReorderableList<AnnouncementModel>(
                  items: currentOrder,
                  onReorder: (oldIndex, newIndex) {
                    final reorderedList =
                        List<AnnouncementModel>.from(currentOrder);
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final item = reorderedList.removeAt(oldIndex);
                    reorderedList.insert(newIndex, item);
                    carouselProvider.setCarouselList(reorderedList);
                  },
                  itemBuilder: (item, index) =>
                      _buildAnnouncementListItem(item, index),
                ),
            ],
          ),
        );
      },
    );
  }

  ///3，构建顶部广告轮播设置组件
  Widget _buildTopAdCarouselSettings() {
    return Consumer2<AdvertisementProvider, TopAdCarouselProvider>(
      builder: (context, advertisementProvider, carouselProvider, child) {
        final topAds = advertisementProvider.topAdvertisements;
        final currentOrder = carouselProvider.topAds;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.ad_units,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    '頂部廣告輪播順序',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '${currentOrder.length} 個廣告',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              if (currentOrder.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '暫無頂部廣告數據',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
              else
                _buildReorderableList<AdModel>(
                  items: currentOrder,
                  onReorder: (oldIndex, newIndex) {
                    final reorderedList = List<AdModel>.from(currentOrder);
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final item = reorderedList.removeAt(oldIndex);
                    reorderedList.insert(newIndex, item);
                    carouselProvider.setCarouselList(reorderedList);
                  },
                  itemBuilder: (item, index) =>
                      _buildAdListItem(item, index, '頂部'),
                ),
            ],
          ),
        );
      },
    );
  }

  ///4，构建全屏广告轮播设置组件
  Widget _buildFullscreenAdCarouselSettings() {
    return Consumer2<AdvertisementProvider, FullscreenAdProvider>(
      builder: (context, advertisementProvider, carouselProvider, child) {
        final fullscreenAds = advertisementProvider.fullAdvertisements;
        final currentOrder = carouselProvider.fullscreenAds;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.fullscreen,
                      color: Colors.orange.shade600,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    '全屏廣告輪播順序',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '${currentOrder.length} 個廣告',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              if (currentOrder.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '暫無全屏廣告數據',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                )
              else
                _buildReorderableList<AdModel>(
                  items: currentOrder,
                  onReorder: (oldIndex, newIndex) {
                    final reorderedList = List<AdModel>.from(currentOrder);
                    if (newIndex > oldIndex) {
                      newIndex -= 1;
                    }
                    final item = reorderedList.removeAt(oldIndex);
                    reorderedList.insert(newIndex, item);
                    carouselProvider.setCarouselList(reorderedList);
                  },
                  itemBuilder: (item, index) =>
                      _buildAdListItem(item, index, '全屏'),
                ),
            ],
          ),
        );
      },
    );
  }

  ///5，构建可重新排序的列表
  Widget _buildReorderableList<T>({
    required List<T> items,
    required Function(int, int) onReorder,
    required Widget Function(T, int) itemBuilder,
  }) {
    return Container(
      constraints: BoxConstraints(maxHeight: 300),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            key: ValueKey('${item.hashCode}_$index'),
            margin: EdgeInsets.only(bottom: 8),
            child: itemBuilder(item, index),
          );
        },
      ),
    );
  }

  ///6，构建通告列表项
  Widget _buildAnnouncementListItem(AnnouncementModel announcement, int index) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  'ID: ${announcement.id} | 類型: ${announcement.uiType.name}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.drag_handle,
            color: Colors.grey.shade400,
            size: 20,
          ),
        ],
      ),
    );
  }

  ///7，构建广告列表项
  Widget _buildAdListItem(AdModel ad, int index, String type) {
    MaterialColor typeColor = type == '頂部' ? Colors.blue : Colors.orange;

    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: typeColor.shade100,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: typeColor.shade700,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4),
                Text(
                  'ID: ${ad.id} | 時長: ${ad.duration}s | 類型: ${ad.display.name}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.drag_handle,
            color: Colors.grey.shade400,
            size: 20,
          ),
        ],
      ),
    );
  }
}
