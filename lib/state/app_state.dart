import 'package:flutter/material.dart';

import '../i18n/lang.dart';
import 'store.dart';

/// App-wide settings. Listen to it (it is a [ChangeNotifier]) to rebuild
/// when the language, appearance or the accessibility option changes.
/// Every change is saved, and restored on the next launch.
class AppState extends ChangeNotifier {
  AppState._() {
    final saved = Store.get('lang');
    _lang = saved is String
        ? AppLang.fromCode(saved)
        // older versions saved a bool; otherwise follow the device language
        : (Store.get('arabic') == true ? AppLang.ar : _deviceLang());
    _avoidStairs = Store.get('avoidStairs') == true;
    _themeMode = switch (Store.get('theme')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
  static final AppState instance = AppState._();

  late AppLang _lang;
  bool _avoidStairs = false;
  ThemeMode _themeMode = ThemeMode.system;

  AppLang get lang => _lang;

  /// Step-free routing: lifts and level floor only (no stairs, no treads, no
  /// moving walkway).
  bool get avoidStairs => _avoidStairs;
  ThemeMode get themeMode => _themeMode;

  static AppLang _deviceLang() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return AppLang.fromCode(code);
  }

  void setLang(AppLang l) {
    if (_lang == l) return;
    _lang = l;
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
    'lang': _lang.code,
    'avoidStairs': _avoidStairs,
    'theme': _themeMode.name,
  });
}
