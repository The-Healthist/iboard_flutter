import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:iboard_app/providers/announcement_carousel_provider.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/ad_full_carousel_provider.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:iboard_app/widgets/debug_fullscreen_ad_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 添加SharedPreferences導入

class CarouselSettingsPage extends StatefulWidget {
  const CarouselSettingsPage({super.key});

  @override
  CarouselSettingsPageState createState() => CarouselSettingsPageState();
}

class CarouselSettingsPageState extends State<CarouselSettingsPage> {
  bool _isClearing = false; // 添加清理狀態標記

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        // 直接返回，不恢复轮播，因为这只是返回到设置页面
        // PopScope handles the pop automatically
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: SafeArea(
            child: Column(
              children: [
                // 顶部标题区域
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.05),
                        spreadRadius: 1,
                        blurRadius: 3,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          // 直接返回，不恢复轮播
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.arrow_back, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.view_carousel,
                        size: 32,
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '輪播順序顯示',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const Spacer(),
                      // 添加清空緩存按鈕
                      ElevatedButton.icon(
                        onPressed: _isClearing ? null : _clearAllCache,
                        icon: _isClearing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.clear_all, size: 18),
                        label: Text(
                          _isClearing ? '清理中...' : '清空緩存',
                          style: const TextStyle(fontSize: 14),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade100,
                          foregroundColor: Colors.red.shade800,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: const Size(0, 36),
                        ),
                      ),
                    ],
                  ),
                ),

                // 主要内容区域
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 说明文字
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue.shade600,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '輪播順序由後台統一管理，此頁面僅供查看當前輪播順序。如需調整順序，請聯繫管理員在後台進行設置。',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // 通告轮播设置
                        _buildAnnouncementCarouselSettings(),

                        const SizedBox(height: 24),

                        // 顶部广告轮播设置
                        _buildTopAdCarouselSettings(),

                        const SizedBox(height: 24),

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

  ///1，清空所有輪播緩存數據
  Future<void> _clearAllCache() async {
    setState(() {
      _isClearing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      // 清空通告緩存數據
      await prefs.remove('announcements_data');

      // 清空廣告緩存數據
      await prefs.remove('advertisements_data');
      await prefs.remove('top_carousel_advertisements');
      await prefs.remove('full_carousel_advertisements');

      // 清空Provider中的數據
      if (mounted) {
        final announcementProvider = context.read<AnnouncementProvider>();
        final advertisementProvider = context.read<AdvertisementProvider>();
        final announcementCarouselProvider =
            context.read<AnnouncementCarouselProvider>();
        final topAdCarouselProvider = context.read<TopAdCarouselProvider>();
        final fullscreenAdProvider = context.read<FullscreenAdProvider>();

        // 清空輪播Provider的數據
        announcementCarouselProvider.updateCarouselList([]);
        topAdCarouselProvider.clearCarouselList();
        fullscreenAdProvider.clearCarouselList();
      }

      // 顯示成功提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ 輪播緩存數據已清空'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // 顯示錯誤提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 清空緩存失敗: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearing = false;
        });
      }
    }
  }

  ///2，构建通告轮播设置组件
  Widget _buildAnnouncementCarouselSettings() {
    return Consumer2<AnnouncementProvider, AnnouncementCarouselProvider>(
      builder: (context, announcementProvider, carouselProvider, child) {
        final announcements = announcementProvider.carouselAnnouncements;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
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
                  const SizedBox(width: 16),
                  Text(
                    '通告輪播順序',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${announcements.length} 個通告',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (announcements.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
                _buildReadOnlyList<AnnouncementModel>(
                  items: announcements,
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
        final topAds = advertisementProvider.topCarouselAdvertisements;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
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
                  const SizedBox(width: 16),
                  Text(
                    '頂部廣告輪播順序',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${topAds.length} 個廣告',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (topAds.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
                _buildReadOnlyList<AdModel>(
                  items: topAds,
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
        final fullscreenAds = advertisementProvider.fullCarouselAdvertisements;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.05),
                spreadRadius: 1,
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
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
                  const SizedBox(width: 16),
                  Text(
                    '全屏廣告輪播順序',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${fullscreenAds.length} 個廣告',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const FullscreenAdDebugWidget(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.bug_report, size: 16),
                    label: const Text('调试', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade100,
                      foregroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (fullscreenAds.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
                _buildReadOnlyList<AdModel>(
                  items: fullscreenAds,
                  itemBuilder: (item, index) =>
                      _buildAdListItem(item, index, '全屏'),
                ),
            ],
          ),
        );
      },
    );
  }

  ///5，构建只读列表（移除拖拽功能）
  Widget _buildReadOnlyList<T>({
    required List<T> items,
    required Widget Function(T, int) itemBuilder,
  }) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Container(
            key: ValueKey('${item.hashCode}_$index'),
            margin: const EdgeInsets.only(bottom: 8),
            child: itemBuilder(item, index),
          );
        },
      ),
    );
  }

  ///6，构建通告列表项
  Widget _buildAnnouncementListItem(AnnouncementModel announcement, int index) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          const SizedBox(width: 12),
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
                const SizedBox(height: 4),
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
            Icons.lock, // 改为锁定图标表示只读
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
      padding: const EdgeInsets.all(12),
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
          const SizedBox(width: 12),
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
                const SizedBox(height: 4),
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
            Icons.lock, // 改为锁定图标表示只读
            color: Colors.grey.shade400,
            size: 20,
          ),
        ],
      ),
    );
  }
}
