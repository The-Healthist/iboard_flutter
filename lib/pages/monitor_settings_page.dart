import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:iboard_app/models/monitor_models.dart';
import 'package:iboard_app/providers/app_data_provider.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/ad_top_carousel_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MonitorChannelKey {
  final int orangepiId;
  final String channelName;

  const MonitorChannelKey({
    required this.orangepiId,
    required this.channelName,
  });
}

MonitorChannelKey? parseMonitorChannelKey(String channelKey) {
  final separatorIndex = channelKey.indexOf('_');
  if (separatorIndex <= 0 || separatorIndex == channelKey.length - 1) {
    return null;
  }

  final orangepiId = int.tryParse(channelKey.substring(0, separatorIndex));
  if (orangepiId == null) return null;

  return MonitorChannelKey(
    orangepiId: orangepiId,
    channelName: channelKey.substring(separatorIndex + 1),
  );
}

String getMonitorChannelDisplayName(
  String channelKey,
  List<Orangepi> orangepis,
) {
  final parsedKey = parseMonitorChannelKey(channelKey);
  if (parsedKey == null) return channelKey;

  for (final orangepi in orangepis) {
    if (orangepi.orangepi_id == parsedKey.orangepiId) {
      return '${orangepi.orangepi_name}-${parsedKey.channelName}';
    }
  }

  return parsedKey.channelName;
}

class MonitorSettingsPage extends StatefulWidget {
  const MonitorSettingsPage({super.key});

  @override
  MonitorSettingsPageState createState() => MonitorSettingsPageState();
}

class MonitorSettingsPageState extends State<MonitorSettingsPage> {
  final TextEditingController _apiUrlController = TextEditingController();
  bool _isLoading = false;
  List<Orangepi> _orangepis = [];
  Set<String> _selectedChannels = {};
  String? _currentIsmartId;
  String _currentApiUrl = 'http://ajlive.sunofw.cn:32001/api/auth/public';
  MonitorLayoutType _selectedLayout = MonitorLayoutType.grid4;

  ///布局类型

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  ///1, 載入已保存的設定
  Future<void> _loadSavedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedApiUrl = prefs.getString('monitor_api_url');
      final savedChannels = prefs.getStringList('monitor_selected_channels');
      final savedLayout = prefs.getString('monitor_layout_type');

      if (!mounted) return;
      setState(() {
        _currentApiUrl = savedApiUrl ?? _currentApiUrl;
        _apiUrlController.text = _currentApiUrl;
        _selectedChannels = Set.from(savedChannels ?? []);
        _selectedLayout = MonitorLayoutType.fromString(savedLayout ?? 'grid4');
      });

