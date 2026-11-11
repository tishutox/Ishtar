import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/me/data/pin_service.dart';
import 'package:lumii_quest/features/me/presentation/pin_pad.dart';

const Color _dangerColor = Color(0xFFE53935);

/// Bottom-sheet version of the login-PIN settings. Set or remove the
/// 4-digit device login PIN.
class PinSheet extends StatefulWidget {
  const PinSheet({super.key});

  @override
  State<PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<PinSheet> {
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Log-In Pin',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            const Text(
              'Require a 4-digit PIN to open the app.',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
            const SizedBox(height: 20),
            if (!_loaded)
              const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_enabled)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _removePin,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _dangerColor,
                    side: BorderSide(
                      color: _dangerColor.withValues(alpha: 0.55),
                    ),
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const AppIcon(AppIcons.delete, color: _dangerColor),
                  label: const Text('Remove PIN'),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _setPin,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const AppIcon(AppIcons.lock),
                  label: const Text('Set up PIN'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
