import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/account/data/account_repository.dart';
import 'package:lumii_quest/features/ishtar/data/local_llm_service.dart';
import 'package:lumii_quest/widgets/settings_section.dart';

const Color _onColor = Color(0xFF34C759);
const Color _offColor = Color(0xFFE53935);

/// Data privacy, safety and AI preferences.
class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  final _repository = AccountRepository();
  bool _keepMemories = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final value = await _repository.getKeepMemories();
    LocalLlmService.instance.keepMemories = value;
    if (mounted) {
      setState(() => _keepMemories = value);
    }
  }

  Future<void> _toggleKeepMemories() async {
    if (_saving) return;
    final next = !_keepMemories;
    setState(() {
      _keepMemories = next;
      _saving = true;
    });
    LocalLlmService.instance.keepMemories = next;
    try {
      await _repository.setKeepMemories(next);
    } catch (_) {
      // Revert on failure so the toggle always reflects the persisted value.
      LocalLlmService.instance.keepMemories = !next;
      if (mounted) setState(() => _keepMemories = !next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
        title: const Text('Data Privacy & Safety'),
      ),
      body: ListView(
        padding: ContentLayout.pagePadding,
        children: [
          ContentLayout.widthBox(
            child: const SettingsSection(
              title: 'Safety',
              dividerIndent: 16,
              children: [
                _PrivacyLinkTile(label: 'Blocked Users'),
                _PrivacyLinkTile(label: 'Support'),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const SettingsSection(
              title: 'Data Privacy',
              dividerIndent: 16,
              children: [
                _PrivacyLinkTile(label: 'Privacy Policy'),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: SettingsSection(
              title: 'Artificial Intelligence',
              dividerIndent: 16,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                  title: const Text('Keep Memories'),
                  trailing: _PowerToggle(
                    isOn: _keepMemories,
                    onTap: _toggleKeepMemories,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyLinkTile extends StatelessWidget {
  const _PrivacyLinkTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      title: Text(label),
      trailing: Transform.translate(
        offset: const Offset(4, 0),
        child: AppIcon(AppIcons.chevronRight, color: primary),
      ),
    );
  }
}

class _PowerToggle extends StatelessWidget {
  const _PowerToggle({required this.isOn, required this.onTap});

  final bool isOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isOn ? _onColor : _offColor;
    return Material(
      color: color.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AppIcon(AppIcons.power, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}
