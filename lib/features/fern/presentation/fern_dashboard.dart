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
    String? currentGroup;
    for (final conversation in conversations) {
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
      final selected = conversation.id == _active?.id;
      items.add(
        ListTile(
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
        ),
      );
    }
    return items;
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
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _onConversationChanged(FernConversation updated) {
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
