import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores and verifies the optional 4-digit device login PIN.
///
/// The PIN is never written in plain text: a random salt plus a salted
/// SHA-256 digest are kept in [SharedPreferences]. A 4-digit PIN only has
/// 10,000 combinations, so this is convenience protection (keeping casual
/// passers-by out), not strong encryption.
class PinService {
  static const _saltKey = 'login_pin_salt_v1';
  static const _hashKey = 'login_pin_hash_v1';

  final Random _random = Random.secure();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_hashKey) ?? '').isNotEmpty;
  }

  Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey) ?? '';
    final stored = prefs.getString(_hashKey) ?? '';
    if (salt.isEmpty || stored.isEmpty) return false;
    return stored == await _digest(salt, pin);
  }

  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, await _digest(salt, pin));
  }

  Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saltKey);
    await prefs.remove(_hashKey);
  }

  Future<String> _digest(String salt, String pin) async {
    final hash = await Sha256().hash(utf8.encode('$salt:$pin'));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _newSalt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
