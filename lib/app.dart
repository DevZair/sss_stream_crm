import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/data/data_sources/auth_remote_data_source.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/domain/usecases/login_usecase.dart';
import 'features/auth/data/repositories/mock_auth_repository.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/auth/presentation/pages/login_page.dart';

class App extends StatefulWidget {
  const App({super.key});

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
    ); // toggle to true only for offline demo

    final authRepository = useMockAuth
        ? MockAuthRepository()
        : AuthRepositoryImpl(AuthRemoteDataSource());

    return RepositoryProvider.value(
      value: authRepository,
      child: BlocProvider(
        create: (_) => AuthBloc(loginUseCase: LoginUseCase(authRepository)),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: controller.themeMode,
          builder: (_, mode, __) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Secure Chat',
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode,
              home: const LoginPage(),
            );
          },
        ),
      ),
    );
  }
}
