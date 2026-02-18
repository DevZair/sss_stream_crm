import 'package:flutter/material.dart';

import 'app.dart';
import 'service/db_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DBService.initialize();

  runApp(const App());
}
