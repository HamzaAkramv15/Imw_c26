import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'i18n/lang.dart';
import 'screens/museum_map_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

class GemNavigatorApp extends StatelessWidget {
  const GemNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds when language / appearance flips (RTL, LTR, light, dark).
    final app = AppState.instance;
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'GEM Navigator',
        debugShowCheckedModeBanner: false,
        theme: GemTheme.light,
        darkTheme: GemTheme.dark,
        themeMode: app.themeMode,
        // The locale picks the text direction, the fonts (Han characters are
        // drawn differently in Japanese and Chinese) and the built-in texts.
        locale: app.lang.locale,
        supportedLocales: [for (final l in AppLang.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // The controls float over the plan: text grows with the system setting,
        // up to the point where it would start to bury the map.
        builder: (context, child) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child!),
        home: const MuseumMapScreen(),
      ),
    );
  }
}
