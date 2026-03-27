import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show CircleAvatar, Colors, Divider, Material, OverlayEntry;
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/ios_action_sheet.dart';
import '../../../../service/utils/error_messages.dart';
import '../../../../service/incoming_message_sound.dart';
import '../../../../service/notification_service.dart';
import '../../data/data_sources/chat_remote_data_source.dart';
import '../models/chat_preview.dart';
import 'chat_detail_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _searchController = TextEditingController();
  final _remote = const ChatRemoteDataSource();
  int _filterIndex = 0; // 0 = All, 1 = Unread
  List<ChatPreview> _allChats = const [];
  List<GlobalSearchUser> _globalResults = const [];
  bool _isLoading = false;
  bool _isSearchingRemote = false;
  String? _error;
  Timer? _searchDebounce;
  StreamSubscription<List<ChatPreview>>? _chatSubscription;
  bool _chatsStreamPrimed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestIosPermissions();
      _initChatStream();
    });
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    setState(() {}); // For local filter

    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      setState(() => _globalResults = const []);
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      setState(() => _isSearchingRemote = true);

      try {
        final users = await _remote.searchUsers(q);
        if (mounted) {
          setState(() => _globalResults = users);
        }
      } catch (e) {
        debugPrint('Remote search error: $e');
      } finally {
        if (mounted) setState(() => _isSearchingRemote = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final localFiltered = _filteredChats();
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final bgColor = isDark ? AppColors.background : AppColors.lightBackground;
    final fgColor = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final query = _searchController.text.trim();

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        backgroundColor:
            (isDark
                    ? const Color(0xFF1C1C1E)
                    : CupertinoColors.systemBackground)
                .withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.separator : AppColors.lightSeparator,
            width: 0.5,
          ),
        ),
        middle: Text(
          'Чаты',
          style: TextStyle(
            color: fgColor,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _startNewChatDialog,
          child: const Icon(
            CupertinoIcons.square_pencil,
            color: AppColors.primary,
            size: 24,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: CupertinoSearchTextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                placeholder: 'Поиск чатов и людей',
                backgroundColor: isDark
                    ? AppColors.surfaceSecondary
                    : AppColors.lightSurfaceSecondary,
                style: TextStyle(color: fgColor, fontSize: 16),
              ),
            ),

            if (query.isEmpty) ...[
              // ── Segment control ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _filterIndex,
                  backgroundColor: isDark
                      ? AppColors.surfaceSecondary
                      : AppColors.lightSurfaceSecondary,
                  thumbColor: isDark
                      ? AppColors.surfaceTertiary
                      : CupertinoColors.white,
                  onValueChanged: (v) => setState(() => _filterIndex = v ?? 0),
                  children: {
                    0: _SegmentItem(label: 'Все', active: _filterIndex == 0, fg: fgColor),
                    1: _SegmentItem(label: 'Непрочитанные', active: _filterIndex == 1, fg: fgColor),
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],

            // ── Main Content ────────────────────────────────────────────────
            Expanded(
              child: _isLoading && _allChats.isEmpty
                  ? const Center(child: CupertinoActivityIndicator(radius: 14))
                  : _error != null && _allChats.isEmpty
                  ? _ErrorView(message: _error!, onRetry: _loadChats)
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        if (query.isEmpty)
                          CupertinoSliverRefreshControl(
                            onRefresh: () async {
                              // Since we use streams, pull-to-refresh isn't strictly needed,
                              // but we can simulate a delay to satisfy the UX.
                              await Future.delayed(const Duration(milliseconds: 500));
                            },
                          ),
                        
                        // ── Local Results ─────────────────────────────────────
                        if (localFiltered.isNotEmpty)
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final chat = localFiltered[index];
                                return _ChatTile(
                                  chat: chat,
                                  isDark: isDark,
                                  isLast: index == localFiltered.length - 1 && query.isEmpty,
                                  onTap: () => _openChat(chat),
                                  onLongPress: () => _showChatActions(context, chat),
                                  onArchive: () => _archive(chat),
                                );
                              },
                              childCount: localFiltered.length,
                            ),
                          ),

                        // ── Global Search Results ──────────────────────────────
                        if (query.isNotEmpty) ...[
                          if (_isSearchingRemote)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CupertinoActivityIndicator(),
                              ),
                            ),
                          if (_globalResults.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: _SectionHeader(title: 'ГЛОБАЛЬНЫЙ ПОИСК', isDark: isDark),
                            ),
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final user = _globalResults[index];
                                  final isLast = index == _globalResults.length - 1;
                                  return _GlobalUserTile(
                                    user: user,
                                    isDark: isDark,
                                    isLast: isLast,
                                    onTap: () => _startChatWithUser(user),
                                  );
                                },
                                childCount: _globalResults.length,
                              ),
                            ),
                          ],
                          if (!_isSearchingRemote &&
                              localFiltered.isEmpty &&
                              _globalResults.isEmpty)
                            const SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(
                                  child: Text(
                                    'Ничего не найдено',
                                    style: TextStyle(color: CupertinoColors.systemGrey),
                                  ),
                                ),
                              ),
                            ),
                        ],
                        const SliverToBoxAdapter(child: SizedBox(height: 100)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<ChatPreview> _filteredChats() {
    final query = _searchController.text.toLowerCase().trim();
    final result = _allChats.where((chat) {
      final matchesSearch =
          query.isEmpty ||
          chat.name.toLowerCase().contains(query) ||
          chat.message.toLowerCase().contains(query);
      final matchesFilter = _filterIndex == 0 ? true : chat.isUnread;
      return matchesSearch && matchesFilter;
    }).toList();

    result.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return _allChats.indexOf(a).compareTo(_allChats.indexOf(b));
    });

    return result;
  }

  Future<void> _openChat(ChatPreview chat) async {
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => ChatDetailPage(chat: chat),
      ),
    );
    // No need to call _loadChats(), the stream will automatically update list
  }

  Future<void> _startChatWithUser(GlobalSearchUser user) async {
    setState(() => _isLoading = true);
    try {
      final chat = await _remote.startChat(user.username);
      if (!mounted) return;
      _openChat(chat);
      _searchController.clear();
      setState(() {
        _allChats = [chat, ..._allChats.where((c) => c.chatId != chat.chatId)];
        _globalResults = const [];
      });
    } catch (e) {
      _showToast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _togglePin(ChatPreview chat) {
    final index = _allChats.indexOf(chat);
    if (index == -1) return;
    final isPinned = _allChats[index].pinned;
    if (!isPinned && _allChats.where((c) => c.pinned).length >= 3) {
      _showToast('Максимум 3 закрепленных чата');
      return;
    }
    setState(() {
      _allChats[index] = _allChats[index].copyWith(pinned: !isPinned);
    });
  }

  void _archive(ChatPreview chat) => setState(() => _allChats.remove(chat));

  void _showToast(String message) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: 100,
        left: 40,
        right: 40,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceTertiary.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Timer(const Duration(seconds: 2), entry.remove);
  }

  Future<void> _showChatActions(BuildContext ctx, ChatPreview chat) async {
    await showIosActionSheet(
      context: ctx,
      title: chat.name,
      actions: [
        IosSheetAction(
          label: chat.pinned ? 'Открепить' : 'Закрепить',
          icon: CupertinoIcons.pin,
          onTap: () => _togglePin(chat),
        ),
        IosSheetAction(
          label: 'Архивировать',
          icon: CupertinoIcons.archivebox,
          onTap: () => _archive(chat),
        ),
      ],
    );
  }

  Future<void> _startNewChatDialog() async {
    final controller = TextEditingController();
    final query = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Новый чат'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: CupertinoTextField(
            controller: controller,
            placeholder: 'Логин или имя',
            autofocus: true,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (query != null && query.isNotEmpty) {
      _startChatWithUser(GlobalSearchUser(
        uid: '',
        username: query,
        fullName: '',
        internalUserId: '',
        avatarUrl: '',
      ));
    }
  }

  void _initChatStream() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    _chatSubscription = _remote.streamChats(limit: 50).listen(
      (chats) {
        if (!mounted) return;
        final prev = _allChats;
        final me = FirebaseAuth.instance.currentUser?.uid;
        if (_chatsStreamPrimed && prev.isNotEmpty) {
          final incoming = IncomingMessageSound.findIncomingFirestoreUpdate(
            previous: prev,
            next: chats,
            activeChatId: NotificationService.instance.currentChatId,
            currentUserId: me,
          );
          if (incoming != null) {
            IncomingMessageSound.play();
            NotificationService.instance.showIncomingChatBanner(incoming);
          }
        }
        _chatsStreamPrimed = true;
        setState(() {
          _allChats = chats;
          _isLoading = false;
          _error = null;
        });
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _error = friendlyError(error);
            _isLoading = false;
          });
        }
      },
    );
  }

  Future<void> _loadChats() async {
    // Left for refresh fallback
    // The stream is active, so we don't strictly need this unless we
    // completely reload. Since we now use _initChatStream(), 
    // _loadChats() is obsolete but kept for reference or retry button logic.
    _initChatStream();
  }

  Future<void> _requestIosPermissions() async {
    if (!Platform.isIOS) return;
    final permissions = [
      Permission.camera,
      Permission.microphone,
      Permission.photos,
    ];
    for (final p in permissions) {
      final status = await p.status;
      if (status.isDenied) await p.request();
    }
  }
}

