import 'package:flutter/material.dart';
import 'package:iboard_app/models/announcement_model.dart';
import 'package:iboard_app/providers/announcement_provider.dart';
import 'package:provider/provider.dart';

class MainScreenWidget extends StatefulWidget {
  final Function(AnnouncementModel? announcement)?
      onAnnouncementTap; // 修改回调函数支持null
  final VoidCallback? onArrearTableTap; // 添加欠费总览回调

  const MainScreenWidget({
    Key? key,
    this.onAnnouncementTap,
    this.onArrearTableTap,
  }) : super(key: key);

  @override
  MainScreenWidgetState createState() => MainScreenWidgetState();
}

class MainScreenWidgetState extends State<MainScreenWidget> {
  // Set default to all
  AnnouncementTypeUi _selectedAnnouncementType = AnnouncementTypeUi.all;

  @override
  void initState() {
    super.initState();
    // Fetch notices when the widget is initialized
    // Use WidgetsBinding.instance.addPostFrameCallback to ensure Provider is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check if the widget is still mounted before accessing the provider
      if (mounted) {
        Provider.of<AnnouncementProvider>(context, listen: false)
            .fetchNotices();
      }
    });
  }

  Widget _buildFunctionButton(
      String chineseTitle, String englishTitle, IconData icon) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              // 处理功能按钮点击
              if (chineseTitle == '欠費查詢') {
                print('🔵 [MainScreenWidget] 用户点击欠费查询按钮');
                // 调用回调函数来显示欠费查询界面
                // 确保立即进入手动操作状态并显示欠费查询界面
                widget.onAnnouncementTap?.call(null); // 传递null表示显示欠费查询
                print('🔵 [MainScreenWidget] 已调用 onAnnouncementTap(null)');
              } else if (chineseTitle == '欠費總覽') {
                print('🔵 [MainScreenWidget] 用户点击欠费总览按钮');
                // 导航到欠费总览页面
                widget.onArrearTableTap?.call();
                print('🔵 [MainScreenWidget] 已调用 onArrearTableTap()');
              } else {
                print('$chineseTitle pressed');
              }
            },
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              padding: const EdgeInsets.all(16.0),
              minimumSize: const Size(double.infinity, 0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 32),
                const SizedBox(height: 8),
                Text(
                  chineseTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  englishTitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnnouncementTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        // Use AnnouncementTypeUi.values
        children: AnnouncementTypeUi.values.map((type) {
          return ChoiceChip(
            label: Text(_getAnnouncementTypeText(type)),
            selected: _selectedAnnouncementType == type,
            onSelected: (selected) {
              if (selected) {
                setState(() {
                  _selectedAnnouncementType = type;
                  // Filtering will be applied by the ListView builder
                  print('Selected type: $type');
                });
              }
            },
          );
        }).toList(),
      ),
    );
  }

  // Update to use AnnouncementTypeUi and add "All"
  String _getAnnouncementTypeText(AnnouncementTypeUi type) {
    switch (type) {
      case AnnouncementTypeUi.all:
        return '全部';
      case AnnouncementTypeUi.general:
        return '一般';
      case AnnouncementTypeUi.emergency:
        return '緊急';
      case AnnouncementTypeUi.government:
        return '政府';
      case AnnouncementTypeUi.corporation:
        return '法團';
      default:
        return ''; // Should not happen
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AnnouncementProvider>(
      builder: (context, announcementProvider, child) {
        // Filter announcements based on the selected UI type
        final List<AnnouncementModel> filteredAnnouncements;
        if (_selectedAnnouncementType == AnnouncementTypeUi.all) {
          filteredAnnouncements = announcementProvider.announcements;
        } else {
          filteredAnnouncements = announcementProvider.announcements
              .where((announcement) =>
                  announcement.uiType == _selectedAnnouncementType)
              .toList();
        }

        return Scaffold(
          body: Row(
            children: [
              // Left Side: Function Selection
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _buildFunctionButton(
                                '欠費查詢', 'Payment Inquiry', Icons.payment),
                            _buildFunctionButton('欠費總覽', 'Self Payment',
                                Icons.account_balance_wallet),
                            _buildFunctionButton('自助繳款', 'Convenience Services',
                                Icons.local_convenience_store),
                            _buildFunctionButton(
                                '便利服務', 'Member Store', Icons.store),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Right Side: Announcements
              Expanded(
                flex: 5,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAnnouncementTypeSelector(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '通告列表',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          if (announcementProvider.isLoading)
                            const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.0)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 智能错误显示：网络错误且有缓存数据时不显示错误信息
                      if (announcementProvider.error != null &&
                          !announcementProvider.isLoading) ...[
                        Builder(
                          builder: (context) {
                            // 检查是否是网络错误且有缓存数据
                            final error = announcementProvider.error!;
                            final hasCachedData =
                                announcementProvider.announcements.isNotEmpty;
                            final isNetworkError = error.contains('网络连接失败') ||
                                error.contains('请求超时') ||
                                error.contains('使用缓存的');

                            // 只有在非网络错误或没有缓存数据时才显示错误
                            if (!isNetworkError || !hasCachedData) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16.0),
                                child: Text(
                                  'Error: $error',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                      Expanded(
                        child: announcementProvider.isLoading &&
                                filteredAnnouncements.isEmpty
                            ? const Center(
                                child: Text(
                                    "讀取中...")) // Show loading text if initially loading and no data yet
                            : filteredAnnouncements.isEmpty
                                ? Center(
                                    child: Text(
                                        '沒有任何通告.')) // Updated for all types
                                : ListView.builder(
                                    itemCount: filteredAnnouncements.length,
                                    itemBuilder: (context, index) {
                                      final announcement =
                                          filteredAnnouncements[index];
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 4.0),
                                        child: ListTile(
                                          title: Text(announcement.title),
                                          subtitle: Text(
                                              '${_getAnnouncementTypeText(announcement.uiType)} - ${announcement.description}'),
                                          onTap: () {
                                            print(
                                                '📰 [MainScreenWidget] 用户点击通告: ${announcement.title} (类型: ${announcement.uiType})');
                                            // 调用回调函数传递announcement对象
                                            widget.onAnnouncementTap
                                                ?.call(announcement);
                                            print(
                                                '📰 [MainScreenWidget] 已调用 onAnnouncementTap(${announcement.title})');
                                          },
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
