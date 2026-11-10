import 'package:flutter/widgets.dart';

import 'app.dart';
import 'state/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init(); // saved state must be loaded before the first frame
  runApp(const GemNavigatorApp());
}
