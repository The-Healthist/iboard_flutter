import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import '../http/api_client.dart';
import '../utils/version_util.dart';

///1. 应用更新状态管理Provider - 整合所有更新功能
class AppUpdateProvider with ChangeNotifier {
  final Dio _dio = Dio();
  CancelToken? _downloadCancelToken;
  Timer? _updateCheckTimer;

  // 当前版本信息
  String? _currentVersion;
  String? get currentVersion => _currentVersion;

  // 远程版本信息
  String? _remoteVersion;
  String? get remoteVersion => _remoteVersion;

  String? _remoteVersionNumber;
  String? get remoteVersionNumber => _remoteVersionNumber;

  String? _remoteBuildNumber;
  String? get remoteBuildNumber => _remoteBuildNumber;

  String? _updateDescription;
  String? get updateDescription => _updateDescription;

  String? _downloadUrl;
  String? get downloadUrl => _downloadUrl;

  // 状态信息
  bool _isCheckingUpdate = false;
  bool get isCheckingUpdate => _isCheckingUpdate;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _isInstalling = false;
  bool get isInstalling => _isInstalling;

  bool _hasUpdate = false;
  bool get hasUpdate => _hasUpdate;

  bool _hasLocalApk = false;
  bool get hasLocalApk => _hasLocalApk;

  String? _localApkPath;
  String? get localApkPath => _localApkPath;

  String? _error;
  String? get error => _error;

  // 下载进度
  int _downloadProgress = 0;
  int get downloadProgress => _downloadProgress;

  int _downloadReceived = 0;
  int get downloadReceived => _downloadReceived;

  int _downloadTotal = 0;
  int get downloadTotal => _downloadTotal;

  // 权限状态
  bool _hasStoragePermission = false;
  bool get hasStoragePermission => _hasStoragePermission;

  bool _hasInstallPermission = false;
  bool get hasInstallPermission => _hasInstallPermission;

  // 下载方式
  bool _useSystemDownloader = false;
  bool get useSystemDownloader => _useSystemDownloader;

  ///2. 初始化权限状态检查
  Future<void> initializePermissions() async {
    await _checkCurrentPermissions();
  }

  ///3. 检查当前权限状态
  Future<void> _checkCurrentPermissions() async {
    try {
      if (Platform.isAndroid) {
        // 检查存储权限
        _hasStoragePermission = await _checkStoragePermission();

        // 检查安装权限
        _hasInstallPermission =
            await Permission.requestInstallPackages.isGranted;

        print('📋 权限状态检查完成:');
        print('  存储权限: ${_hasStoragePermission ? '已授权' : '未授权'}');
        print('  安装权限: ${_hasInstallPermission ? '已授权' : '未授权'}');

        notifyListeners();
      } else {
        _hasStoragePermission = true;
        _hasInstallPermission = true;
      }
    } catch (e) {
      print('❌ 权限状态检查失败: $e');
    }
  }

  ///4. 检查存储权限（适配Android不同版本）
  Future<bool> _checkStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      // Android 13+ (API 33+) 不需要存储权限
      final androidInfo = await _getAndroidVersion();
      if (androidInfo >= 33) {
        print('📱 Android 13+，不需要存储权限');
        return true;
      }

      // Android 11-12 (API 30-32)
      if (androidInfo >= 30) {
        // 检查是否有管理外部存储权限
        final managePermission =
            await Permission.manageExternalStorage.isGranted;
        if (managePermission) return true;

        // 或者检查基本存储权限
        final storagePermission = await Permission.storage.isGranted;
        return storagePermission;
      }

