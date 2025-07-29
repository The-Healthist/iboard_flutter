import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:logger/logger.dart';

/// 调试缓存工具类
/// 用于检查SharedPreferences中的缓存数据
class DebugCacheUtil {
  static final Logger _logger = Logger();

  ///1，检查所有轮播顺序缓存
  static Future<void> checkAllCarouselOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查顶部广告轮播顺序
      final topAdOrder = prefs.getString('top_ad_carousel_order');
      if (topAdOrder != null) {
        final topAdData = json.decode(topAdOrder) as List;
        _logger.i('📋 顶部广告轮播顺序缓存: ${topAdData.length}个配置');
        for (int i = 0; i < topAdData.length; i++) {
          final item = topAdData[i];
          _logger.i(
              '  ${i + 1}. ID: ${item['id']}, 标题: ${item['title']}, 顺序: ${item['order']}');
        }
      } else {
        _logger.w('❌ 顶部广告轮播顺序缓存为空');
      }

      // 检查通告轮播顺序
      final announcementOrder = prefs.getString('announcement_carousel_order');
      if (announcementOrder != null) {
        final announcementData = json.decode(announcementOrder) as List;
        _logger.i('📋 通告轮播顺序缓存: ${announcementData.length}个配置');
        for (int i = 0; i < announcementData.length; i++) {
          final item = announcementData[i];
          _logger.i(
              '  ${i + 1}. ID: ${item['id']}, 标题: ${item['title']}, 顺序: ${item['order']}');
        }
      } else {
        _logger.w('❌ 通告轮播顺序缓存为空');
      }

      // 检查全屏广告轮播顺序
      final fullscreenAdOrder = prefs.getString('fullscreen_ad_carousel_order');
      if (fullscreenAdOrder != null) {
        final fullscreenAdData = json.decode(fullscreenAdOrder) as List;
        _logger.i('📋 全屏广告轮播顺序缓存: ${fullscreenAdData.length}个配置');
        for (int i = 0; i < fullscreenAdData.length; i++) {
          final item = fullscreenAdData[i];
          _logger.i(
              '  ${i + 1}. ID: ${item['id']}, 标题: ${item['title']}, 顺序: ${item['order']}');
        }
      } else {
        _logger.w('❌ 全屏广告轮播顺序缓存为空');
      }
    } catch (e) {
      _logger.e('检查轮播顺序缓存失败', error: e);
    }
  }

  ///2，检查原始数据缓存
  static Future<void> checkRawDataCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查广告数据缓存
      final advertisementsData = prefs.getString('advertisements_data');
      if (advertisementsData != null) {
        final adsData = json.decode(advertisementsData) as List;
        _logger.i('📋 广告数据缓存: ${adsData.length}个广告');
        for (int i = 0; i < adsData.length; i++) {
          final ad = adsData[i];
          _logger.i(
              '  ${i + 1}. ID: ${ad['id']}, 标题: ${ad['title']}, 显示类型: ${ad['display']}');
        }
      } else {
        _logger.w('❌ 广告数据缓存为空');
      }

      // 检查通告数据缓存
      final announcementsData = prefs.getString('announcements_data');
      if (announcementsData != null) {
        final announcementsList = json.decode(announcementsData) as List;
        _logger.i('📋 通告数据缓存: ${announcementsList.length}个通告');
        for (int i = 0; i < announcementsList.length; i++) {
          final announcement = announcementsList[i];
          _logger.i(
              '  ${i + 1}. ID: ${announcement['id']}, 标题: ${announcement['title']}, 类型: ${announcement['type']}');
        }
      } else {
        _logger.w('❌ 通告数据缓存为空');
      }
    } catch (e) {
      _logger.e('检查原始数据缓存失败', error: e);
    }
  }

  ///3，清除所有轮播顺序缓存
  static Future<void> clearAllCarouselOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('top_ad_carousel_order');
      await prefs.remove('announcement_carousel_order');
      await prefs.remove('fullscreen_ad_carousel_order');
      _logger.i('🗑️ 已清除所有轮播顺序缓存');
    } catch (e) {
      _logger.e('清除轮播顺序缓存失败', error: e);
    }
  }

  ///4，清除所有数据缓存
  static Future<void> clearAllDataCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('advertisements_data');
      await prefs.remove('announcements_data');
      _logger.i('🗑️ 已清除所有数据缓存');
    } catch (e) {
      _logger.e('清除数据缓存失败', error: e);
    }
  }

  ///5，检查所有缓存键
  static Future<void> checkAllCacheKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      _logger.i('📋 所有缓存键: ${keys.length}个');
      for (final key in keys) {
        final value = prefs.get(key);
        if (value is String) {
          _logger.i('  $key: ${value.length} 字符');
        } else {
          _logger.i('  $key: $value');
        }
      }
    } catch (e) {
      _logger.e('检查缓存键失败', error: e);
    }
  }

  ///6，测试轮播顺序保存和恢复功能
  static Future<void> testCarouselOrderPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 创建测试数据
      final testOrderData = [
        {'id': 1, 'title': '测试广告1', 'order': 0},
        {'id': 2, 'title': '测试广告2', 'order': 1},
        {'id': 3, 'title': '测试广告3', 'order': 2},
      ];

      // 保存测试数据
      await prefs.setString('test_carousel_order', json.encode(testOrderData));
      _logger.i('✅ 测试轮播顺序已保存');

      // 读取测试数据
      final savedData = prefs.getString('test_carousel_order');
      if (savedData != null) {
        final decodedData = json.decode(savedData) as List;
        _logger.i('✅ 测试轮播顺序读取成功: ${decodedData.length}个配置');

        // 验证数据完整性
        bool isValid = true;
        for (int i = 0; i < decodedData.length; i++) {
          final item = decodedData[i];
          if (item['id'] != testOrderData[i]['id'] ||
              item['title'] != testOrderData[i]['title'] ||
              item['order'] != testOrderData[i]['order']) {
            isValid = false;
            _logger.e('❌ 数据验证失败: 索引$i');
            break;
          }
        }

        if (isValid) {
          _logger.i('✅ 轮播顺序持久化功能正常');
        } else {
          _logger.e('❌ 轮播顺序持久化功能异常');
        }
      } else {
        _logger.e('❌ 测试轮播顺序读取失败');
      }

      // 清理测试数据
      await prefs.remove('test_carousel_order');
      _logger.i('🗑️ 测试数据已清理');
    } catch (e) {
      _logger.e('测试轮播顺序持久化功能失败', error: e);
    }
  }
}
