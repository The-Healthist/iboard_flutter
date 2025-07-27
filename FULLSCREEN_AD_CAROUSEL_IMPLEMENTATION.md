# 全屏广告轮播功能实现文档

## 概述
本次实现完成了全屏广告的轮播功能，参考了通告轮播和顶部广告轮播的逻辑，支持视频和图片的全屏播放，采用cover布局，并实现了暂停恢复功能。

## 主要实现内容

### 1. 更新了 `FullAdvertisementCarouselProvider` (`lib/providers/full_advertisement_carousel_provider.dart`)

**主要特性：**
- 简化了定时器逻辑，只保留一个主要的轮播定时器 `_carouselTimer`
- 支持暂停和恢复功能，记录播放进度
- 使用API配置的 `advertisementPlayDuration` 作为全屏广告停留时间
- 自动轮播所有全屏广告列表
- 支持调试日志输出

**主要方法：**
- `updateFullscreenAds()` - 更新广告数据并创建Widget组件
- `enterFullscreenMode(int advertisementPlayDuration)` - 进入全屏广告模式并开始轮播
- `exitFullscreenMode()` - 退出全屏广告模式
- `pauseCarousel()` - 暂停轮播并记录播放进度
- `resumeCarousel(int advertisementPlayDuration)` - 恢复轮播从暂停位置继续
- `getCurrentAd()` - 获取当前播放的广告
- `getCurrentAdWidget()` - 获取当前播放的广告Widget
- `startDebugTimer()` / `stopDebugTimer()` - 启动/停止调试定时器

### 2. 重构了 `FullscreenAdsPage` (`lib/pages/fullscreen_ads_page.dart`)

**主要改进：**
- 使用 `Consumer3` 监听三个Provider：`AdvertisementProvider`、`FullAdvertisementCarouselProvider`、`CarouselStateProvider`
- 支持错误状态、加载状态和默认状态的显示
- 自动使用Provider提供的当前广告Widget
- 移除了手动索引管理，完全依赖Provider

### 3. 更新了 `FullAdWidget` (`lib/widgets/full_ad_widget.dart`)

**主要改进：**
- 视频播放使用 `FittedBox` 和 `BoxFit.cover` 确保全屏填充
- 图片显示继续使用 `BoxFit.cover`
- 保持了原有的错误处理和加载状态显示

### 4. 集成到 `MainscreenPage` (`lib/pages/mainscreen_page.dart`)

**主要改进：**
- 添加了对 `FullAdvertisementCarouselProvider` 的支持
- 在 `_pauseAllCarousels()` 方法中启动全屏广告轮播
- 在 `_resumeAllCarousels()` 方法中退出全屏广告轮播
- 更新设置页面的暂停/恢复逻辑以包含全屏广告
- 在广告数据更新时同步更新全屏广告数据

### 5. 注册Provider (`lib/main.dart`)

**添加的Provider：**
- `FullAdvertisementCarouselProvider` 注册到应用的Provider树中

## 功能特性

### 1. 轮播功能
- ✅ 进入全屏广告状态后自动开始轮播
- ✅ 每个广告使用其自身的 `duration` 属性作为播放时间
- ✅ 自动循环播放所有全屏广告
- ✅ 支持视频和图片内容

### 2. 暂停恢复功能
- ✅ 退出全屏广告前暂停当前播放
- ✅ 记录播放进度（已播放时间）
- ✅ 下次进入时从暂停位置继续播放
- ✅ 支持设置页面的暂停恢复

### 3. 布局支持
- ✅ 视频和图片都采用cover布局全屏显示
- ✅ 视频使用 `FittedBox` + `BoxFit.cover`
- ✅ 图片使用 `BoxFit.cover`

### 4. 时间配置
- ✅ 使用 `state_provider.dart` 中的 `advertisementPlayDuration` (API获取)
- ✅ 不修改state_provider.dart的现有逻辑
- ✅ 简化定时器，只保留一个主要轮播定时器

### 5. 调试功能
- ✅ 详细的日志记录
- ✅ 实时状态调试输出
- ✅ 播放进度跟踪

## 使用方式

### 进入全屏广告模式
当 `CarouselStateProvider` 的状态变为 `AppState.fullscreenAd` 时：
1. 自动暂停其他所有轮播
2. 启动全屏广告轮播
3. 使用API配置的播放时间

### 退出全屏广告模式
当状态变为 `AppState.defaultState` 时：
1. 暂停全屏广告轮播并记录进度
2. 恢复其他轮播的播放
3. 保存播放状态以便下次恢复

### 手动操作
- 进入设置页面会暂停全屏广告轮播
- 退出设置页面会恢复全屏广告轮播（如果之前处于活跃状态）

## 技术实现细节

### 时间管理
- 使用 `DateTime` 记录开始时间和暂停时间
- 计算已播放时间和剩余时间
- 支持精确的暂停恢复

### 状态管理
- `_isActive` - 是否处于全屏广告模式
- `_isPaused` - 是否暂停状态
- `_currentAdIndex` - 当前广告索引
- `_adElapsedTime` - 已播放时间
- `_adDuration` - 当前广告总时长

### 错误处理
- 广告数据为空时显示默认界面
- 网络错误时显示错误信息
- 视频加载失败时提供重试选项

## 测试建议

1. **基本轮播测试**：验证广告能否正常轮播
2. **暂停恢复测试**：测试进入/退出全屏广告的暂停恢复功能
3. **混合内容测试**：测试视频和图片混合的轮播
4. **边界情况测试**：测试无广告数据、网络错误等情况
5. **设置页面测试**：测试进入设置页面的暂停恢复功能

## 依赖关系

此实现依赖以下Provider：
- `AdvertisementProvider` - 提供广告数据
- `CarouselStateProvider` - 提供状态管理和时间配置
- `FullAdvertisementCarouselProvider` - 管理全屏广告轮播逻辑

## 配置说明

无需额外配置，使用现有API配置：
- `advertisementPlayDuration` - 全屏广告播放时长（秒）
- 每个广告的 `duration` 属性 - 单个广告的播放时长

## 注意事项

1. 确保广告数据中包含正确的 `duration` 属性
2. 视频文件需要是支持的格式
3. 网络图片需要确保可访问性
4. 调试模式下会有详细的日志输出
