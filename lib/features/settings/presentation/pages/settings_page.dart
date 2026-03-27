import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show CircleAvatar;

import '../../../../core/theme/app_colors.dart';
import '../../../../service/db_service.dart';
import '../../../auth/presentation/pages/login_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? CupertinoColors.black : const Color(0xFFF2F2F7);

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Настройки'),
        backgroundColor: isDark
            ? const Color(0xFF1C1C1E).withValues(alpha: 0.8)
            : CupertinoColors.systemBackground.withValues(alpha: 0.8),
      ),
      child: ListView(
        children: [
          // ── Profile Section ─────────────────────────────────────────────
          CupertinoListSection.insetGrouped(
            margin: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            children: [
              CupertinoListTile(
                padding: const EdgeInsets.all(12),
                leadingSize: 60,
                leading: CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    DBService.currentUserName.isNotEmpty
                        ? DBService.currentUserName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: CupertinoColors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  DBService.currentFullName.isNotEmpty
                      ? DBService.currentFullName
                      : DBService.currentUserName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '@${DBService.currentUserName}',
                  style: const TextStyle(color: CupertinoColors.systemGrey),
                ),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _showInfo(context, 'Профиль: ${DBService.currentFullName}'),
              ),
            ],
          ),

          // ── Account Section ─────────────────────────────────────────────
          CupertinoListSection.insetGrouped(
            header: const Text('АККАУНТ'),
            children: [
              _SettingsTile(
                icon: CupertinoIcons.lock_shield_fill,
                iconColor: CupertinoColors.systemBlue,
                title: 'Конфиденциальность',
                onTap: () => _showInfo(context, 'Функция скоро появится.'),
              ),
              _SettingsTile(
                icon: CupertinoIcons.bell_fill,
                iconColor: CupertinoColors.systemRed,
                title: 'Уведомления',
                onTap: () => _showInfo(context, 'Настройки уведомлений скоро.'),
              ),
              _SettingsTile(
                icon: CupertinoIcons.paintbrush_fill,
                iconColor: CupertinoColors.systemCyan,
                title: 'Оформление',
                onTap: () => _showInfo(context, 'Смена темы скоро.'),
              ),
            ],
          ),

          // ── Support Section ─────────────────────────────────────────────
          CupertinoListSection.insetGrouped(
            header: const Text('ПОДДЕРЖКА'),
            children: [
              _SettingsTile(
                icon: CupertinoIcons.question_circle_fill,
                iconColor: CupertinoColors.systemGreen,
                title: 'Помощь и FAQ',
                onTap: () => _showInfo(context, 'support@example.com'),
              ),
              _SettingsTile(
                icon: CupertinoIcons.info_circle_fill,
                iconColor: CupertinoColors.systemGrey,
                title: 'О приложении',
                onTap: () => _showInfo(context, 'Версия 1.0.0 (Cupertino Redesign)'),
              ),
            ],
          ),

          // ── Actions Section ─────────────────────────────────────────────
          CupertinoListSection.insetGrouped(
            children: [
              CupertinoListTile(
                leading: const _IconBox(
                  icon: CupertinoIcons.square_arrow_right_fill,
                  color: CupertinoColors.systemRed,
                ),
                title: const Text(
                  'Выйти',
                  style: TextStyle(color: CupertinoColors.systemRed),
                ),
                onTap: () => _handleLogout(context),
              ),
            ],
          ),
          const SizedBox(height: 100), // Spacing for floating tab bar
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Выйти?'),
        content: const Text('Вы уверены, что хотите завершить сессию?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      await DBService.clearSession();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          CupertinoPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
      }
    }
  }

  void _showInfo(BuildContext context, String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: _IconBox(icon: icon, color: iconColor),
      title: Text(title),
      trailing: const CupertinoListTileChevron(),
      onTap: onTap,
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: CupertinoColors.white, size: 18),
    );
  }
}
