import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Tiny key/value store for the app's saved state (one JSON blob on disk).
/// `Store.init()` is awaited in `main()` before anything reads from it, so the
/// first frame already shows the restored language, theme, pins, map and route.
class Store {
  Store._();

  static SharedPreferences? _prefs;
  static Map<String, dynamic> _data = {};
  static const _key = 'gem_state_v1';

  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_key);
      if (raw != null) _data = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      _data = {}; // a corrupt or unavailable store just means "start fresh"
    }
  }

  /// The saved value for [key], or null.
  static Object? get(String key) => _data[key];

  static void put(Map<String, dynamic> values) {
    _data.addAll(values);
    try {
      _prefs?.setString(_key, jsonEncode(_data));
    } catch (_) {}
  }
}
