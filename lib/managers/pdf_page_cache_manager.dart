import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

class PdfPageCacheResult {
  final List<String> pagePaths;
  final bool fromCache;

  const PdfPageCacheResult({
    required this.pagePaths,
    required this.fromCache,
  });
}

class PdfPageCacheManager {
  PdfPageCacheManager._();

  static final PdfPageCacheManager instance = PdfPageCacheManager._();
  static final Map<String, Future<PdfPageCacheResult>> _activeJobs = {};
  static Future<void> _renderQueue = Future<void>.value();

  static const String _cacheSubDir = 'pdf_page_cache';
  static const String _completeMarkerName = 'complete.txt';

  Future<PdfPageCacheResult> getPageImages({
    required File pdfFile,
    required String cacheKey,
    double dpi = 120,
  }) async {
    final String safeKey = _sanitizeCacheKey(cacheKey);
    final String jobKey = '$safeKey:${dpi.round()}';
    final Directory cacheDir = await _getCacheDirectory(safeKey, dpi);

    final cachedPages = await _readCachedPages(cacheDir);
    if (cachedPages.isNotEmpty) {
      return PdfPageCacheResult(pagePaths: cachedPages, fromCache: true);
    }

    final activeJob = _activeJobs[jobKey];
    if (activeJob != null) {
      return activeJob;
    }

    final Future<PdfPageCacheResult> job = _enqueueRender(
      pdfFile: pdfFile,
      cacheDir: cacheDir,
      dpi: dpi,
    );
    _activeJobs[jobKey] = job;

    try {
      return await job;
    } finally {
      if (identical(_activeJobs[jobKey], job)) {
        _activeJobs.remove(jobKey);
      }
    }
  }

  Future<PdfPageCacheResult> _enqueueRender({
    required File pdfFile,
    required Directory cacheDir,
    required double dpi,
  }) {
    final Future<PdfPageCacheResult> job = _renderQueue.then(
      (_) => _renderPdfPages(pdfFile: pdfFile, cacheDir: cacheDir, dpi: dpi),
      onError: (_) =>
          _renderPdfPages(pdfFile: pdfFile, cacheDir: cacheDir, dpi: dpi),
    );

    _renderQueue = job.then<void>((_) {}, onError: (_) {});
    return job;
  }

  Future<Directory> _getCacheDirectory(String safeKey, double dpi) async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final String dirPath = p.join(
      appDir.path,
      _cacheSubDir,
      '${safeKey}_dpi_${dpi.round()}',
    );
    final Directory dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<String>> _readCachedPages(Directory cacheDir) async {
    final marker = File(p.join(cacheDir.path, _completeMarkerName));
    if (!await marker.exists()) {
      return const [];
    }

    final expectedPageCount =
        int.tryParse((await marker.readAsString()).trim()) ?? 0;
    if (expectedPageCount <= 0) {
      return const [];
    }

    final List<String> pagePaths = [];
    for (int index = 0; index < expectedPageCount; index++) {
      final pageFile = File(p.join(cacheDir.path, _pageFileName(index)));
      if (!await pageFile.exists()) {
        return const [];
      }
      pagePaths.add(pageFile.path);
    }
    return pagePaths;
  }

  Future<PdfPageCacheResult> _renderPdfPages({
    required File pdfFile,
    required Directory cacheDir,
    required double dpi,
  }) async {
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
    await cacheDir.create(recursive: true);

    final Uint8List pdfBytes = await pdfFile.readAsBytes();
    final List<String> pagePaths = [];

    var pageIndex = 0;
    await for (final page in Printing.raster(pdfBytes, dpi: dpi)) {
      final Uint8List pngBytes = await page.toPng();
      final pageFile = File(p.join(cacheDir.path, _pageFileName(pageIndex)));
      await pageFile.writeAsBytes(pngBytes, flush: true);
      pagePaths.add(pageFile.path);
      pageIndex++;
    }

    if (pagePaths.isEmpty) {
      throw StateError('PDF raster returned no pages.');
    }

    final marker = File(p.join(cacheDir.path, _completeMarkerName));
    await marker.writeAsString(pagePaths.length.toString(), flush: true);

    return PdfPageCacheResult(pagePaths: pagePaths, fromCache: false);
  }

  String _sanitizeCacheKey(String key) {
    final sanitized = key.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]+'), '_');
    if (sanitized.length <= 96) {
      return sanitized;
    }
    return sanitized.substring(0, 96);
  }

  String _pageFileName(int index) {
    return 'page_${index.toString().padLeft(3, '0')}.png';
  }
}
