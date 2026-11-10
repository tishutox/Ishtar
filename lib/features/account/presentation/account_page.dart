import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/account/data/account_repository.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:lumii_quest/widgets/settings_section.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _repository = AccountRepository();
  final _profileRepository = ProfileRepository();
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }
    try {
      final profile = await _profileRepository.getById(user.id);
      if (mounted && profile != null) {
        setState(() => _profile = profile);
      }
    } catch (_) {
      // Fall back to auth metadata; the tiles still render their values.
    }
  }

  String get _username {
    final raw =
        Supabase.instance.client.auth.currentUser?.userMetadata?['username'];
    return _profile?.username ??
        (raw is String && raw.isNotEmpty ? raw : '');
  }

  String get _displayName {
    final raw = Supabase.instance.client.auth.currentUser
        ?.userMetadata?['display_name'];
    return _profile?.displayName ??
        (raw is String && raw.isNotEmpty ? raw : '');
  }

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _editUsername() async {
    final result = await _promptForText(
      title: 'Username',
      label: 'Username',
      initialValue: _username,
      prefixText: '@',
      textCapitalization: TextCapitalization.none,
      validator: _usernameValidator,
    );
    if (result == null || result == _username || !mounted) return;
    try {
      await _repository.updateUsername(result);
      _showSnackBar('Username updated.');
      await _load();
    } catch (error) {
      _showSnackBar('Username could not be updated: $error');
    }
  }

  Future<void> _editDisplayName() async {
    final result = await _promptForText(
      title: 'Display name',
      label: 'Display name',
      initialValue: _displayName,
      validator: _displayNameValidator,
    );
    if (result == null || result == _displayName || !mounted) return;
    try {
      await _repository.updateDisplayName(result);
      _showSnackBar('Display name updated.');
      await _load();
    } catch (error) {
      _showSnackBar('Display name could not be updated: $error');
    }
  }

  Future<void> _editEmail() async {
    final result = await _promptForText(
      title: 'Email',
      label: 'Email',
      initialValue: _email,
      keyboardType: TextInputType.emailAddress,
      textCapitalization: TextCapitalization.none,
      validator: _emailValidator,
    );
    if (result == null || result == _email || !mounted) return;
    try {
      await _repository.updateEmail(result);
      _showSnackBar('Email updated.');
    } catch (error) {
      _showSnackBar('Email could not be updated: $error');
    }
  }

  Future<void> _changePassword() async {
    final newPassword = await showDialog<String>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (newPassword == null || !mounted) return;
    try {
      await _repository.updatePassword(newPassword);
      _showSnackBar('Password updated.');
    } catch (error) {
      _showSnackBar('Password could not be updated: $error');
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, profile, friendships, notifications and chats. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const AppIcon(AppIcons.trash),
            label: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _repository.deleteCurrentAccount();
      _showSnackBar('Your account has been deleted.');
    } catch (error) {
      _showSnackBar('Account could not be deleted: $error');
    }
  }

  Future<String?> _promptForText({
    required String title,
    required String label,
    required String initialValue,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    String? prefixText,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: title,
        label: label,
        initialValue: initialValue,
        validator: validator,
        keyboardType: keyboardType,
        prefixText: prefixText,
        textCapitalization: textCapitalization,
      ),
    );
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
        title: const Text('Account'),
      ),
      body: ListView(
        padding: ContentLayout.pagePadding,
        children: [
          ContentLayout.widthBox(
            child: SettingsSection(
              title: 'Account Information',
              dividerIndent: 16,
              children: [
                _AccountTile(
                  label: 'Username',
                  value: _username,
                  onTap: _editUsername,
                ),
                _AccountTile(
                  label: 'Displayname',
                  value: _displayName,
                  onTap: _editDisplayName,
                ),
                _AccountTile(
                  label: 'Email',
                  value: _email,
                  onTap: _editEmail,
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: SettingsSection(
              title: 'Danger Zone',
              dividerIndent: 16,
              children: [
                _AccountTile(
                  label: 'Change Password',
                  onTap: _changePassword,
                ),
                _AccountTile(
                  label: 'Delete Account',
                  labelColor: Theme.of(context).colorScheme.error,
                  onTap: _deleteAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.label,
    this.value,
    this.labelColor,
    this.onTap,
  });

  final String label;
  final String? value;
  final Color? labelColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.62);
    final accent = labelColor ?? primary;
    return ListTile(
      title: Text(label, style: TextStyle(color: labelColor)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: muted, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Transform.translate(
            offset: const Offset(4, 0),
            child: AppIcon(AppIcons.chevronRight, color: accent, size: 20),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    this.validator,
    this.keyboardType,
    this.prefixText,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final String title;
  final String label;
  final String initialValue;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String? prefixText;
  final TextCapitalization textCapitalization;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.textCapitalization,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixText: widget.prefixText,
            border: const OutlineInputBorder(),
          ),
          validator: widget.validator,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

String? _usernameValidator(String? value) {
  final username = value?.trim() ?? '';
  if (username.isEmpty) {
    return 'Username is required.';
  }
  if (!RegExp(r'^[A-Za-z0-9._-]{1,20}$').hasMatch(username)) {
    return 'Use 1-20 letters, numbers, dots, underscores or dashes.';
  }
  return null;
}

String? _displayNameValidator(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) {
    return 'Display name is required.';
  }
  if (name.length > 50) {
    return 'Display name must be 50 characters or fewer.';
  }
  return null;
}

String? _emailValidator(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) {
    return 'Email is required.';
  }
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? _passwordValidator(String? value) {
  final password = value?.trim() ?? '';
  if (password.length < 8) {
    return 'Password needs at least 8 characters.';
  }
  return null;
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_newPasswordController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _newPasswordController,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'New password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: AppIcon(
                    _obscure ? AppIcons.eye : AppIcons.eyeOff,
                  ),
                ),
              ),
              validator: _passwordValidator,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value != _newPasswordController.text) {
                  return 'Passwords do not match.';
                }
                return _passwordValidator(value);
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
