import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/ios_action_sheet.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../home/presentation/root_tabs.dart';
import '../bloc/auth_bloc.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _userIdController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _userIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _isFormValid =>
      _usernameController.text.trim().isNotEmpty &&
      _fullNameController.text.trim().isNotEmpty &&
      _userIdController.text.trim().isNotEmpty &&
      _passwordController.text.trim().length >= 6;

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state.status == AuthStatus.failure &&
            state.errorMessage.isNotEmpty) {
          showIosAlert<void>(
            context: context,
            title: 'Ошибка входа',
            message: state.errorMessage,
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                child: const Text('OK'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        } else if (state.status == AuthStatus.success) {
          Navigator.of(context).pushReplacement(
            CupertinoPageRoute<void>(builder: (_) => const RootTabs()),
          );
        }
      },
      child: CupertinoPageScaffold(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final isLoading = state.status == AuthStatus.loading;
                    final isDark =
                        CupertinoTheme.brightnessOf(context) == Brightness.dark;

                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Logo ──────────────────────────────────────────
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(22),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                CupertinoIcons.chat_bubble_2_fill,
                                color: CupertinoColors.white,
                                size: 40,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              'Войти',
                              style: CupertinoTheme.of(
                                context,
                              ).textTheme.navLargeTitleTextStyle,
                            ),
                          ),
                          Center(
                            child: Text(
                              'Безопасный мессенджер',
                              style: TextStyle(
                                fontSize: 15,
                                color: isDark
                                    ? AppColors.textSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 36),

                          // ── Fields ────────────────────────────────────────
                          AppTextField(
                            label: 'Логин',
                            hint: 'уникальный никнейм',
                            controller: _usernameController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Имя',
                            hint: 'Как вас называть',
                            controller: _fullNameController,
                            keyboardType: TextInputType.name,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'ID пользователя',
                            hint: 'Ваш внутренний ID',
                            controller: _userIdController,
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 14),
                          AppTextField(
                            label: 'Пароль',
                            hint: '••••••••',
                            controller: _passwordController,
                            obscureText: state.obscurePassword,
                            textInputAction: TextInputAction.done,
                            suffix: GestureDetector(
                              onTap: () => context.read<AuthBloc>().add(
                                const AuthTogglePasswordVisibility(),
                              ),
                              child: Icon(
                                state.obscurePassword
                                    ? CupertinoIcons.eye
                                    : CupertinoIcons.eye_slash,
                                color: AppColors.textSecondary,
                                size: 20,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 28),

                          // ── Button ────────────────────────────────────────
                          PrimaryButton(
                            label: 'Войти',
                            isLoading: isLoading,
                            disabled: !_isFormValid,
                            onPressed: () {
                              context.read<AuthBloc>().add(
                                AuthLoginSubmitted(
                                  username: _usernameController.text,
                                  password: _passwordController.text,
                                  fullName: _fullNameController.text,
                                  userId: _userIdController.text,
                                ),
                              );
                            },
                          ),

                          // ── Error ─────────────────────────────────────────
                          if (state.errorMessage.isNotEmpty &&
                              state.status == AuthStatus.failure) ...[
                            const SizedBox(height: 16),
                            _ErrorBanner(message: state.errorMessage),
                          ],
                          const SizedBox(height: 24),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle,
            color: AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
