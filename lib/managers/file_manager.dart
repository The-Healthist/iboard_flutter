import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:iboard_app/models/file_model.dart'; // Changed import
import 'package:logger/logger.dart';

class FileManager {
  final Dio _dio;
  final Logger _logger = Logger();
  static const String _cacheSubDir = 'file_cache';

  FileManager({Dio? dio}) : _dio = dio ?? Dio();

  Future<String> _getCacheDirectoryPath() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String cachePath = p.join(appDir.path, _cacheSubDir);
    final Directory cacheDir = Directory(cachePath);
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
      // _logger.i('Created cache directory: $cachePath');
    }
    return cachePath;
  }

  Future<File?> getFile(FileModel fileModel) async {
    try {
      final String cacheDirPath = await _getCacheDirectoryPath();
      // Use MD5 as filename to ensure uniqueness and integrity if needed, or just use the original filename from URL
      // For simplicity, let's use the last part of the URL as a potential filename and append md5 for uniqueness.
      final String fileNameFromUrl = p.basename(Uri.parse(fileModel.url).path);
      final String localFileName = '${fileModel.md5}_$fileNameFromUrl';
      final String localFilePath = p.join(cacheDirPath, localFileName);

      final File localFile = File(localFilePath);

      if (await localFile.exists()) {
        // _logger.i('File found in cache: $localFilePath');
        // Optionally, add a check here to verify file integrity using MD5 if required.
        fileModel.localFilePath = localFilePath;
        return localFile;
      }

      // _logger.i('Downloading file from ${fileModel.url} to $localFilePath');
      await _dio.download(fileModel.url, localFilePath);
      // _logger.i('File downloaded successfully: $localFilePath');
      fileModel.localFilePath = localFilePath;
      return localFile;
    } catch (e, stackTrace) {
      _logger.e('Error in getFile for ${fileModel.url}',
          error: e, stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> clearCache() async {
    try {
      final String cacheDirPath = await _getCacheDirectoryPath();
      final Directory cacheDir = Directory(cacheDirPath);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        // _logger.i('Cache cleared: $cacheDirPath');
        await cacheDir.create(recursive: true); // Recreate after deleting
      }
    } catch (e, stackTrace) {
      _logger.e('Error clearing cache', error: e, stackTrace: stackTrace);
    }
  }

  Future<double> getCacheSize() async {
    try {
      final String cacheDirPath = await _getCacheDirectoryPath();
      final Directory cacheDir = Directory(cacheDirPath);
      if (!await cacheDir.exists()) {
        return 0.0;
      }

      int totalSize = 0;
      final List<FileSystemEntity> entities = await cacheDir.list().toList();
      for (FileSystemEntity entity in entities) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize / (1024 * 1024); // Size in MB
    } catch (e, stackTrace) {
      _logger.e('Error getting cache size', error: e, stackTrace: stackTrace);
      return 0.0;
    }
  }
}