      await _loadBuildingIsmartId();
    } catch (e) {
      // 靜默失敗
    }
  }

  ///2, 從AppDataProvider獲取大廈ismartid
  Future<void> _loadBuildingIsmartId() async {
    try {
      final appDataProvider =
          Provider.of<AppDataProvider>(context, listen: false);
      final ismartId = appDataProvider.settingsModel?.building.ismartId;

      if (ismartId != null && ismartId.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _currentIsmartId = ismartId;
        });

        await _onGetMonitorData();
      } else {
        _showError('未找到大廈ismartid，請先確保設備已正確登入');
      }
    } catch (e) {
      _showError('獲取大廈ismartid失敗: ${e.toString()}');
    }
  }

  ///3, 保存設定
  Future<bool> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('monitor_api_url', _currentApiUrl);
      await prefs.setStringList(
          'monitor_selected_channels', _selectedChannels.toList());
      await prefs.setString('monitor_layout_type', _selectedLayout.name);
      return true;
    } catch (e) {
      if (mounted) {
        _showError('保存失敗: ${e.toString()}');
      }
      return false;
    }
  }

  ///4, 獲取監控數據
  Future<void> _onGetMonitorData() async {
    if (_currentIsmartId == null || _currentIsmartId!.isEmpty) {
      _showError('大廈ismartid為空');
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final apiUrl = _apiUrlController.text.trim().isEmpty
          ? _currentApiUrl
          : _apiUrlController.text.trim();

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(MonitorRequest(
          ismartId: _currentIsmartId!,
          isStaff: true,
        ).toJson()),
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        final monitorResponse =
            MonitorResponse.fromJsonObject(jsonDecode(response.body));

        if (monitorResponse.success) {
          if (!mounted) return;
          setState(() {
            _orangepis = monitorResponse.data.orangepis;
            _currentApiUrl = apiUrl;
          });
          _showSuccess('監控數據獲取成功');
        } else {
          _showError('獲取監控數據失敗');
        }
      } else {
        _showError('網路請求失敗: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        _showError('請求失敗: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  ///5, 手動刷新監控數據
  Future<void> _onRefreshButtonPressed() async {
    final inputUrl = _apiUrlController.text.trim();
    if (inputUrl.isNotEmpty) {
      _currentApiUrl = inputUrl;
    }

    await _onGetMonitorData();
  }

  ///2, 切換通道選擇
  void _toggleChannelSelection(String channelKey) {
    // 如果布局是 hidden，不允许选择
    if (_selectedLayout == MonitorLayoutType.hidden) {
      _showError('「不顯示」佈局無需選擇監控通道');
      return;
    }

    setState(() {
      if (_selectedChannels.contains(channelKey)) {
        _selectedChannels.remove(channelKey);
      } else {
        if (_selectedChannels.length < _selectedLayout.count) {
          _selectedChannels.add(channelKey);
        } else {
          _showError('此佈局最多只能選擇${_selectedLayout.count}個監控通道');
        }
      }
    });
  }

  ///7, 取消選中的通道
  void _removeChannel(String channelKey) {
    setState(() {
      _selectedChannels.remove(channelKey);
    });
  }

  ///8, 獲取已選中通道的顯示名稱
  String _getChannelDisplayName(String channelKey) {
    return getMonitorChannelDisplayName(channelKey, _orangepis);
  }

  ///3, 顯示成功消息
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  ///6, 確認選擇
  Future<void> _confirmSelection() async {
    // 如果布局不是 hidden，要求至少选择一个通道
    if (_selectedLayout != MonitorLayoutType.hidden &&
        _selectedChannels.isEmpty) {
      _showError('請至少選擇一個監控通道');
      return;
    }

    // 如果布局是 hidden，清空已选通道
    if (_selectedLayout == MonitorLayoutType.hidden) {
      _selectedChannels.clear();
    }

    final saved = await _saveSettings();
    if (!saved || !mounted) return;

    //  立即刷新监控画面配置（不等待广告轮播）
    try {
      final topAdCarouselProvider =
          Provider.of<TopAdCarouselProvider>(context, listen: false);
      await topAdCarouselProvider.refreshAllMonitorWidgets();
    } catch (_) {}

    if (!mounted) return;
    // 触发广告轮播更新，以便重新读取监控配置（用于下次轮播）
    try {
      final advertisementProvider =
          Provider.of<AdvertisementProvider>(context, listen: false);
      await advertisementProvider.fetchAdvertisements(forceInit: true);
    } catch (_) {}

    if (!mounted) return;
    _showSuccess('監控通道設定已保存並立即生效');

    _notifyLiveMonitorUpdate();
  }

  ///5, 通知實時監控頁面更新
  void _notifyLiveMonitorUpdate() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        Navigator.pop(context, true);
      }
    });
  }

  ///5, 顯示錯誤消息
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  ///6, 构建香橙派卡片
  Widget _buildOrangepiCard(Orangepi orangepi) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 6,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: orangepi.is_active
                      ? Colors.green.shade50
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.device_hub,
                  color: orangepi.is_active
                      ? Colors.green.shade600
                      : Colors.grey.shade600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  orangepi.orangepi_name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: orangepi.is_active
                      ? Colors.green.shade100
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  orangepi.is_active ? '在線' : '離線',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: orangepi.is_active
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: orangepi.urls.asMap().entries.map((entry) {
              final index = entry.key;
              final channelName = 'channel${index + 1}';
              final channelKey = '${orangepi.orangepi_id}_$channelName';
              final isSelected = _selectedChannels.contains(channelKey);
              final isDisabled = _selectedLayout == MonitorLayoutType.hidden;

              return GestureDetector(
                onTap: isDisabled
                    ? null
                    : () => _toggleChannelSelection(channelKey),
                child: Opacity(
                  opacity: isDisabled ? 0.5 : 1.0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.blue.shade600
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? Colors.blue.shade600
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.videocam_outlined,
                          size: 16,
                          color:
                              isSelected ? Colors.white : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          channelName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      color: Colors.grey.withValues(alpha: 0.05),
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
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.arrow_back, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Icon(
                      Icons.settings_remote,
                      size: 32,
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '設定監控畫面',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
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
                      const SizedBox(height: 40),

                      // 设置卡片
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withValues(alpha: 0.1),
                              spreadRadius: 1,
                              blurRadius: 6,
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
                                    Icons.api,
                                    color: Colors.blue.shade600,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'API介面配置',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // API地址输入框和按钮区域
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '介面地址 (可選)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _apiUrlController,
                                        enabled: !_isLoading,
                                        decoration: InputDecoration(
                                          hintText:
                                              '預設: http://ajlive.sunofw.cn:32001/api/auth/public',
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            borderSide: BorderSide(
                                                color: Colors.blue.shade600),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton(
                                      onPressed: _isLoading
                                          ? null
                                          : _onRefreshButtonPressed,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue.shade600,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 24,
                                          vertical: 12,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text('刷新'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            ///  布局选择部分
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '監控佈局選擇',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children:
                                      MonitorLayoutType.values.map((layout) {
                                    final isSelected =
                                        _selectedLayout == layout;
                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedLayout = layout;
                                              // 如果选择"不显示"，清空已选通道
                                              if (layout ==
                                                  MonitorLayoutType.hidden) {
                                                _selectedChannels.clear();
                                              } else if (_selectedChannels
                                                      .length >
                                                  layout.count) {
                                                // 如果选中的通道数超过新布局的最大数，移除多余的
                                                final channelList =
                                                    _selectedChannels.toList();
                                                _selectedChannels = Set.from(
                                                    channelList
                                                        .take(layout.count));
                                              }
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? Colors.blue.shade600
                                                  : Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isSelected
                                                    ? Colors.blue.shade600
                                                    : Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  layout.label,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: isSelected
                                                        ? Colors.white
                                                        : Colors.grey.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // 大厦信息显示
                            if (_currentIsmartId != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.green.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.business,
                                      color: Colors.green.shade600,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '當前大廈 iSmart ID: $_currentIsmartId',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            if (_selectedChannels.isNotEmpty) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.blue.shade200),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          color: Colors.blue.shade600,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '已選擇 ${_selectedChannels.length}/${_selectedLayout.count} 個監控通道',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.blue.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_selectedChannels.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children:
                                            _selectedChannels.map((channelKey) {
                                          return GestureDetector(
                                            onTap: () =>
                                                _removeChannel(channelKey),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade600,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _getChannelDisplayName(
                                                        channelKey),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons.close,
                                                    size: 14,
                                                    color: Colors.white,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),

                      if (_orangepis.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        ..._orangepis
                            .map((orangepi) => _buildOrangepiCard(orangepi)),
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.1),
                                spreadRadius: 1,
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.blue.shade600,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '確認選擇',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '已選擇 ${_selectedChannels.length}/${_selectedLayout.count} 個通道',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _confirmSelection,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Text(
                                    '確認保存',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
