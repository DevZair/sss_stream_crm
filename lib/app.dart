import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/data/data_sources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/data/repositories/mock_auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'core/widgets/splash_screen.dart';

class App extends StatefulWidget {
  const App({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final controller = ThemeController.instance;

  @override
  Widget build(BuildContext context) {
    final bool useMockAuth = const bool.fromEnvironment(
      'USE_MOCK_AUTH',
      defaultValue: false,
    );

    final authRepository = useMockAuth
        ? MockAuthRepository()
        : AuthRepositoryImpl(AuthRemoteDataSource());

    return RepositoryProvider.value(
      value: authRepository,
      child: BlocProvider(
        create: (_) => AuthBloc(authRepository: authRepository),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: controller.themeMode,
          builder: (context, mode, child) {
            final isDark =
                mode == ThemeMode.dark ||
                (mode == ThemeMode.system &&
                    WidgetsBinding
                            .instance
                            .platformDispatcher
                            .platformBrightness ==
                        Brightness.dark);

            return CupertinoApp(
              navigatorKey: App.navigatorKey,
              debugShowCheckedModeBanner: false,
              title: 'Secure Chat',
              theme: isDark ? AppTheme.cupertinoLDark : AppTheme.cupertinoLight,
              // Wrap with Material so Material widgets (BLoC Listeners etc.) still work
              builder: (context, child) => Material(
                color: Colors.transparent,
                child: Theme(
                  data: isDark ? AppTheme.dark : AppTheme.light,
                  child: child!,
                ),
              ),
              home: const SplashScreen(),
            );
          },
        ),
      ),
    );
  }
}
