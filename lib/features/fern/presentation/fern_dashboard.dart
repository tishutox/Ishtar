import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/account/data/account_repository.dart';
import 'package:lumii_quest/features/fern/data/fern_repository.dart';
import 'package:lumii_quest/features/fern/data/local_llm_service.dart';
import 'package:lumii_quest/features/fern/presentation/fern_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in root: a light-gray dashboard (sidebar) with the active Fern chat
/// shifted to its right.
class FernDashboard extends StatefulWidget {
  const FernDashboard({super.key});

  @override
  State<FernDashboard> createState() => _FernDashboardState();
}

class _FernDashboardState extends State<FernDashboard> {
  static const Color _sidebarColor = Color(0xFFF6F6F6);
  static const Color _searchFill = Color(0xFFEFEFF0);
  static const Color _dangerColor = Color(0xFFE53935);

  final _repository = FernRepository();
  final _searchController = TextEditingController();
  List<FernConversation> _conversations = [];
  FernConversation? _active;
  bool _sidebarOpen = false;
  bool _loaded = false;

  List<FernConversation> get _filteredConversations {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _conversations;
    return _conversations.where((c) {
      if (c.title.toLowerCase().contains(query)) return true;
      return c.messages.any((m) => m.content.toLowerCase().contains(query));
    }).toList();
  }

  String? get _avatarUrl {
    final value =
        Supabase.instance.client.auth.currentUser?.userMetadata?['avatar_url'];
    return value is String && value.isNotEmpty ? value : null;
  }

  String _timeGroup(DateTime updatedAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(updatedAt.year, updatedAt.month, updatedAt.day);
    final days = today.difference(date).inDays;
    if (days <= 0) return 'Today';
    if (days < 7) return 'Last week';
    if (days < 30) return 'Last month';
    if (days < 365) return 'Last year';
    return 'An eternity ago';
  }

