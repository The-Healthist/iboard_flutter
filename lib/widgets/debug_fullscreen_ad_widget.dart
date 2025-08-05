import 'package:flutter/material.dart';
import 'package:iboard_app/providers/advertisement_provider.dart';
import 'package:iboard_app/providers/fullscreen_ad_provider.dart';
import 'package:iboard_app/managers/file_manager.dart';
import 'package:iboard_app/models/ad_model.dart';
import 'package:provider/provider.dart';
import 'package:logger/logger.dart';

// foundation.dart import removed as kDebugMode is no longer used

class FullscreenAdDebugWidget extends StatefulWidget {
  const FullscreenAdDebugWidget({Key? key}) : super(key: key);

  @override
  State<FullscreenAdDebugWidget> createState() =>
      _FullscreenAdDebugWidgetState();
}

class _FullscreenAdDebugWidgetState extends State<FullscreenAdDebugWidget> {
  final Logger _logger = Logger();
  final FileManager _fileManager = FileManager();

  List<Map<String, dynamic>> _debugInfo = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _generateDebugInfo();
  }

  ///1，生成调试信息
  Future<void> _generateDebugInfo() async {
    setState(() {
      _isLoading = true;
      _debugInfo.clear();
    });

    try {
      final advertisementProvider = context.read<AdvertisementProvider>();
      final fullscreenAdProvider = context.read<FullscreenAdProvider>();

      // 基本信息
      _debugInfo.add({
        'title': '📊 基本信息',
        'content': [
          '总广告数量: ${advertisementProvider.advertisements.length}',
          '全屏广告数量: ${advertisementProvider.fullAdvertisements.length}',
          'Provider活跃状态: ${fullscreenAdProvider.isActive}',
          '当前广告索引: ${fullscreenAdProvider.currentAdIndex}',
          '广告Widget数量: ${fullscreenAdProvider.adWidgets.length}',
        ]
      });

      // 错误信息
      if (advertisementProvider.error != null) {
        _debugInfo.add({
          'title': '⚠️ 错误信息',
          'content': [
            '错误: ${advertisementProvider.error}',
            '是否正在加载: ${advertisementProvider.isLoading}',
          ]
        });
      }

      // 全屏广告列表
      final fullAds = advertisementProvider.fullAdvertisements;
      if (fullAds.isNotEmpty) {
        List<String> adListInfo = [];
        for (int i = 0; i < fullAds.length; i++) {
          final ad = fullAds[i];
          adListInfo.add('${i + 1}. ID: ${ad.id}, 标题: ${ad.title}');
          adListInfo.add('   类型: ${ad.file.mimeType}');
          adListInfo.add('   URL: ${ad.file.url}');
          adListInfo.add('   时长: ${ad.durationObject.inSeconds}秒');
          adListInfo.add('   文件大小: ${ad.file.fileSize} bytes');
          adListInfo.add('');
        }

        _debugInfo.add({
          'title': '🎬 全屏广告列表 (${fullAds.length}个)',
          'content': adListInfo,
        });
      }

      // 自定义轮播顺序
      final customOrderAds = fullscreenAdProvider.fullscreenAds;
      if (customOrderAds.isNotEmpty) {
        List<String> orderInfo = [];
        for (int i = 0; i < customOrderAds.length; i++) {
          final ad = customOrderAds[i];
          orderInfo.add('${i + 1}. ID: ${ad.id}, 标题: ${ad.title}');
        }

        _debugInfo.add({
          'title': '🔄 自定义轮播顺序 (${customOrderAds.length}个)',
          'content': orderInfo,
        });
      }

      // 文件缓存状态检查
      await _checkFileCacheStatus(fullAds);

      // 当前播放广告详情
      final currentAd = fullscreenAdProvider.getCurrentAd();
      if (currentAd != null) {
        await _checkCurrentAdDetails(currentAd);
      }
    } catch (e) {
      _logger.e('生成调试信息时发生错误', error: e);
      _debugInfo.add({
        'title': '❌ 调试信息生成错误',
        'content': ['错误: $e'],
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  ///2，检查文件缓存状态
  Future<void> _checkFileCacheStatus(List<AdModel> ads) async {
    List<String> cacheInfo = [];

    for (int i = 0; i < ads.length; i++) {
      final ad = ads[i];
      try {
        final localFilePath = await _fileManager.getFile(ad.file);
        if (localFilePath == null) {
          cacheInfo.add('${i + 1}. ${ad.title}');
          cacheInfo.add('   ❌ 无法获取本地文件路径');
          cacheInfo.add('   🎯 文件类型: ${ad.file.mimeType}');
          cacheInfo.add('');
          continue;
        }
        if (await localFilePath.exists()) {
          final fileSize = await localFilePath.length();
          final lastModified = await localFilePath.lastModified();
          cacheInfo.add('${i + 1}. ${ad.title}');
          cacheInfo.add('   ✅ 文件存在: ${localFilePath.path}');
          cacheInfo.add('   📁 文件大小: $fileSize bytes');
          cacheInfo.add('   📅 最后修改: $lastModified');
          cacheInfo.add('   🎯 文件类型: ${ad.file.mimeType}');
        } else {
          cacheInfo.add('${i + 1}. ${ad.title}');
          cacheInfo.add('   ❌ 文件不存在: ${localFilePath.path}');
          cacheInfo.add('   🎯 文件类型: ${ad.file.mimeType}');
        }
        cacheInfo.add('');
      } catch (e) {
        cacheInfo.add('${i + 1}. ${ad.title}');
        cacheInfo.add('   ❌ 检查文件时出错: $e');
        cacheInfo.add('');
      }
    }

    _debugInfo.add({
      'title': '📁 文件缓存状态检查',
      'content': cacheInfo,
    });
  }

  ///3，检查当前播放广告详情
  Future<void> _checkCurrentAdDetails(AdModel currentAd) async {
    List<String> currentAdInfo = [];

    currentAdInfo.add('当前播放广告: ${currentAd.title}');
    currentAdInfo.add('ID: ${currentAd.id}');
    currentAdInfo.add('文件类型: ${currentAd.file.mimeType}');
    currentAdInfo.add('URL: ${currentAd.file.url}');
    currentAdInfo.add('时长: ${currentAd.durationObject.inSeconds}秒');

    try {
      final localFilePath = await _fileManager.getFile(currentAd.file);
      if (localFilePath == null) {
        currentAdInfo.add('❌ 无法获取本地文件路径');
        _debugInfo.add({
          'title': '🎯 当前播放广告详情',
          'content': currentAdInfo,
        });
        return;
      }
      if (await localFilePath.exists()) {
        final fileSize = await localFilePath.length();
        final lastModified = await localFilePath.lastModified();
        currentAdInfo.add('✅ 本地文件路径: ${localFilePath.path}');
        currentAdInfo.add('📁 文件大小: $fileSize bytes');
        currentAdInfo.add('📅 最后修改: $lastModified');

        // 检查文件是否可读
        try {
          await localFilePath.openRead().first;
          currentAdInfo.add('✅ 文件可读');
        } catch (e) {
          currentAdInfo.add('❌ 文件不可读: $e');
        }
      } else {
        currentAdInfo.add('❌ 本地文件不存在: ${localFilePath.path}');
      }
    } catch (e) {
      currentAdInfo.add('❌ 获取文件路径失败: $e');
    }

    _debugInfo.add({
      'title': '🎯 当前播放广告详情',
      'content': currentAdInfo,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全屏广告调试信息'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _generateDebugInfo,
            tooltip: '刷新调试信息',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _debugInfo.length,
              itemBuilder: (context, index) {
                final info = _debugInfo[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ExpansionTile(
                    title: Text(
                      info['title'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: (info['content'] as List<String>)
                              .map((line) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: SelectableText(
                                      line,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
