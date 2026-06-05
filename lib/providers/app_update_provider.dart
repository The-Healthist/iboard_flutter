import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../http/api_client.dart';
import '../utils/version_util.dart';
import 'package:logger/logger.dart';

///1. 应用更新状态管理Provider - 整合所有更新功能
class AppUpdateProvider with ChangeNotifier {
  final Logger _logger = Logger();
  final Dio _dio = Dio();
  final Future<Map<String, dynamic>> Function()? _appVersionLoader;
  final Future<Map<String, String>> Function()? _currentVersionLoader;
  CancelToken? _downloadCancelToken;
  Timer? _updateCheckTimer;

  // 当前版本信息
  String? _currentVersion;
  String? get currentVersion => _currentVersion;

  String? _currentVersionDescription; // 添加当前版本的描述字段
  String? get currentVersionDescription => _currentVersionDescription;

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

  // 节流控制
  DateTime? _lastCheckTime;
  DateTime? _lastInstallTime;
  static const Duration _checkThrottleDuration =
      Duration(seconds: 3); // 检查更新节流3秒
  static const Duration _installThrottleDuration =
      Duration(seconds: 5); // 安装节流5秒

  AppUpdateProvider({
    Future<Map<String, dynamic>> Function()? appVersionLoader,
    Future<Map<String, String>> Function()? currentVersionLoader,
  })  : _appVersionLoader = appVersionLoader,
        _currentVersionLoader = currentVersionLoader;

  ///2.1. 检查是否可以进行更新检查 (节流控制)
  bool get canCheckUpdate {
    if (_isCheckingUpdate) return false;
    if (_lastCheckTime == null) return true;
    return DateTime.now().difference(_lastCheckTime!) > _checkThrottleDuration;
  }

  ///2.2. 检查是否可以进行安装 (节流控制)
  bool get canInstall {
    if (_isInstalling) return false;
    if (_lastInstallTime == null) return true;
    return DateTime.now().difference(_lastInstallTime!) >
        _installThrottleDuration;
  }

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

        _logger.i(' 權限狀態檢查完成:');
        _logger.i('  存儲權限: ${_hasStoragePermission ? '已授權' : '未授權'}');
        _logger.i('  安裝權限: ${_hasInstallPermission ? '已授權' : '未授權'}');

