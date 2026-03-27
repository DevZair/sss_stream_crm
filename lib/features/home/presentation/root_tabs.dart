import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;

import '../../chat/presentation/pages/chat_list_page.dart';
import '../../call/presentation/widgets/incoming_video_call_host.dart';
import '../../call/services/connectycube_call_kit_service.dart';
import '../../settings/presentation/pages/settings_page.dart';
import '../../../service/local_push_notifications.dart';
import '../../../service/notification_service.dart';

class RootTabs extends StatefulWidget {
  const RootTabs({super.key});

  @override
  State<RootTabs> createState() => _RootTabsState();
}

class _RootTabsState extends State<RootTabs> {
  int _index = 2; // default to Chats

  @override
  void initState() {
    super.initState();
    ConnectycubeCallKitService.ensureInitialized();
    NotificationService.instance.initialize();
    unawaited(ConnectycubeCallKitService.syncVoipTokenToFirestore());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeLaunchNotification();
      if (mounted) {
        ConnectycubeCallKitService.offerFullScreenIncomingCallPermission(
          context,
        );
      }
    });
  }

  Future<void> _consumeLaunchNotification() async {
    final details = await LocalPushNotifications.getLaunchDetails();
    final payload = details?.notificationResponse?.payload;
    if (details?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      NotificationService.instance.openChatById(payload);
    }
  }

  late final List<Widget> _pages = [
    const _PlaceholderPage(
      title: 'Contacts',
      icon: CupertinoIcons.person_solid,
    ),
    const _PlaceholderPage(title: 'Calls', icon: CupertinoIcons.phone_fill),
    const ChatListPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return IncomingVideoCallHost(
      child: CupertinoPageScaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: CupertinoColors.black, // Dark background for the stack
        child: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(index: _index, children: _pages),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16 + padding.bottom,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _GlassBar(
                      height: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _NavButton(
                            label: 'Contacts',
                            icon: CupertinoIcons.person_solid,
                            active: _index == 0,
                            onTap: () => _setIndex(0),
                          ),
                          _NavButton(
                            label: 'Calls',
                            icon: CupertinoIcons.phone_fill,
                            active: _index == 1,
                            onTap: () => _setIndex(1),
                          ),
                          _NavButton(
                            label: 'Chats',
                            icon: CupertinoIcons.chat_bubble_2_fill,
                            active: _index == 2,
                            onTap: () => _setIndex(2),
                          ),
                          _NavButton(
                            label: 'Settings',
                            icon: CupertinoIcons.gear_alt_fill,
                            active: _index == 3,
                            onTap: () => _setIndex(3),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setIndex(int value) => setState(() => _index = value);
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final activeColor = CupertinoColors.activeBlue;
    final inactiveColor = CupertinoColors.systemGrey;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: active ? const Color(0x22FFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: active ? activeColor : inactiveColor,
              size: 26,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: active ? activeColor : inactiveColor,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBar extends StatelessWidget {
  const _GlassBar({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xCC1C1C1E),
            border: Border.all(color: const Color(0x22FFFFFF), width: 0.5),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final fg = isDark ? CupertinoColors.white : CupertinoColors.black;
    return CupertinoPageScaffold(
      backgroundColor: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      navigationBar: CupertinoNavigationBar(
        middle: Text(title),
        backgroundColor: isDark
            ? const Color(0xFF1C1C1E).withValues(alpha: 0.8)
            : null,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: fg.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              '$title page',
              style: TextStyle(color: fg.withValues(alpha: 0.5)),
            ),
          ],
        ),
      ),
    );
  }
}