  List<Widget> _buildChatListItems(List<FernConversation> conversations) {
    final items = <Widget>[];
    final pinned = conversations.where((c) => c.pinned).toList();
    final unpinned = conversations.where((c) => !c.pinned).toList();

    if (pinned.isNotEmpty) {
      items.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Pinned',
            style: TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
        ),
      );
      for (final conversation in pinned) {
        items.add(_buildChatTile(conversation));
      }
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(height: 24, color: Color(0xFFE4E4E8)),
        ),
      );
    }

    String? currentGroup;
    for (final conversation in unpinned) {
      final group = _timeGroup(conversation.updatedAt);
      if (group != currentGroup) {
        currentGroup = group;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              group,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
            ),
          ),
        );
      }
      items.add(_buildChatTile(conversation));
    }
    return items;
  }

  Widget _buildChatTile(FernConversation conversation) {
    final selected = conversation.id == _active?.id;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      tileColor: selected ? const Color(0xFFE4E4E8) : Colors.transparent,
      title: Text(
        conversation.title.isEmpty ? 'New chat' : conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF1A1A1A),
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => _openConversation(conversation.id),
      onLongPress: () => _showChatActions(conversation),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    unawaited(_load());
    unawaited(_syncKeepMemories());
  }

  Future<void> _syncKeepMemories() async {
    LocalLlmService.instance.keepMemories = await AccountRepository()
        .getKeepMemories();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final conversations = await _repository.loadConversations();
    if (!mounted) return;
    setState(() {
      _conversations = conversations;
      _loaded = true;
      // Always start in a fresh, unsaved chat. It becomes a saved conversation
      // (and shows up in the sidebar) only once the user sends a message.
      _active = _repository.createConversation();
    });
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  void _onConversationChanged(FernConversation updated) {
    print('[Fern] _onConversationChanged: id=${updated.id}, '
        'messages=${updated.messages.length}, title="${updated.title}"');
    try {
      setState(() {
        if (_active?.id == updated.id) {
          _active = updated;
        }
        final index = _conversations.indexWhere((c) => c.id == updated.id);
        if (index == -1) {
          _conversations.insert(0, updated);
        } else {
          _conversations[index] = updated;
        }
        _sortConversations();
      });
    } catch (e) {
      print('[Fern] _onConversationChanged setState error: $e');
    }
    print('[Fern] _onConversationChanged: now ${_conversations.length} chats');
    unawaited(_repository.saveConversations(_conversations));
  }

  void _openConversation(String id) {
    setState(() {
      for (final conversation in _conversations) {
        if (conversation.id == id) {
          _active = conversation;
          break;
        }
      }
      _sidebarOpen = false;
    });
  }

  void _toggleSidebar() {
    setState(() => _sidebarOpen = !_sidebarOpen);
  }

  Future<void> _showChatActions(FernConversation conversation) async {
    final action = await showModalBottomSheet<_ChatAction>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const AppIcon(AppIcons.penLine),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, _ChatAction.rename),
            ),
            ListTile(
              leading: AppIcon(
                conversation.pinned ? AppIcons.pinOff : AppIcons.pin,
              ),
              title: Text(conversation.pinned ? 'Unpin' : 'Pin'),
              onTap: () => Navigator.pop(
                context,
                conversation.pinned ? _ChatAction.unpin : _ChatAction.pin,
              ),
            ),
            ListTile(
              leading: const AppIcon(AppIcons.trash, color: _dangerColor),
              title: const Text(
                'Delete',
                style: TextStyle(color: _dangerColor),
              ),
              onTap: () => Navigator.pop(context, _ChatAction.delete),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _ChatAction.rename:
        await _renameConversation(conversation);
        break;
      case _ChatAction.pin:
        await _setPinned(conversation.id, true);
        break;
      case _ChatAction.unpin:
        await _setPinned(conversation.id, false);
        break;
      case _ChatAction.delete:
        await _deleteConversation(conversation);
        break;
    }
  }

  Future<void> _renameConversation(FernConversation conversation) async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialTitle: conversation.title),
    );
    if (newTitle == null || !mounted) return;
    setState(() {
      final index = _conversations.indexWhere((c) => c.id == conversation.id);
      if (index != -1) _conversations[index].title = newTitle;
      if (_active?.id == conversation.id) {
        _active = _active!.copyWith(title: newTitle);
      }
    });
    await _repository.saveConversations(_conversations);
  }

  Future<void> _setPinned(String id, bool pinned) async {
    setState(() {
      final index = _conversations.indexWhere((c) => c.id == id);
      if (index != -1) _conversations[index].pinned = pinned;
      if (_active?.id == id) {
        _active = _active!.copyWith(pinned: pinned);
      }
      _sortConversations();
    });
    await _repository.saveConversations(_conversations);
  }

  Future<void> _deleteConversation(FernConversation conversation) async {
    setState(() {
      _conversations.removeWhere((c) => c.id == conversation.id);
      if (_active?.id == conversation.id) {
        _active = _repository.createConversation();
      }
      _sortConversations();
    });
    await _repository.saveConversations(_conversations);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final active = _active;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = (screenWidth * 0.80).clamp(0.0, 300.0).toDouble();

    return Scaffold(
      body: Stack(
        children: [
          active == null
              ? const SizedBox.shrink()
              : FernPage(
                  key: ValueKey(active.id),
                  conversation: active,
                  onChanged: _onConversationChanged,
                  onToggleSidebar: _toggleSidebar,
                ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_sidebarOpen,
              child: AnimatedOpacity(
                opacity: _sidebarOpen ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: GestureDetector(
                  onTap: _toggleSidebar,
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: sidebarWidth,
            child: AnimatedSlide(
              offset: _sidebarOpen ? Offset.zero : const Offset(-1, 0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(24),
                ),
                child: _buildSidebar(context, sidebarWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, double width) {
    final conversations = _filteredConversations;
    return Container(
      width: width,
      color: _sidebarColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search chat content...',
                      prefixIcon: const AppIcon(AppIcons.search, size: 24),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      filled: true,
                      fillColor: _searchFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'No chats yet',
                        style: TextStyle(color: Color(0xFF8E8E93)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      children: _buildChatListItems(conversations),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildAvatar(),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => context.push('/settings'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text(
                      'Settings',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = _avatarUrl;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => context.push('/own-profile'),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: const Color(0xFFE4E4E8),
        backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
        child: avatarUrl == null
            ? const AppIcon(AppIcons.circleUserRound, size: 22)
            : null,
      ),
    );
  }
}

enum _ChatAction { rename, pin, unpin, delete }

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Rename chat'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(hintText: 'Chat title'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
