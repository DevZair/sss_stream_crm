import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../chat/presentation/pages/chat_list_page.dart';
import '../bloc/auth_bloc.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
          _showSnack(context, state.errorMessage, isError: true);
        } else if (state.status == AuthStatus.success) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => const ChatListPage()),
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) {
                    final isLoading = state.status == AuthStatus.loading;

                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Войти',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 24),
                          AppTextField(
                            label: 'Логин',
                            hint: 'username или телефон',
                            controller: _usernameController,
                            keyboardType: TextInputType.emailAddress,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Имя',
                            hint: 'Как вас называть',
                            controller: _fullNameController,
                            keyboardType: TextInputType.name,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'ID пользователя',
                            hint: 'Ваш внутренний ID',
                            controller: _userIdController,
                            keyboardType: TextInputType.text,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            label: 'Пароль',
                            hint: '••••••••',
                            controller: _passwordController,
                            obscureText: state.obscurePassword,
                            suffix: IconButton(
                              onPressed: () => context.read<AuthBloc>().add(
                                const AuthTogglePasswordVisibility(),
                              ),
                              icon: Icon(
                                state.obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 20),
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
                          if (state.errorMessage.isNotEmpty &&
                              state.status == AuthStatus.failure) ...[
                            const SizedBox(height: 12),
                            _ErrorBanner(message: state.errorMessage),
                          ],
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

  void _showSnack(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: isError ? AppColors.error : AppColors.surface,
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
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
        color: AppColors.error.withOpacity(0.08),
        border: Border.all(color: AppColors.error.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
