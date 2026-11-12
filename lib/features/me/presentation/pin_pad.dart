import 'package:flutter/material.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';

/// A self-contained 4-digit PIN entry: four status dots plus a numeric
/// keypad. Calls [onCompleted] once four digits have been entered, then
/// clears itself.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onCompleted});

  final ValueChanged<String> onCompleted;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _entered = '';

  void _addDigit(String digit) {
    if (_entered.length >= 4) return;
    final next = _entered + digit;
    setState(() => _entered = next);
    if (next.length == 4) {
      final pin = next;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _entered = '');
        widget.onCompleted(pin);
      });
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Widget _digitKey(String digit) {
    return _KeypadButton(
      onTap: () => _addDigit(digit),
      child: Text(
        digit,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _backspaceKey() {
    return _KeypadButton(
      onTap: _backspace,
      child: const AppIcon(AppIcons.delete, size: 24, color: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PinDots(filled: _entered.length),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_digitKey('1'), _digitKey('2'), _digitKey('3')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_digitKey('4'), _digitKey('5'), _digitKey('6')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [_digitKey('7'), _digitKey('8'), _digitKey('9')],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 76, height: 76),
            _digitKey('0'),
            _backspaceKey(),
          ],
        ),
      ],
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.filled});

  final int filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? Colors.black : Colors.transparent,
              border: Border.all(
                color: i < filled ? Colors.black : const Color(0xFFC7C7CC),
                width: 2,
              ),
            ),
          ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Center(child: child),
        ),
      ),
    );
  }
}
