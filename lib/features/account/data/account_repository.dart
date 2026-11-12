import 'package:supabase_flutter/supabase_flutter.dart';

class AccountRepository {
  AccountRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> deleteCurrentAccount() async {
    await _client.rpc('delete_own_account');
    try {
      await _client.auth.signOut();
    } catch (_) {
      // The auth user may already be gone after the RPC; in that case the
      // server-side account deletion succeeded and the local session will be
      // invalidated on the next auth refresh/app start.
    }
  }

  Future<void> updateUsername(String username) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your username.');
    }
    await _client
        .from('profiles')
        .update({'username': username})
        .eq('id', user.id);
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your display name.');
    }
    await _client
        .from('profiles')
        .update({'display_name': displayName})
        .eq('id', user.id);
    await _client.auth.updateUser(
      UserAttributes(data: {'display_name': displayName}),
    );
  }

  Future<void> updateFirstName(String firstName) async {
    await _client.auth.updateUser(
      UserAttributes(data: {'first_name': firstName}),
    );
  }

  Future<void> updateLastName(String lastName) async {
    await _client.auth.updateUser(
      UserAttributes(data: {'last_name': lastName}),
    );
  }

  Future<void> updateEmail(String email) async {
    await _client.auth.updateUser(UserAttributes(email: email));
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Stores the birthday as `YYYY-MM-DD` in the auth user metadata (the same
  /// place the sign-up wizard writes it).
  Future<void> updateBirthday(String birthday) async {
    await _client.auth.updateUser(
      UserAttributes(data: {'birthday': birthday}),
    );
  }

  /// Whether the local AI keeps its memories between chats. Defaults to true
  /// (on) when the user is signed out or the row is missing.
  Future<bool> getKeepMemories() async {
    final user = _client.auth.currentUser;
    if (user == null) return true;
    try {
      final row = await _client
          .from('profiles')
          .select('keep_memories')
          .eq('id', user.id)
          .maybeSingle();
      return (row?['keep_memories'] as bool?) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> setKeepMemories(bool value) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Sign in to update your settings.');
    }
    await _client
        .from('profiles')
        .update({'keep_memories': value})
        .eq('id', user.id);
  }
}
