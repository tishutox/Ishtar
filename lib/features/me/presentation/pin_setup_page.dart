import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/me/data/pin_service.dart';
import 'package:lumii_quest/features/me/presentation/pin_pad.dart';
import 'package:lumii_quest/widgets/settings_section.dart';

const Color _onColor = Color(0xFF34C759);
const Color _dangerColor = Color(0xFFE53935);

/// Set or remove the 4-digit device login PIN.
class PinSetupPage extends StatefulWidget {
  const PinSetupPage({super.key});

  @override
  State<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends State<PinSetupPage> {
  final _service = PinService();
  bool _enabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await _service.isEnabled();
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _loaded = true;
      });
    }
  }

  Future<void> _setPin() async {
    final first = await _promptPin('Choose a PIN');
    if (first == null || !mounted) return;
    final second = await _promptPin('Confirm your PIN');
    if (second == null || !mounted) return;
    if (first != second) {
      _showSnack('PINs do not match. Try again.');
      return;
    }
    await _service.setPin(first);
    if (!mounted) return;
    _showSnack('Login PIN enabled.');
    await _load();
  }

  Future<void> _removePin() async {
    final entered = await _promptPin('Enter your current PIN');
    if (entered == null || !mounted) return;
    final ok = await _service.verify(entered);
    if (!ok) {
      if (mounted) _showSnack('Incorrect PIN.');
      return;
    }
    await _service.removePin();
    if (!mounted) return;
    _showSnack('Login PIN removed.');
    await _load();
  }

  Future<String?> _promptPin(String title) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              PinPad(
                onCompleted: (pin) => Navigator.of(sheetContext).pop(pin),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
        title: const Text('Log-In Pin'),
      ),
      body: ListView(
        padding: ContentLayout.pagePadding,
        children: [
          ContentLayout.widthBox(
            child: SettingsSection(
              title: 'Log-In Pin',
              dividerIndent: 16,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  title: const Text('Log-In Pin'),
                  subtitle: const Text(
                    'Require a 4-digit PIN to open the app.',
                  ),
                  trailing: Text(
                    _enabled ? 'On' : 'Off',
                    style: TextStyle(
                      color: _enabled ? _onColor : const Color(0xFF8E8E93),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'When enabled, you have to enter your PIN every time you '
                'open the app while signed in.',
                style: TextStyle(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.62),
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ContentLayout.widthBox(
            child: !_loaded
                ? const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _enabled
                ? OutlinedButton.icon(
                    onPressed: _removePin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _dangerColor,
                      side: BorderSide(
                        color: _dangerColor.withValues(alpha: 0.55),
                      ),
                    ),
                    icon: const AppIcon(AppIcons.lock, color: _dangerColor),
                    label: const Text('Remove PIN'),
                  )
                : FilledButton.icon(
                    onPressed: _setPin,
                    icon: const AppIcon(AppIcons.lock),
                    label: const Text('Set up PIN'),
                  ),
          ),
        ],
      ),
    );
  }
}
