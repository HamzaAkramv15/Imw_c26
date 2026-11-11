import 'dart:ui';

/// The languages the app speaks. The order is the column order of every
/// table in translations.dart.
enum AppLang {
  en('English', 'en'),
  ar('العربية', 'ar'),
  de('Deutsch', 'de'),
  fr('Français', 'fr'),
  ru('Русский', 'ru'),
  ja('日本語', 'ja'),
  ko('한국어', 'ko'),
  zh('简体中文', 'zh');

  const AppLang(this.nativeName, this.code);

  /// The language's own name, as shown in the language picker.
  final String nativeName;
  final String code;

  bool get rtl => this == AppLang.ar;

  /// Scripts written without spaces between words: no letter-spacing, and
  /// search matches inside words.
  bool get cjk => this == AppLang.ja || this == AppLang.ko || this == AppLang.zh;

  /// Locale handed to Flutter: it picks the right fonts (Japanese and Chinese
  /// share code points but not glyph shapes) and the built-in widget texts.
  Locale get locale => this == AppLang.zh ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans') : Locale(code);

  static AppLang fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return AppLang.en;
  }
}
