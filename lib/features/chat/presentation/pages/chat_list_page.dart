import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../service/utils/error_messages.dart';
import '../../data/data_sources/chat_remote_data_source.dart';
import '../models/chat_preview.dart';
import 'chat_detail_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ChatRemoteDataSource _remote = const ChatRemoteDataSource();
  ChatFilter _filter = ChatFilter.all;
  List<ChatPreview> _allChats = const [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestIosPermissions();
      _loadChats();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredChats();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _startNewChat,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF1A0C5C), Color(0xFF0D0B2B)]
                : const [Color(0xFFF7FAFF), Color(0xFFE8F0FF)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Text(
                      'Chats',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 18),
                _SearchBar(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),
                _Filters(
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadChats,
                    child: _error != null && _allChats.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 120),
                              Center(
                                child: Text(
                                  _error ?? '',
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: ElevatedButton(
                                  onPressed: _loadChats,
                                  child: const Text('Повторить'),
                                ),
                              ),
                            ],
                          )
                        : _isLoading && _allChats.isEmpty
                        ? Center(
                            child: CircularProgressIndicator(color: onSurface),
                          )
                        : _ChatList(
                            chats: filtered,
                            onTogglePin: _togglePin,
                            onArchive: _archive,
                            onTap: (chat) async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ChatDetailPage(chat: chat),
                                ),
                              );
                              _loadChats();
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ChatPreview> _filteredChats() {
    final query = _searchController.text.toLowerCase();
    final result = _allChats.where((chat) {
      final matchesSearch =
          query.isEmpty ||
          chat.name.toLowerCase().contains(query) ||
          chat.message.toLowerCase().contains(query);

      final matchesFilter = switch (_filter) {
        ChatFilter.all => true,
        ChatFilter.unread => chat.isUnread,
      };

      return matchesSearch && matchesFilter;
    }).toList();

    result.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return _allChats.indexOf(a).compareTo(_allChats.indexOf(b));
    });

    return result;
  }

  int get _pinnedCount => _allChats.where((c) => c.pinned).length;

  void _togglePin(ChatPreview chat) {
    final index = _allChats.indexOf(chat);
    if (index == -1) return;

    final isPinned = _allChats[index].pinned;
    if (!isPinned && _pinnedCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Максимум 3 закрепленных чата')),
      );
      return;
    }

    setState(() {
      _allChats[index] = _allChats[index].copyWith(pinned: !isPinned);
    });
  }

  void _archive(ChatPreview chat) {
    setState(() {
      _allChats.remove(chat);
    });
  }

  Future<void> _startNewChat() async {
    final controller = TextEditingController();
    final phone = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Новый чат', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Введите номер в международном формате',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (!mounted || phone == null || phone.isEmpty) return;

    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите номер в международном формате')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final chat = await _remote.startChat(digits);
      if (!mounted) return;
      setState(() {
        _allChats = [chat, ..._allChats.where((c) => c.chatId != chat.chatId)];
      });
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatDetailPage(chat: chat)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadChats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final chats = await _remote.fetchChats(limit: 50);
      if (mounted) {
        setState(() {
          _allChats = chats;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _requestIosPermissions() async {
    if (!Platform.isIOS) return;
    final permissions = [
      Permission.camera,
      Permission.microphone,
      Permission.photos,
      Permission.photosAddOnly,
    ];
    bool hasPermanentlyDenied = false;
    for (final permission in permissions) {
      final status = await permission.status;
      if (status.isDenied || status.isRestricted) {
        final newStatus = await permission.request();
        if (newStatus.isPermanentlyDenied) {
          hasPermanentlyDenied = true;
        }
      } else if (status.isPermanentlyDenied) {
        hasPermanentlyDenied = true;
      }
    }
    if (hasPermanentlyDenied && mounted) {
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Требуются разрешения'),
          content: const Text(
            'Некоторые разрешения были отклонены. Откройте настройки, чтобы предоставить доступ к камере, микрофону и фото.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Открыть настройки'),
            ),
          ],
        ),
      );
      if (shouldOpen == true) {
        await openAppSettings();
      }
    }
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search',
        prefixIcon: Icon(Icons.search, color: onSurface.withOpacity(0.7)),
        filled: true,
        fillColor: onSurface.withOpacity(0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: onSurface.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppColors.primary.withOpacity(0.8)),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
      style: TextStyle(color: onSurface),
    );
  }
}

enum ChatFilter { all, unread }

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelected});

  final ChatFilter selected;
  final ValueChanged<ChatFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final filters = ChatFilter.values;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: filters.map((filter) {
        final isSelected = selected == filter;
        final label = switch (filter) {
          ChatFilter.all => 'All',
          ChatFilter.unread => 'Unread',
        };
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onSelected(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withOpacity(isSelected ? 0 : 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? Colors.black
                          : Colors.white.withOpacity(0.8),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.chats,
    required this.onTap,
    required this.onTogglePin,
    required this.onArchive,
  });

  final List<ChatPreview> chats;
  final ValueChanged<ChatPreview> onTap;
  final ValueChanged<ChatPreview> onTogglePin;
  final ValueChanged<ChatPreview> onArchive;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (chats.isEmpty) {
      return Center(
        child: Text(
          'No chats',
          style: TextStyle(color: onSurface.withOpacity(0.7)),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      itemCount: chats.length,
      separatorBuilder: (_, __) => Divider(
        color: onSurface.withOpacity(0.1),
        height: 18,
        thickness: 1,
        indent: 14,
        endIndent: 14,
      ),
      itemBuilder: (context, index) {
        final chat = chats[index];
        return Dismissible(
          key: ValueKey(chat.chatId),
          direction: DismissDirection.endToStart,
          background: const _SwipeBackground(),
          confirmDismiss: (_) => _showActions(context, chat),
          onDismissed: (_) => onArchive(chat),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: chat.color,
                  backgroundImage: chat.avatarUrl != null
                      ? NetworkImage(chat.avatarUrl!)
                      : null,
                  child: chat.avatarUrl != null
                      ? null
                      : Text(
                          chat.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                if (chat.isUnread)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              chat.name,
              style: TextStyle(color: onSurface, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              chat.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: onSurface.withOpacity(0.8)),
            ),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  chat.time,
                  style: TextStyle(
                    color: onSurface.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                if (chat.pinned)
                  Icon(Icons.push_pin, size: 16, color: onSurface),
              ],
            ),
            onTap: () => onTap(chat),
          ),
        );
      },
    );
  }

  Future<bool> _showActions(BuildContext context, ChatPreview chat) async {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final surface = Theme.of(context).colorScheme.surface;
    final action = await showModalBottomSheet<_ChatAction>(
      context: context,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetAction(
                icon: chat.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                label: chat.pinned ? 'Открепить' : 'Закрепить',
                color: onSurface,
                onTap: () => Navigator.of(context).pop(_ChatAction.pin),
              ),
              const SizedBox(height: 8),
              _SheetAction(
                icon: Icons.archive_outlined,
                label: 'Архивировать',
                color: onSurface,
                onTap: () => Navigator.of(context).pop(_ChatAction.archive),
              ),
            ],
          ),
        );
      },
    );

    if (action == _ChatAction.pin) {
      onTogglePin(chat);
      return false;
    }

    if (action == _ChatAction.archive) {
      return true;
    }

    return false;
  }
}

enum _ChatAction { pin, archive }

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.7),
            Theme.of(context).colorScheme.primary.withOpacity(0.45),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.push_pin, color: Colors.white70),
          SizedBox(width: 18),
          Icon(Icons.archive_outlined, color: Colors.white70),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