        notifyListeners();
      } else {
        _hasStoragePermission = true;
        _hasInstallPermission = true;
      }
    } catch (e) {
      _logger.e(' 權限狀態檢查失敗: $e');
    }
  }

  ///4. 检查存储权限（适配Android不同版本）
  Future<bool> _checkStoragePermission() async {
    if (!Platform.isAndroid) return true;

    try {
      // Android 13+ (API 33+) 不需要存储权限
      final androidInfo = await _getAndroidVersion();
      if (androidInfo >= 33) {
        _logger.i(' Android 13+，不需要存儲權限');
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
      _logger.e(' 檢查存儲權限失敗: $e');
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
      _logger.i(' 開始請求應用更新所需權限...');

      if (Platform.isAndroid) {
        // 请求存储权限
        final storageGranted = await _requestStoragePermissionWithFallback();

        // 请求安装权限
        final installGranted = await _requestInstallPermission();

        _hasStoragePermission = storageGranted;
        _hasInstallPermission = installGranted;

        _logger.i(' 權限請求結果:');
        _logger.i('  存儲權限: ${storageGranted ? '已授權' : '被拒絕'}');
        _logger.i('  安裝權限: ${installGranted ? '已授權' : '被拒絕'}');

        notifyListeners();

        // 如果存储权限被拒绝，建议使用系统下载器
        if (!storageGranted) {
          _useSystemDownloader = true;
          _logger.i(' 存儲權限被拒絕，將使用系統下載管理器');
        }

        return installGranted; // 安装权限是必需的
      }

      return true;
    } catch (e) {
      _logger.e(' 權限請求失敗: $e');
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
      _logger.e(' 存儲權限請求失敗: $e');
      return false;
    }
  }

  ///7. 加载本地保存的版本描述
  Future<void> _loadCurrentVersionDescription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentVersionDescription = prefs.getString('app_version_description');
    } catch (e) {
      _logger.e(' 加载本地版本描述失败: $e');
      _currentVersionDescription = null;
    }
  }

  ///7a. 保存版本描述到本地
  Future<void> _saveCurrentVersionDescription(String description) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_version_description', description);
      _currentVersionDescription = description;
    } catch (e) {
      _logger.e(' 保存版本描述失败: $e');
    }
  }

  ///7b. 检查是否需要更新（增强版 - 考虑description）
  bool _needsUpdateWithDescription(
    String currentVersion,
    String currentBuild,
    String? currentDescription,
    String remoteVersion,
    String remoteBuild,
    String remoteDescription,
  ) {
    // 首先使用原有的版本号和构建号比较逻辑
    final versionNeedsUpdate = VersionUtil.needsUpdate(
      currentVersion,
      currentBuild,
      remoteVersion,
      remoteBuild,
    );

    // 如果版本需要更新，直接返回true
    if (versionNeedsUpdate) {
      return true;
    }

    // 如果版本号相同，检查description是否不同
    if (currentVersion == remoteVersion && currentBuild == remoteBuild) {
      final descriptionChanged =
          (currentDescription ?? '') != remoteDescription;
      if (descriptionChanged) {
        return true;
      }
    }

    return false;
  }

  ///8. 检查应用更新
  Future<void> checkForUpdate({bool autoDownload = false}) async {
    // 节流检查
    if (!canCheckUpdate) {
      _error = '操作频繁，请稍后再试';
      notifyListeners();
      return;
    }

    try {
      _isCheckingUpdate = true;
      _lastCheckTime = DateTime.now(); // 记录操作时间
      _error = null;
      notifyListeners();

      // 获取当前应用版本
      final currentVersionInfo = _currentVersionLoader == null
          ? await VersionUtil.getCurrentAppVersion()
          : await _currentVersionLoader();
      final currentVersion =
          currentVersionInfo['version']?.toString() ?? '1.0.0';
      final currentBuild = currentVersionInfo['buildNumber']?.toString() ?? '1';

      _currentVersion =
          VersionUtil.formatVersionInfo(currentVersion, currentBuild);

      // 获取远程版本信息
      final response = _appVersionLoader == null
          ? await ApiClient(baseUrl: 'http://39.108.49.167:10031')
              .getAppVersion()
          : await _appVersionLoader();

      final versionData = _nullableMap(response['data']);
      if (versionData == null) {
        _error = '获取版本信息失败';
        _hasUpdate = false;
        _hasLocalApk = false;
        return;
      }

      final currentVersionData = _nullableMap(versionData['currentVersion']);
      if (currentVersionData == null) {
        _error = '远程版本数据为空';
        _hasUpdate = false;
        _hasLocalApk = false;
        return;
      }

      final remoteVersion =
          currentVersionData['versionNumber']?.toString() ?? '1.0.0';
      final remoteBuild = currentVersionData['buildNumber']?.toString() ?? '1';
      final downloadUrl = currentVersionData['downloadUrl']?.toString() ?? '';
      final description = currentVersionData['description']?.toString() ?? '';

      _remoteVersion =
          VersionUtil.formatVersionInfo(remoteVersion, remoteBuild);
      _remoteVersionNumber = remoteVersion;
      _remoteBuildNumber = remoteBuild;
      _updateDescription = description;
      _downloadUrl = downloadUrl;

      // 加载当前版本的描述（如果存在）
      await _loadCurrentVersionDescription();

      // 使用增强的更新检查逻辑（同时考虑版本和描述）
      final needsUpdate = _needsUpdateWithDescription(
        currentVersion,
        currentBuild,
        _currentVersionDescription,
        remoteVersion,
        remoteBuild,
        description,
      );

      if (needsUpdate) {
        _hasUpdate = true;
        // 检查是否已下载
        await _checkLocalApk();

        // 如果需要自动下载且本地没有APK
        if (autoDownload && !_hasLocalApk) {
          // 延迟一点时间确保UI更新完成
          Future.delayed(const Duration(milliseconds: 500), () async {
            await downloadApk();
          });
        }
      } else {
        _hasUpdate = false;
        _hasLocalApk = false;
      }
    } catch (e) {
      _error = '检查更新失败: $e';
      _hasUpdate = false;
      _hasLocalApk = false;
      _logger.e(' AppUpdateProvider: 檢查更新異常 - $e');
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

      _logger.i(' AppUpdateProvider: 開始下載APK');

      // 使用应用缓存目录，无需存储权限
      _logger.i(' 使用應用緩存目錄下載，無需存儲權限');

      // 清理旧文件以释放空间
      await cleanOldApkFiles();

      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();

      // 生成包含description哈希的文件名
      final descriptionHash = _updateDescription?.hashCode.toString() ?? '0';
      final fileName =
          'iboard_v${_remoteVersionNumber}_${_remoteBuildNumber}_$descriptionHash.apk';
      final filePath = '${downloadDir.path}/$fileName';

      _logger.i(' 下載路徑: $filePath');

      // 检查文件是否已存在
      final file = File(filePath);
      if (await file.exists()) {
        _logger.i(' APK文件已存在: $filePath');
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
              _logger.i(
                  ' 下載進度: $newProgress% (${(received / 1024 / 1024).toStringAsFixed(1)}MB/${(total / 1024 / 1024).toStringAsFixed(1)}MB)');
            }

            _downloadProgress = newProgress;
            notifyListeners();
          }
        },
      );

      // 验证文件是否下载成功
      if (await file.exists()) {
        final fileSize = await file.length();
        _logger.i(' APK下載成功: $filePath ($fileSize bytes)');
        _localApkPath = filePath;
        _hasLocalApk = true;
        _downloadProgress = 100;
      } else {
        _logger.e(' APK文件下載失敗');
        _error = '文件下载失败';
        _hasLocalApk = false;
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _logger.i(' 下載已取消');
        _hasLocalApk = false;
      } else {
        _logger.e(' 下載APK失敗: $e');
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
      _logger.i(' AppUpdateProvider: 用戶取消下載');
    }
  }

  ///5. 安装APK
  Future<void> installApk() async {
    if (_localApkPath == null) {
      _error = 'APK文件不存在';
      notifyListeners();
      return;
    }

    // 节流检查
    if (!canInstall) {
      _logger.i(' 安装操作频繁，请稍后再试');
      _error = '操作频繁，请稍后再试';
      notifyListeners();
      return;
    }

    try {
      _isInstalling = true;
      _lastInstallTime = DateTime.now(); // 记录操作时间
      _error = null;
      notifyListeners();

      _logger.i(' AppUpdateProvider: 開始安裝APK');

      final file = File(_localApkPath!);
      if (!await file.exists()) {
        _logger.e(' APK文件不存在: $_localApkPath');
        _error = 'APK文件不存在';
        return;
      }

      // 请求安装权限
      final installPermission = await _requestInstallPermission();
      if (!installPermission) {
        _logger.e(' 缺少安裝權限');
        _error = '缺少安装权限';
        return;
      }

      // 打开APK文件进行安装
      final result = await OpenFile.open(_localApkPath!);

      if (result.type == ResultType.done) {
        _logger.i(' APK安裝程序已啟動');

        // 安装程序启动成功后，保存当前的description以备下次比较
        if (_updateDescription != null) {
          await _saveCurrentVersionDescription(_updateDescription!);
          _logger.i(' 已保存当前版本描述信息');
        }
      } else {
        _logger.e(' 啟動APK安裝失敗: ${result.message}');
        _error = '启动APK安装失败: ${result.message}';
      }
    } catch (e) {
      _error = '安装失败: $e';
      _logger.e(' AppUpdateProvider: 安裝APK異常 - $e');
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

      // 生成包含description哈希的文件名，确保description变化时重新下载
      final descriptionHash = _updateDescription?.hashCode.toString() ?? '0';
      final fileName =
          'iboard_v${_remoteVersionNumber}_${_remoteBuildNumber}_$descriptionHash.apk';
      final filePath = '${downloadDir.path}/$fileName';

      final file = File(filePath);
      if (await file.exists()) {
        _localApkPath = filePath;
        _hasLocalApk = true;
      } else {
        _hasLocalApk = false;
        // 清理可能存在的旧版本APK文件
        await _cleanOldVersionApkFiles();
      }
    } catch (e) {
      _hasLocalApk = false;
      _logger.e(' AppUpdateProvider: 檢查本地APK失敗 - $e');
    }
  }

  ///6a. 清理特定版本的旧APK文件
  Future<void> _cleanOldVersionApkFiles() async {
    try {
      final downloadDir = await _getDownloadDirectory();
      final files = downloadDir.listSync();

      // 查找当前版本的旧APK文件（不同description哈希）
      final currentVersionPrefix =
          'iboard_v${_remoteVersionNumber}_$_remoteBuildNumber';

      for (final file in files) {
        if (file is File &&
            file.path.contains(currentVersionPrefix) &&
            file.path.endsWith('.apk')) {
          try {
            await file.delete();
            _logger.i(' 已清理旧版本APK文件: ${file.path}');
          } catch (e) {
            _logger.w(' 清理APK文件失败: ${file.path} - $e');
          }
        }
      }
    } catch (e) {
      _logger.e(' 清理旧版本APK文件失败: $e');
    }
  }

  ///7. 手动检查本地APK（用于頁面刷新）
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

      _logger.i(
          ' 緩存目錄APK文件總大小: ${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB');

      // 如果缓存大小超过100MB或文件数量超过3个，进行清理
      if (totalSize > 100 * 1024 * 1024 || apkFiles.length > 3) {
        _logger.i(
            ' 緩存空間需要清理（大小: ${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB，文件數: ${apkFiles.length}）');

        // 按修改时间排序，保留最新的文件
        apkFiles.sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

        // 保留最新的1个文件，删除其他
        for (int i = 1; i < apkFiles.length; i++) {
          await apkFiles[i].delete();
          _logger.i(' 刪除舊APK文件: ${apkFiles[i].path}');
        }

        _logger.i(' 緩存清理完成，保留最新文件，刪除了 ${apkFiles.length - 1} 個舊文件');
      } else {
        _logger.i(
            ' 緩存空間正常（${(totalSize / 1024 / 1024).toStringAsFixed(2)}MB），無需清理');
      }
    } catch (e) {
      _logger.e(' AppUpdateProvider: 清理APK文件失敗 - $e');
    }
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
      _logger.i(' 使用系統下載管理器下載APK');

      // 使用系统浏览器打开下载鏈接
      await _openUrlInBrowser(_downloadUrl!);

      _downloadProgress = 0;
      _isDownloading = false;
      _useSystemDownloader = true;

      // 提示用户手动安装
      _error = null;
      _logger.i(' 已使用系統下載管理器開始下載，請在下載完成後手動安裝APK');

      // 定期检查下载文件夹中是否有APK文件
      _startCheckingDownloadFolder();

      notifyListeners();
    } catch (e) {
      _logger.e(' 系統下載管理器啟動失敗: $e');
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
        _logger.i(' 已在瀏覽器中打開下載鏈接');
      } else {
        throw Exception('无法启动浏览器');
      }
    } catch (e) {
      _logger.e(' 打開瀏覽器失敗: $e');
      // 降级方案：显示下载鏈接让用户手动复制
      _error = '无法自动打开浏览器，请手动复制以下鏈接下载：\n$url';
      rethrow;
    }
  }

  ///12. 定期检查下载文件夹
  void _startCheckingDownloadFolder() {
    Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        final found = await _checkDownloadFolderForApk();
        if (found || !_useSystemDownloader) {
          timer.cancel();
        }
      } catch (e) {
        _logger.e('檢查下載文件夾失敗: $e');
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
          'iboard_v${_remoteVersionNumber}_$_remoteBuildNumber.apk';

      for (final file in files) {
        if (file is File && file.path.contains(fileName)) {
          _logger.i(' 在系統下載文件夾找到APK: ${file.path}');
          _localApkPath = file.path;
          _hasLocalApk = true;
          _downloadProgress = 100;
          notifyListeners();
          return true;
        }
      }

      return false;
    } catch (e) {
      _logger.e('檢查系統下載文件夾失敗: $e');
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
        _logger.i(' 創建APK緩存目錄: ${downloadDir.path}');
      }

      return downloadDir;
    } catch (e) {
      _logger.e(' 獲取緩存目錄失敗，嘗試應用文檔目錄: $e');

      // 降级方案：使用应用文档目录
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final downloadDir = Directory('${docDir.path}/apk_updates');

        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }

        return downloadDir;
      } catch (e2) {
        _logger.e(' 獲取應用文檔目錄也失敗: $e2');
        rethrow;
      }
    }
  }

  ///12. 重置状态
  void resetState() {
    _currentVersion = null;
    _currentVersionDescription = null; // 添加描述重置
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

    _logger.i(' 啟動定期版本檢查，間隔: ${interval.inHours}小時');

    _updateCheckTimer = Timer.periodic(interval, (timer) async {
      try {
        _logger.i(' 定期檢查版本更新...');
        await checkForUpdate();
      } catch (e) {
        _logger.e(' 定期檢查更新失敗: $e');
      }
    });
  }

  ///17. 停止定期检查更新
  void stopPeriodicUpdateCheck() {
    if (_updateCheckTimer != null) {
      _updateCheckTimer!.cancel();
      _updateCheckTimer = null;
      _logger.i(' 已停止定期版本檢查');
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

Map<String, dynamic>? _nullableMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}
