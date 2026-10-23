import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationDataStorage {
  static final Map<int, Map<String, dynamic>> _notificationPayloads = {};

  static const String _prefsKey = 'notification_payloads';

  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_prefsKey);
    if (jsonString != null && jsonString.isNotEmpty) {
      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      // keys in JSON are strings, convert to int keys
      _notificationPayloads.clear();
      jsonMap.forEach((key, value) {
        _notificationPayloads[int.parse(key)] = Map<String, dynamic>.from(
          value,
        );
      });
    }
  }

  static Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // convert int keys to strings for json
    final jsonMap = _notificationPayloads.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final jsonString = json.encode(jsonMap);
    await prefs.setString(_prefsKey, jsonString);
  }

  static Future<void> savePayload(int id, Map<String, dynamic> payload) async {
    _notificationPayloads[id] = payload;
    await saveToPrefs();
  }

  static Map<String, dynamic>? getPayload(int id) {
    return _notificationPayloads[id];
  }

  static Future<void> removePayload(int id) async {
    _notificationPayloads.remove(id);
    await saveToPrefs();
  }

  static Map<int, Map<String, dynamic>> getAllPayloads() {
    return _notificationPayloads;
  }
}