// ── Subwidgets ─────────────────────────────────────────────────────────────

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({required this.label, required this.active, required this.fg});
  final String label;
  final bool active;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      color: isDark ? AppColors.background : AppColors.lightBackground,
      child: Text(
        title,
        style: const TextStyle(
          color: CupertinoColors.systemGrey,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _GlobalUserTile extends StatelessWidget {
  const _GlobalUserTile({
    required this.user,
    required this.isDark,
    required this.onTap,
    required this.isLast,
  });
  final GlobalSearchUser user;
  final bool isDark;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: isDark ? AppColors.surface : AppColors.lightSurface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    backgroundImage: user.avatarUrl.isNotEmpty ? NetworkImage(user.avatarUrl) : null,
                    child: user.avatarUrl.isEmpty
                        ? Text(user.displayName[0].toUpperCase(),
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 16)),
                        Text('@${user.username}',
                            style: const TextStyle(color: CupertinoColors.systemGrey, fontSize: 14)),
                      ],
                    ),
                  ),
                  const Icon(CupertinoIcons.chevron_forward, color: CupertinoColors.systemGrey3, size: 18),
                ],
              ),
            ),
            if (!isLast)
              Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 68,
                  color: isDark ? AppColors.separator : AppColors.lightSeparator),
          ],
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
    required this.onArchive,
    required this.isLast,
  });

  final ChatPreview chat;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onArchive;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final fgColor = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final secondaryColor = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
    final surfaceColor = isDark ? AppColors.surface : AppColors.lightSurface;

    return Dismissible(
      key: ValueKey(chat.chatId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: AppColors.error,
        child: const Icon(CupertinoIcons.archivebox, color: CupertinoColors.white),
      ),
      onDismissed: (_) => onArchive(),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: surfaceColor,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: chat.color,
                          backgroundImage: chat.avatarUrl != null ? NetworkImage(chat.avatarUrl!) : null,
                          child: chat.avatarUrl != null
                              ? null
                              : Text(chat.initials,
                                  style: const TextStyle(
                                      color: CupertinoColors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                        if (chat.isUnread)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle,
                                border: Border.all(color: surfaceColor, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(chat.name,
                                      style: TextStyle(color: fgColor, fontWeight: FontWeight.w600, fontSize: 16),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              if (chat.pinned)
                                const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(CupertinoIcons.pin_fill, size: 13, color: AppColors.textSecondary)),
                              Text(chat.time,
                                  style: TextStyle(
                                      color: chat.isUnread ? AppColors.primary : secondaryColor, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(chat.message,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: secondaryColor, fontSize: 14)),
                              ),
                              if (chat.isUnread)
                                Container(
                                    width: 10,
                                    height: 10,
                                    decoration:
                                        const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: 72,
                    color: isDark ? AppColors.separator : AppColors.lightSeparator),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          CupertinoButton(onPressed: onRetry, child: const Text('Повторить')),
        ],
      ),
    );
  }
}
