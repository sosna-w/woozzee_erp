// version_info.dart
import 'package:shared_preferences/shared_preferences.dart';

class VersionInfo {
  static const String _lastUpdateCheckKey = 'last_update_check';
  static const String _skipVersionKey = 'skip_version_';

  static Future<void> saveLastUpdateCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUpdateCheckKey, DateTime.now().toIso8601String());
  }

  static Future<DateTime?> getLastUpdateCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final dateString = prefs.getString(_lastUpdateCheckKey);
    if (dateString != null) {
      return DateTime.parse(dateString);
    }
    return null;
  }

  static Future<void> skipVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_skipVersionKey + version, true);
  }

  static Future<bool> isVersionSkipped(String version) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_skipVersionKey + version) ?? false;
  }
}