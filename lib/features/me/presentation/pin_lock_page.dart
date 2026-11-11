import 'package:flutter/material.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/me/data/pin_service.dart';
import 'package:lumii_quest/features/me/presentation/pin_pad.dart';

/// Full-screen lock shown at app launch when a login PIN is set.
class PinLockPage extends StatefulWidget {
  const PinLockPage({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<PinLockPage> createState() => _PinLockPageState();
}

class _PinLockPageState extends State<PinLockPage> {
  final _service = PinService();
  String? _error;

  Future<void> _submit(String pin) async {
    final ok = await _service.verify(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'Incorrect PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(AppIcons.lock, size: 40, color: Colors.black),
                const SizedBox(height: 16),
                Text(
                  'Enter your PIN',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 20,
                  child: _error == null
                      ? null
                      : Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFE53935),
                            fontSize: 14,
                          ),
                        ),
                ),
                const SizedBox(height: 8),
                PinPad(onCompleted: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
