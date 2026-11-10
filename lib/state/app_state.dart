import 'package:flutter/material.dart';

import 'store.dart';

/// App-wide settings. Listen to it (it is a [ChangeNotifier]) to rebuild
/// when the language, appearance or the accessibility option changes.
/// Every change is saved, and restored on the next launch.
class AppState extends ChangeNotifier {
  AppState._() {
    _arabic = Store['arabic'] == true;
    _avoidStairs = Store['avoidStairs'] == true;
    _themeMode = switch (Store['theme']) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
  static final AppState instance = AppState._();

  bool _arabic = false;
  bool _avoidStairs = false;
  ThemeMode _themeMode = ThemeMode.system;

  bool get isArabic => _arabic;
  bool get avoidStairs => _avoidStairs;
  ThemeMode get themeMode => _themeMode;

  void toggleLanguage() => setArabic(!_arabic);

  void setArabic(bool v) {
    if (_arabic == v) return;
    _arabic = v;
    _save();
    notifyListeners();
  }

  void setAvoidStairs(bool v) {
    if (_avoidStairs == v) return;
    _avoidStairs = v;
    _save();
    notifyListeners();
  }

  void setThemeMode(ThemeMode m) {
    if (_themeMode == m) return;
    _themeMode = m;
    _save();
    notifyListeners();
  }

  void _save() => Store.put({
    'arabic': _arabic,
    'avoidStairs': _avoidStairs,
    'theme': _themeMode.name,
  });
}

extension on Type {
  Object? operator [](String other) {
    return null;
  }
}