      // Android 10及以下
      return await Permission.storage.isGranted;
    } catch (e) {
      print('❌ 检查存储权限失败: $e');
      return false;
    }
  }

  ///5. 获取Android版本
  Future<int> _getAndroidVersion() async {
    try {
      if (Platform.isAndroid) {
        // 简化版本检查，假设现代Android版本
        return 30; // 可以根据需要实现更精确的版本检查
      }
      return 0;
    } catch (e) {
      return 30; // 默认假设为Android 11
    }
  }

  ///6. 请求所有必要权限
  Future<bool> requestAllPermissions() async {
    try {
      print('🔐 开始请求应用更新所需权限...');

      if (Platform.isAndroid) {
        // 请求存储权限
        final storageGranted = await _requestStoragePermissionWithFallback();

        // 请求安装权限
        final installGranted = await _requestInstallPermission();

        _hasStoragePermission = storageGranted;
        _hasInstallPermission = installGranted;

        print('📋 权限请求结果:');
        print('  存储权限: ${storageGranted ? '已授权' : '被拒绝'}');
        print('  安装权限: ${installGranted ? '已授权' : '被拒绝'}');

        notifyListeners();

        // 如果存储权限被拒绝，建议使用系统下载器
        if (!storageGranted) {
          _useSystemDownloader = true;
          print('💡 存储权限被拒绝，将使用系统下载管理器');
        }

        return installGranted; // 安装权限是必需的
      }

      return true;
    } catch (e) {
      print('❌ 权限请求失败: $e');
      _error = '权限请求失败: $e';
      notifyListeners();
      return false;
    }
  }

  ///7. 请求存储权限（带降级处理）
  Future<bool> _requestStoragePermissionWithFallback() async {
    try {
      final androidVersion = await _getAndroidVersion();

      // Android 13+ 不需要存储权限
      if (androidVersion >= 33) {
        return true;
      }

      // Android 11-12 先尝试管理外部存储权限
      if (androidVersion >= 30) {
        final manageStatus = await Permission.manageExternalStorage.request();
        if (manageStatus.isGranted) {
          return true;
        }

        // 如果管理权限被拒绝，尝试基本存储权限
        final storageStatus = await Permission.storage.request();
        return storageStatus.isGranted;
      }

      // Android 10及以下
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    } catch (e) {
      print('❌ 存储权限请求失败: $e');
      return false;
    }
  }

  ///8. 检查应用更新
  Future<void> checkForUpdate({bool autoDownload = false}) async {
    try {
      _isCheckingUpdate = true;
      _error = null;
      notifyListeners();

      print('🔍 AppUpdateProvider: 开始检查更新');

      // 获取当前应用版本
      final currentVersionInfo = await VersionUtil.getCurrentAppVersion();
      final currentVersion = currentVersionInfo['version'] ?? '1.0.0';
      final currentBuild = currentVersionInfo['buildNumber'] ?? '1';

      _currentVersion =
          VersionUtil.formatVersionInfo(currentVersion, currentBuild);
      print('📱 当前版本: $_currentVersion');

      // 获取远程版本信息
      final apiClient =
          ApiClient(baseUrl: 'http://test.iboard.skylinedances.com');
      final response = await apiClient.getAppVersion();

      if (response['data'] == null) {
        print('❌ 获取远程版本信息失败: 响应数据为空');
        _error = '获取版本信息失败';
        _hasUpdate = false;
        _hasLocalApk = false;
        return;
      }

      final versionData = response['data'];
      final currentVersionData = versionData['currentVersion'];

      if (currentVersionData == null) {
        print('❌ 远程版本数据为空');
        _error = '远程版本数据为空';
        _hasUpdate = false;
        _hasLocalApk = false;
        return;
      }

      final remoteVersion = currentVersionData['versionNumber'] ?? '1.0.0';
      final remoteBuild = currentVersionData['buildNumber'] ?? '1';
      final downloadUrl = currentVersionData['downloadUrl'] ?? '';
      final description = currentVersionData['description'] ?? '';

      _remoteVersion =
          VersionUtil.formatVersionInfo(remoteVersion, remoteBuild);
      _remoteVersionNumber = remoteVersion;
      _remoteBuildNumber = remoteBuild;
      _updateDescription = description;
      _downloadUrl = downloadUrl;

      print('🌐 远程版本: $_remoteVersion');
      print('📝 更新描述: $description');
      print('🔗 下载链接: $downloadUrl');

      // 检查是否需要更新
      final needsUpdate = VersionUtil.needsUpdate(
          currentVersion, currentBuild, remoteVersion, remoteBuild);

      if (needsUpdate) {
        print('✅ 发现新版本，需要更新');
        _hasUpdate = true;
        // 检查是否已下载
        await _checkLocalApk();

        // 如果需要自动下载且本地没有APK
        if (autoDownload && !_hasLocalApk) {
          print('🚀 自动开始下载更新包...');
          // 延迟一点时间确保UI更新完成
          Future.delayed(Duration(milliseconds: 500), () async {
            await downloadApk();
          });
        }
      } else {
        print('✅ 当前版本已是最新版本');
        _hasUpdate = false;
        _hasLocalApk = false;
      }
    } catch (e) {
      _error = '检查更新失败: $e';
      _hasUpdate = false;
      _hasLocalApk = false;
      print('❌ AppUpdateProvider: 检查更新异常 - $e');
    } finally {
      _isCheckingUpdate = false;
      notifyListeners();
    }
  }

  ///3. 下载APK文件
  Future<void> downloadApk() async {
    if (_downloadUrl == null ||
        _remoteVersionNumber == null ||
        _remoteBuildNumber == null) {
      _error = '下载信息不完整';
      notifyListeners();
      return;
    }

    try {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadReceived = 0;
      _downloadTotal = 0;
      _error = null;
      notifyListeners();

      print('⬇️ AppUpdateProvider: 开始下载APK');

      // 使用应用缓存目录，无需存储权限
      print('📁 使用应用缓存目录下载，无需存储权限');

      // 清理旧文件以释放空间
      await cleanOldApkFiles();

      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();
      final fileName =
          'iboard_v${_remoteVersionNumber}_${_remoteBuildNumber}.apk';
      final filePath = '${downloadDir.path}/$fileName';

      print('📁 下载路径: $filePath');

      // 检查文件是否已存在
      final file = File(filePath);
      if (await file.exists()) {
        print('✅ APK文件已存在: $filePath');
        _localApkPath = filePath;
        _hasLocalApk = true;
        _downloadProgress = 100;
        _isDownloading = false;
        notifyListeners();
        return;
      }

      // 创建取消令牌
      _downloadCancelToken = CancelToken();

      // 开始下载
      await _dio.download(
        _downloadUrl!,
        filePath,
        cancelToken: _downloadCancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            _downloadReceived = received;
            _downloadTotal = total;
            final newProgress = ((received / total) * 100).round();

            // 只在进度变化且为10的倍数时输出日志，减少日志频率
            if (newProgress != _downloadProgress && newProgress % 1000 == 0) {
              print(
                  '📥 下载进度: $newProgress% (${(received / 1024 / 1024).toStringAsFixed(1)}MB/${(total / 1024 / 1024).toStringAsFixed(1)}MB)');
            }

            _downloadProgress = newProgress;
            notifyListeners();
          }
        },
      );

      // 验证文件是否下载成功
      if (await file.exists()) {
        final fileSize = await file.length();
        print('✅ APK下载成功: $filePath (${fileSize} bytes)');
        _localApkPath = filePath;
        _hasLocalApk = true;
        _downloadProgress = 100;
      } else {
        print('❌ APK文件下载失败');
        _error = '文件下载失败';
        _hasLocalApk = false;
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        print('⏹️ 下载已取消');
        _hasLocalApk = false;
      } else {
        print('❌ 下载APK失败: $e');
        _error = '下载失败: $e';
        _hasLocalApk = false;
      }
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  ///4. 取消下载
  void cancelDownload() {
    if (_isDownloading) {
      _downloadCancelToken?.cancel('用户取消下载');
      print('⏹️ AppUpdateProvider: 用户取消下载');
    }
  }

  ///5. 安装APK
  Future<void> installApk() async {
    if (_localApkPath == null) {
      _error = 'APK文件不存在';
      notifyListeners();
      return;
    }

    try {
      _isInstalling = true;
      _error = null;
      notifyListeners();

      print('📦 AppUpdateProvider: 开始安装APK');

      final file = File(_localApkPath!);
      if (!await file.exists()) {
        print('❌ APK文件不存在: $_localApkPath');
        _error = 'APK文件不存在';
        return;
      }

      // 请求安装权限
      final installPermission = await _requestInstallPermission();
      if (!installPermission) {
        print('❌ 缺少安装权限');
        _error = '缺少安装权限';
        return;
      }

      // 打开APK文件进行安装
      final result = await OpenFile.open(_localApkPath!);

      if (result.type == ResultType.done) {
        print('✅ APK安装程序已启动');
      } else {
        print('❌ 启动APK安装失败: ${result.message}');
        _error = '启动APK安装失败: ${result.message}';
      }
    } catch (e) {
      _error = '安装失败: $e';
      print('❌ AppUpdateProvider: 安装APK异常 - $e');
    } finally {
      _isInstalling = false;
      notifyListeners();
    }
  }

  ///6. 检查本地APK文件
  Future<void> _checkLocalApk() async {
    if (_remoteVersionNumber == null || _remoteBuildNumber == null) {
      _hasLocalApk = false;
      return;
    }

    try {
      final downloadDir = await _getDownloadDirectory();
      final fileName =
          'iboard_v${_remoteVersionNumber}_${_remoteBuildNumber}.apk';
      final filePath = '${downloadDir.path}/$fileName';

      final file = File(filePath);
      if (await file.exists()) {
        _localApkPath = filePath;
        _hasLocalApk = true;
        print('✅ AppUpdateProvider: 找到本地APK文件 - $filePath');
      } else {
        _hasLocalApk = false;
        print('❌ AppUpdateProvider: 本地APK文件不存在');
      }
    } catch (e) {
      _hasLocalApk = false;
      print('❌ AppUpdateProvider: 检查本地APK失败 - $e');
    }
  }

  ///7. 手动检查本地APK（用于页面刷新）
  Future<void> refreshLocalApkStatus() async {
    await _checkLocalApk();
    notifyListeners();
  }

  ///8. 清理旧APK文件并优化缓存空间
  Future<void> cleanOldApkFiles() async {
    try {
      final downloadDir = await _getDownloadDirectory();
      final files = downloadDir.listSync();
      final apkFiles = <File>[];

      // 收集所有APK文件
      for (final file in files) {
        if (file is File &&
            file.path.endsWith('.apk') &&
            file.path.contains('iboard_v')) {
          apkFiles.add(file);
        }
      }

      if (apkFiles.isEmpty) return;

      // 计算总文件大小
      int totalSize = 0;
      for (final file in apkFiles) {
        totalSize += await file.length();
      }

      print(
          '📁 缓存目录APK文件总大小: ${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB');

      // 如果缓存大小超过100MB或文件数量超过3个，进行清理
      if (totalSize > 100 * 1024 * 1024 || apkFiles.length > 3) {
        print(
            '⚠️ 缓存空间需要清理（大小: ${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB，文件数: ${apkFiles.length}）');

        // 按修改时间排序，保留最新的文件
        apkFiles.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

        // 保留最新的1个文件，删除其他
        for (int i = 1; i < apkFiles.length; i++) {
          await apkFiles[i].delete();
          print('🗑️ 删除旧APK文件: ${apkFiles[i].path}');
        }

        print('✅ 缓存清理完成，保留最新文件，删除了 ${apkFiles.length - 1} 个旧文件');
      } else {
        print(
            '✅ 缓存空间正常（${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB），无需清理');
      }
    } catch (e) {
      print('❌ AppUpdateProvider: 清理APK文件失败 - $e');
    }
  }

  ///9. 请求存储权限
  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
    return true;
  }

  ///10. 请求安装权限
  Future<bool> _requestInstallPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      return status.isGranted;
    }
    return true;
  }

  ///10. 使用系统下载管理器下载APK
  Future<void> downloadWithSystemDownloader() async {
    try {
      print('📱 使用系统下载管理器下载APK');

      // 使用系统浏览器打开下载链接
      await _openUrlInBrowser(_downloadUrl!);

      _downloadProgress = 0;
      _isDownloading = false;
      _useSystemDownloader = true;

      // 提示用户手动安装
      _error = null;
      print('💡 已使用系统下载管理器开始下载，请在下载完成后手动安装APK');

      // 定期检查下载文件夹中是否有APK文件
      _startCheckingDownloadFolder();

      notifyListeners();
    } catch (e) {
      print('❌ 系统下载管理器启动失败: $e');
      _error = '启动系统下载失败: $e';
      _isDownloading = false;
      notifyListeners();
    }
  }

  ///11. 在浏览器中打开URL
  Future<void> _openUrlInBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      final canLaunch = await canLaunchUrl(uri);

      if (canLaunch) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, // 强制使用外部浏览器
        );
        print('✅ 已在浏览器中打开下载链接');
      } else {
        throw Exception('无法启动浏览器');
      }
    } catch (e) {
      print('❌ 打开浏览器失败: $e');
      // 降级方案：显示下载链接让用户手动复制
      _error = '无法自动打开浏览器，请手动复制以下链接下载：\n$url';
      throw e;
    }
  }

  ///12. 定期检查下载文件夹
  void _startCheckingDownloadFolder() {
    Timer.periodic(Duration(seconds: 5), (timer) async {
      try {
        final found = await _checkDownloadFolderForApk();
        if (found || !_useSystemDownloader) {
          timer.cancel();
        }
      } catch (e) {
        print('检查下载文件夹失败: $e');
      }
    });
  }

  ///13. 检查系统下载文件夹中的APK
  Future<bool> _checkDownloadFolderForApk() async {
    try {
      // 检查系统下载文件夹
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!await downloadDir.exists()) {
        return false;
      }

      final files = downloadDir.listSync();
      final fileName =
          'iboard_v${_remoteVersionNumber}_${_remoteBuildNumber}.apk';

      for (final file in files) {
        if (file is File && file.path.contains(fileName)) {
          print('✅ 在系统下载文件夹找到APK: ${file.path}');
          _localApkPath = file.path;
          _hasLocalApk = true;
          _downloadProgress = 100;
          notifyListeners();
          return true;
        }
      }

      return false;
    } catch (e) {
      print('检查系统下载文件夹失败: $e');
      return false;
    }
  }

  ///14. 获取下载目录 - 使用应用缓存目录，无需存储权限
  Future<Directory> _getDownloadDirectory() async {
    try {
      // 优先使用应用缓存目录，不需要任何权限
      final cacheDir = await getTemporaryDirectory();
      final downloadDir = Directory('${cacheDir.path}/apk_updates');

      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
        print('📁 创建APK缓存目录: ${downloadDir.path}');
      }

      return downloadDir;
    } catch (e) {
      print('❌ 获取缓存目录失败，尝试应用文档目录: $e');

      // 降级方案：使用应用文档目录
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${docDir.path}/apk_updates');

        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }

        return downloadDir;
      } catch (e2) {
        print('❌ 获取应用文档目录也失败: $e2');
        rethrow;
      }
    }
  }

  ///12. 重置状态
  void resetState() {
    _currentVersion = null;
    _remoteVersion = null;
    _remoteVersionNumber = null;
    _remoteBuildNumber = null;
    _updateDescription = null;
    _downloadUrl = null;
    _isCheckingUpdate = false;
    _isDownloading = false;
    _isInstalling = false;
    _hasUpdate = false;
    _hasLocalApk = false;
    _localApkPath = null;
    _error = null;
    _downloadProgress = 0;
    _downloadReceived = 0;
    _downloadTotal = 0;
    notifyListeners();
  }

  ///13. 清除错误信息
  void clearError() {
    _error = null;
    notifyListeners();
  }

  ///14. 格式化文件大小
  String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  ///15. 获取下载进度文本
  String get downloadProgressText {
    if (_downloadTotal > 0) {
      return '${formatFileSize(_downloadReceived)} / ${formatFileSize(_downloadTotal)}';
    }
    return '$_downloadProgress%';
  }

  ///16. 启动定期检查更新 - 可选功能
  void startPeriodicUpdateCheck(
      {Duration interval = const Duration(hours: 6)}) {
    stopPeriodicUpdateCheck(); // 先停止现有的定时器

    print('🔄 启动定期版本检查，间隔: ${interval.inHours}小时');

    _updateCheckTimer = Timer.periodic(interval, (timer) async {
      try {
        print('🔄 定期检查版本更新...');
        await checkForUpdate();
      } catch (e) {
        print('❌ 定期检查更新失败: $e');
      }
    });
  }

  ///17. 停止定期检查更新
  void stopPeriodicUpdateCheck() {
    if (_updateCheckTimer != null) {
      _updateCheckTimer!.cancel();
      _updateCheckTimer = null;
      print('⏹️ 已停止定期版本检查');
    }
  }

  ///18. 销毁时清理资源
  @override
  void dispose() {
    stopPeriodicUpdateCheck();
    _downloadCancelToken?.cancel();
    super.dispose();
  }
}
