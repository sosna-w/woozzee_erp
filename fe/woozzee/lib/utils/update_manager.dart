// update_manager.dart - ОБНОВЛЕННАЯ ВЕРСИЯ
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:window_manager/window_manager.dart';
import 'constants.dart';

class UpdateManager {
  static final UpdateManager _instance = UpdateManager._internal();
  factory UpdateManager() => _instance;
  UpdateManager._internal();

  static const String _baseUrl = 'https://hide_domain.com';
  String? _latestVersion;
  String? _latestFilename;
  String? _latestTitle;
  String? _latestDescription;

  // Статическая переменная для хранения информации об обновлении для показа при запуске
  static Map<String, dynamic>? _pendingUpdate;

  Future<Map<String, dynamic>> checkForUpdates() async {
    try {
      final url = Uri.parse('$_baseUrl/app/version/check/$appVersion');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final updateAvailable = data['update_available'] ?? false;

        if (updateAvailable) {
          _latestVersion = data['latest_version']['version'];
          _latestFilename = data['latest_version']['filename'];
          _latestTitle = data['latest_version']['title'];
          _latestDescription = data['latest_version']['description'];

          final updateInfo = {
            'update_available': true,
            'current_version': appVersion,
            'latest_version': _latestVersion,
            'filename': _latestFilename,
            'title': _latestTitle,
            'description': _latestDescription,
          };

          // Сохраняем информацию об обновлении для показа при запуске
          _pendingUpdate = updateInfo;

          return updateInfo;
        } else {
          _pendingUpdate = null; // Сбрасываем, если обновления нет
          return {
            'update_available': false,
            'current_version': appVersion,
            'latest_version': appVersion,
          };
        }
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Получить информацию об ожидающем обновлении
  static Map<String, dynamic>? getPendingUpdate() {
    return _pendingUpdate;
  }

  // Очистить информацию об ожидающем обновлении (после показа диалога)
  static void clearPendingUpdate() {
    _pendingUpdate = null;
  }

  // Проверить, есть ли доступное обновление
  static bool hasPendingUpdate() {
    return _pendingUpdate != null && _pendingUpdate!['update_available'] == true;
  }

  Future<void> downloadUpdate(BuildContext context, String filename) async {
    try {
      final url = Uri.parse('$_baseUrl/app/version/download/$filename');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$filename';
        final file = File(filePath);

        await file.writeAsBytes(response.bodyBytes);

        await _runInstaller(filePath);
      } else {
        throw Exception('Ошибка скачивания: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // update_manager.dart - добавляем метод

  Future<void> downloadUpdateWithProgress(
      BuildContext context,
      String filename,
      Function(double progress) onProgress,
      ) async {
    try {
      final url = Uri.parse('$_baseUrl/app/version/download/$filename');
      final client = http.Client();
      final request = http.Request('GET', url);
      final response = await client.send(request);

      if (response.statusCode == 200) {
        final contentLength = response.contentLength;
        int bytesReceived = 0;
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$filename';
        final file = File(filePath);
        final sink = file.openWrite();

        await response.stream.listen((chunk) {
          bytesReceived += chunk.length;
          if (contentLength != null && contentLength > 0) {
            final progressValue = bytesReceived / contentLength;
            onProgress(progressValue.clamp(0.0, 1.0));
          }
          sink.add(chunk);
        }).asFuture();

        await sink.close();
        await _runInstaller(filePath);
      } else {
        throw Exception('Ошибка скачивания: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getVersionHistory() async {
    try {
      final url = Uri.parse('$_baseUrl/app/versions');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final versions = (data['versions'] as List).cast<Map<String, dynamic>>();
        return versions;
      } else {
        throw Exception('Ошибка сервера: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _runInstaller(String installerPath) async {
    try {
      await windowManager.close();

      if (Platform.isWindows) {
        await Process.run(installerPath, [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/LANG=russian'
        ]);
      } else {
        await OpenFile.open(installerPath);
      }
    } catch (e) {
      print('Ошибка запуска установщика: $e');
    }
  }

  String? get latestVersion => _latestVersion;
  String? get latestTitle => _latestTitle;
  String? get latestDescription => _latestDescription;
}