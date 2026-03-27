import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'service/db_service.dart';
import 'service/firebase_backend_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DBService.initialize();
  await FirebaseBackendService.initialize(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const App());
}
