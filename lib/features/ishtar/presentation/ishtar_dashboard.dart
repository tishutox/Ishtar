import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/account/data/account_repository.dart';
import 'package:lumii_quest/features/ishtar/data/ishtar_repository.dart';
import 'package:lumii_quest/features/ishtar/data/local_llm_service.dart';
import 'package:lumii_quest/features/ishtar/presentation/ishtar_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signed-in root: a light-gray dashboard (sidebar) with the active Ishtar chat
/// shifted to its right.
class IshtarDashboard extends StatefulWidget {
  const IshtarDashboard({super.key});

  @override
  State<IshtarDashboard> createState() => _IshtarDashboardState();
}

class _IshtarDashboardState extends State<IshtarDashboard> {
  static const Color _sidebarColor = Color(0xFFF6F6F6);
  static const Color _dangerColor = Color(0xFFE53935);

  final _repository = IshtarRepository();
  final _searchController = TextEditingController();
  List<IshtarConversation> _conversations = [];
  IshtarConversation? _active;
  bool _sidebarOpen = false;
  bool _loaded = false;
  double _swipeDelta = 0;
  double _grabDelta = 0;

  List<IshtarConversation> get _filteredConversations {
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

  List<Widget> _buildChatListItems(List<IshtarConversation> conversations) {
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

  Widget _buildChatTile(IshtarConversation conversation) {
    final selected = conversation.id == _active?.id;
    return Builder(
      builder: (tileContext) => ListTile(
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
        onLongPress: () => _showChatActions(tileContext, conversation),
      ),
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

  void _onConversationChanged(IshtarConversation updated) {
    print('[Ishtar] _onConversationChanged: id=${updated.id}, '
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
      print('[Ishtar] _onConversationChanged setState error: $e');
    }
    print('[Ishtar] _onConversationChanged: now ${_conversations.length} chats');
    unawaited(_repository.saveConversations(_conversations));
  }

  void _openConversation(String id) {
    _searchController.clear();
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

  void _newChat() {
    _searchController.clear();
    setState(() {
      _active = _repository.createConversation();
      _sidebarOpen = false;
    });
  }

  void _onSwipeStart(DragStartDetails details) {
    _swipeDelta = 0;
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    _swipeDelta += details.delta.dx;
  }

  void _onSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (!_sidebarOpen && (_swipeDelta > 60 || velocity > 300)) {
      setState(() => _sidebarOpen = true);
    }
    _swipeDelta = 0;
  }

  void _onGrabStart(DragStartDetails details) {
    _grabDelta = 0;
  }

  void _onGrabUpdate(DragUpdateDetails details) {
    _grabDelta += details.delta.dx;
  }

  void _onGrabEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_grabDelta < -40 || velocity < -300) {
      if (_sidebarOpen) setState(() => _sidebarOpen = false);
    } else if (_grabDelta > 40 || velocity > 300) {
      if (!_sidebarOpen) setState(() => _sidebarOpen = true);
    }
    _grabDelta = 0;
  }

  Future<void> _showChatActions(
    BuildContext tileContext,
    IshtarConversation conversation,
  ) async {
    final box = tileContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !box.hasSize) return;

    // Anchor the menu next to the tile — to its right and below it (or above
    // it when there is not enough room below) — so it no longer covers the
    // chat it belongs to.
    final tileTopLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final tileBottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    const horizontalGap = 8.0;
    const verticalGap = 4.0;
    // Approximate height of the three-item menu. `showMenu` clamps it to the
    // overlay anyway, so a small over/under-estimate is harmless.
    const estimatedMenuHeight = 160.0;
    final placeBelow =
        tileBottomRight.dy + verticalGap + estimatedMenuHeight <=
        overlay.size.height;
    final left = tileBottomRight.dx + horizontalGap;
    final top = (placeBelow
            ? tileBottomRight.dy + verticalGap
            : tileTopLeft.dy - estimatedMenuHeight - verticalGap)
        .clamp(0.0, overlay.size.height)
        .toDouble();

    final position = RelativeRect.fromLTRB(left, top, left, top);

    final action = await showMenu<_ChatAction>(
      context: context,
      position: position,
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<_ChatAction>(
          value: _ChatAction.rename,
          child: const _ChatMenuItem(icon: AppIcons.penLine, label: 'Rename'),
        ),
        PopupMenuItem<_ChatAction>(
          value: conversation.pinned ? _ChatAction.unpin : _ChatAction.pin,
          child: _ChatMenuItem(
            icon: conversation.pinned ? AppIcons.pinOff : AppIcons.pin,
            label: conversation.pinned ? 'Unpin' : 'Pin',
          ),
        ),
        PopupMenuItem<_ChatAction>(
          value: _ChatAction.delete,
          child: const _ChatMenuItem(
            icon: AppIcons.trash,
            label: 'Delete',
            color: _dangerColor,
          ),
        ),
      ],
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

  Future<void> _renameConversation(IshtarConversation conversation) async {
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

  Future<void> _deleteConversation(IshtarConversation conversation) async {
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
    final contentWidth = (screenWidth * 0.80).clamp(0.0, 300.0).toDouble();
    const grabBufferWidth = 16.0;
    final sidebarWidth = contentWidth + grabBufferWidth;

    return Scaffold(
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _onSwipeStart,
            onHorizontalDragUpdate: _onSwipeUpdate,
            onHorizontalDragEnd: _onSwipeEnd,
            child: active == null
                ? const SizedBox.shrink()
                : IshtarPage(
                    key: ValueKey(active.id),
                    conversation: active,
                    onChanged: _onConversationChanged,
                    onToggleSidebar: _toggleSidebar,
                  ),
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
                child: _buildSidebar(context, contentWidth, grabBufferWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    double contentWidth,
    double bufferWidth,
  ) {
    final conversations = _filteredConversations;
    return Container(
      width: contentWidth + bufferWidth,
      color: _sidebarColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: contentWidth,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSidebarHeader(),
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
                        _buildNewChatButton(),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: () => context.push('/settings'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
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
          ),
          SizedBox(
            width: bufferWidth,
            child: _buildGrabHandle(),
          ),
        ],
      ),
    );
  }

  Widget _buildGrabHandle() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onGrabStart,
      onHorizontalDragUpdate: _onGrabUpdate,
      onHorizontalDragEnd: _onGrabEnd,
      child: Center(
        child: Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFC7C7CC),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarHeader() {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _buildSearchField(),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Row(
          children: [
            const AppIcon(AppIcons.search, size: 20, color: Color(0xFF8E8E93)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search chat content...',
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              InkWell(
                onTap: _searchController.clear,
                child: const AppIcon(
                  AppIcons.x,
                  size: 16,
                  color: Color(0xFF8E8E93),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewChatButton() {
    return Tooltip(
      message: 'New chat',
      child: Material(
        color: Colors.black,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _newChat,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: AppIcon(
                AppIcons.messageCirclePlus,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
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

class _ChatMenuItem extends StatelessWidget {
  const _ChatMenuItem({required this.icon, required this.label, this.color});

  final String icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? const Color(0xFF1A1A1A);
    return Row(
      children: [
        AppIcon(icon, color: foreground),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: foreground)),
      ],
    );
  }
}

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
