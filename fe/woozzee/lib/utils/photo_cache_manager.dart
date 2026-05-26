// photo_cache_manager.dart
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class PhotoCacheManager {
  static final PhotoCacheManager _instance = PhotoCacheManager._internal();
  factory PhotoCacheManager() => _instance;
  PhotoCacheManager._internal();

  static const String _cacheFolderName = 'cache_woozzee_wb';
  static const String _cacheInfoKey = 'photo_cache_info';

  Directory? _cacheDirectory;
  Map<String, dynamic> _cacheInfo = {};

  // Кэш в памяти для быстрого доступа
  final Map<String, List<File>> _memoryCache = {};

  Future<void> initialize() async {
    if (_cacheDirectory != null) return;

    try {
      // Получаем папку Downloads
      final downloadsDirectory = await getDownloadsDirectory();
      if (downloadsDirectory == null) {
        throw Exception('Не удалось получить путь к папке Downloads');
      }

      // Используем path.join для корректного пути на всех платформах
      _cacheDirectory = Directory(path.join(downloadsDirectory.path, _cacheFolderName));
      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
        print('✅ Папка кэша создана: ${_cacheDirectory!.path}');
      }

      // Загружаем информацию о кэше
      await _loadCacheInfo();
      print('✅ Менеджер кэша фото инициализирован');
    } catch (e) {
      print('❌ Ошибка инициализации кэша фото: $e');
      rethrow;
    }
  }

  Future<void> _loadCacheInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final infoJson = prefs.getString(_cacheInfoKey);

      if (infoJson != null) {
        _cacheInfo = json.decode(infoJson);
      } else {
        _cacheInfo = {
          'totalFiles': 0,
          'totalSize': 0,
          'lastCleanup': DateTime.now().toIso8601String(),
          'cacheStats': {},
        };
      }
    } catch (e) {
      print('⚠️ Ошибка загрузки информации о кэше: $e');
      _cacheInfo = {
        'totalFiles': 0,
        'totalSize': 0,
        'lastCleanup': DateTime.now().toIso8601String(),
        'cacheStats': {},
      };
    }
  }

  Future<void> _saveCacheInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheInfoKey, json.encode(_cacheInfo));
    } catch (e) {
      print('⚠️ Ошибка сохранения информации о кэше: $e');
    }
  }

  String _getPhotoFileName(int nmId, int index) {
    return '${nmId}_${index}.jpg';
  }

  String _getPhotoFilePath(int nmId, int index) {
    final fileName = _getPhotoFileName(nmId, index);
    // Используем path.join для корректного пути на всех платформах
    return path.join(_cacheDirectory!.path, fileName);
  }

  Future<bool> isPhotoCached(int nmId, int index) async {
    try {
      final filePath = _getPhotoFilePath(nmId, index);
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  Future<File?> getPhotoFile(int nmId, int index) async {
    try {
      final filePath = _getPhotoFilePath(nmId, index);
      final file = File(filePath);

      if (await file.exists()) {
        return file;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> cachePhoto(int nmId, int index, String imageUrl) async {
    try {
      print('🔄 Кэширование фото: nmId=$nmId, index=$index');

      // Загружаем изображение
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Ошибка загрузки: ${response.statusCode}');
      }

      // Сохраняем файл
      final file = File(_getPhotoFilePath(nmId, index));
      await file.writeAsBytes(response.bodyBytes);

      // Обновляем информацию о кэше
      await _updateCacheInfo(nmId, index, response.bodyBytes.length);

      // Добавляем в память
      final cacheKey = '$nmId';
      if (!_memoryCache.containsKey(cacheKey)) {
        _memoryCache[cacheKey] = [];
      }
      _memoryCache[cacheKey]!.add(file);

      print('✅ Фото закэшировано: ${file.path}');
    } catch (e) {
      print('❌ Ошибка кэширования фото: $e');
      rethrow;
    }
  }

  Future<void> _updateCacheInfo(int nmId, int index, int fileSize) async {
    final nmIdStr = nmId.toString();

    if (!_cacheInfo.containsKey('cacheStats')) {
      _cacheInfo['cacheStats'] = {};
    }

    if (!_cacheInfo['cacheStats'].containsKey(nmIdStr)) {
      _cacheInfo['cacheStats'][nmIdStr] = {
        'photoCount': 0,
        'totalSize': 0,
        'lastAccess': DateTime.now().toIso8601String(),
      };
    }

    _cacheInfo['cacheStats'][nmIdStr]['photoCount'] += 1;
    _cacheInfo['cacheStats'][nmIdStr]['totalSize'] += fileSize;
    _cacheInfo['cacheStats'][nmIdStr]['lastAccess'] = DateTime.now().toIso8601String();

    _cacheInfo['totalFiles'] = (_cacheInfo['totalFiles'] ?? 0) + 1;
    _cacheInfo['totalSize'] = (_cacheInfo['totalSize'] ?? 0) + fileSize;

    await _saveCacheInfo();
  }

  Future<void> preloadProductPhotos(int nmId, List<String> imageUrls) async {
    try {
      print('🔄 Предзагрузка фото для товара: $nmId');

      // Проверяем, закэшированы ли уже все фото
      int cachedCount = 0;
      for (int i = 0; i < imageUrls.length; i++) {
        if (await isPhotoCached(nmId, i)) {
          cachedCount++;
        }
      }

      // Если все фото уже в кэше
      if (cachedCount == imageUrls.length) {
        print('ℹ️ Все $cachedCount фото уже в кэше для товара $nmId');
        return;
      }

      print('ℹ️ $cachedCount из ${imageUrls.length} фото уже в кэше для товара $nmId');

      // Загружаем отсутствующие фото параллельно
      final futures = <Future>[];

      for (int i = 0; i < imageUrls.length; i++) {
        final imageUrl = imageUrls[i];

        // Проверяем, есть ли уже в кэше
        final isCached = await isPhotoCached(nmId, i);
        if (!isCached) {
          futures.add(cachePhoto(nmId, i, imageUrl));
        }
      }

      if (futures.isNotEmpty) {
        await Future.wait(futures);
        print('✅ Предзагрузка завершена для товара $nmId');
      }
    } catch (e) {
      print('⚠️ Ошибка предзагрузки: $e');
    }
  }

  Future<void> clearCacheForProduct(int nmId) async {
    try {
      print('🗑️ Очистка кэша для товара: $nmId');

      final nmIdStr = nmId.toString();
      final cacheStats = _cacheInfo['cacheStats'] ?? {};

      if (cacheStats.containsKey(nmIdStr)) {
        final productStats = cacheStats[nmIdStr];
        final productSize = productStats['totalSize'] ?? 0;
        final productCount = productStats['photoCount'] ?? 0;

        // Удаляем файлы
        for (int i = 0; i < productCount; i++) {
          final filePath = _getPhotoFilePath(nmId, i);
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        }

        // Обновляем статистику
        _cacheInfo['totalFiles'] = (_cacheInfo['totalFiles'] ?? 0) - productCount;
        _cacheInfo['totalSize'] = (_cacheInfo['totalSize'] ?? 0) - productSize;
        cacheStats.remove(nmIdStr);

        // Удаляем из памяти
        _memoryCache.remove(nmIdStr);

        await _saveCacheInfo();
        print('✅ Кэш очищен для товара $nmId');
      }
    } catch (e) {
      print('❌ Ошибка очистки кэша: $e');
    }
  }

  Future<void> clearAllCache() async {
    try {
      print('🗑️ Очистка всего кэша...');

      if (await _cacheDirectory!.exists()) {
        // Удаляем все файлы
        await _cacheDirectory!.delete(recursive: true);
        await _cacheDirectory!.create(recursive: true);

        // Сбрасываем статистику
        _cacheInfo = {
          'totalFiles': 0,
          'totalSize': 0,
          'lastCleanup': DateTime.now().toIso8601String(),
          'cacheStats': {},
        };

        // Очищаем память
        _memoryCache.clear();

        await _saveCacheInfo();
        print('✅ Весь кэш очищен');
      }
    } catch (e) {
      print('❌ Ошибка очистки всего кэша: $e');
    }
  }

  Future<Map<String, dynamic>> getCacheInfo() async {
    // Обновляем статистику из файловой системы
    await _refreshCacheInfoFromDisk();

    return {
      'totalFiles': _cacheInfo['totalFiles'] ?? 0,
      'totalSize': _cacheInfo['totalSize'] ?? 0,
      'cacheStats': _cacheInfo['cacheStats'] ?? {},
      'cachePath': _cacheDirectory?.path,
    };
  }

  Future<void> _refreshCacheInfoFromDisk() async {
    try {
      if (_cacheDirectory == null || !await _cacheDirectory!.exists()) return;

      final files = await _cacheDirectory!.list().toList();
      int totalSize = 0;
      final Map<String, dynamic> stats = {};

      for (var file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;

          // Извлекаем nmId из имени файла
          final fileName = path.basename(file.path);
          if (fileName.contains('_')) {
            final parts = fileName.split('_');
            if (parts.isNotEmpty) {
              final nmIdStr = parts[0];

              if (!stats.containsKey(nmIdStr)) {
                stats[nmIdStr] = {
                  'photoCount': 0,
                  'totalSize': 0,
                };
              }

              stats[nmIdStr]['photoCount'] += 1;
              stats[nmIdStr]['totalSize'] += stat.size;
            }
          }
        }
      }

      _cacheInfo['totalFiles'] = files.length;
      _cacheInfo['totalSize'] = totalSize;
      _cacheInfo['cacheStats'] = stats;

      await _saveCacheInfo();
    } catch (e) {
      print('⚠️ Ошибка обновления информации о кэше: $e');
    }
  }

  String getCachePath() {
    return _cacheDirectory?.path ?? '';
  }

  Future<void> openCacheFolder() async {
    try {
      final cachePath = getCachePath();
      if (cachePath.isEmpty) return;

      // Для разных платформ используем разные команды
      if (Platform.isWindows) {
        await Process.run('explorer', [cachePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [cachePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [cachePath]);
      }
    } catch (e) {
      print('❌ Не удалось открыть папку кэша: $e');
    }
  }
}