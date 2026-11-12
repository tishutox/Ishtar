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

  String get _firstName {
    final raw = Supabase.instance.client.auth.currentUser
        ?.userMetadata?['first_name'];
    return raw is String && raw.isNotEmpty ? raw : '';
  }

  String get _lastName {
    final raw = Supabase.instance.client.auth.currentUser
        ?.userMetadata?['last_name'];
    return raw is String && raw.isNotEmpty ? raw : '';
  }

  String get _email =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  String? get _birthday {
    final raw =
        Supabase.instance.client.auth.currentUser?.userMetadata?['birthday'];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  DateTime? get _birthdayDate =>
      _birthday == null ? null : DateTime.tryParse(_birthday!);

  String get _birthdayDisplay {
    final value = _birthday;
    if (value == null) return '';
    final parts = value.split('-');
    if (parts.length != 3) return value;
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

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

  Future<void> _editFirstName() async {
    final result = await _promptForText(
      title: 'First name',
      label: 'First name',
      initialValue: _firstName,
      textCapitalization: TextCapitalization.words,
      validator: _nameValidator,
    );
    if (result == null || result == _firstName || !mounted) return;
    try {
      await _repository.updateFirstName(result);
      _showSnackBar('First name updated.');
      await _load();
    } catch (error) {
      _showSnackBar('First name could not be updated: $error');
    }
  }

  Future<void> _editLastName() async {
    final result = await _promptForText(
      title: 'Last name',
      label: 'Last name',
      initialValue: _lastName,
      textCapitalization: TextCapitalization.words,
      validator: _nameValidator,
    );
    if (result == null || result == _lastName || !mounted) return;
    try {
      await _repository.updateLastName(result);
      _showSnackBar('Last name updated.');
      await _load();
    } catch (error) {
      _showSnackBar('Last name could not be updated: $error');
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

  Future<void> _editBirthday() async {
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BirthdaySheet(initialDate: _birthdayDate),
    );
    if (selected == null || !mounted) return;
    try {
      await _repository.updateBirthday(
        selected.toIso8601String().split('T').first,
      );
      if (!mounted) return;
      _showSnackBar('Birthday updated.');
      setState(() {});
    } catch (error) {
      _showSnackBar('Birthday could not be updated: $error');
    }
  }

  Future<void> _changePassword() async {
    final newPassword = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PasswordSheet(),
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
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _DeleteAccountSheet(),
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
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TextInputSheet(
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
                  label: 'First name',
                  value: _firstName,
                  onTap: _editFirstName,
                ),
                _AccountTile(
                  label: 'Last name',
                  value: _lastName,
                  onTap: _editLastName,
                ),
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
                _AccountTile(
                  label: 'Birthday',
                  value: _birthdayDisplay,
                  onTap: _editBirthday,
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

class _TextInputSheet extends StatefulWidget {
  const _TextInputSheet({
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
  State<_TextInputSheet> createState() => _TextInputSheetState();
}

class _TextInputSheetState extends State<_TextInputSheet> {
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: widget.keyboardType,
                  textCapitalization: widget.textCapitalization,
                  decoration: InputDecoration(
                    labelText: widget.label,
                    prefixText: widget.prefixText,
                  ),
                  validator: widget.validator,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet();

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
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
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_newPasswordController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change password',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Form(
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
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    shape: const StadiumBorder(),
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountSheet extends StatelessWidget {
  const _DeleteAccountSheet();

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Delete account?',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'This permanently deletes your account, profile, friendships, '
              'notifications and chats. This cannot be undone.',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 48),
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BirthdaySheet extends StatefulWidget {
  const _BirthdaySheet({this.initialDate});

  final DateTime? initialDate;

  @override
  State<_BirthdaySheet> createState() => _BirthdaySheetState();
}

class _BirthdaySheetState extends State<_BirthdaySheet> {
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date =
        widget.initialDate ?? DateTime(now.year - 18, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Birthday',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 400,
              child: CalendarDatePicker(
                initialDate: _date,
                firstDate: DateTime(now.year - 120),
                lastDate: now,
                onDateChanged: (date) => setState(() => _date = date),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_date),
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 48),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _nameValidator(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) {
    return 'This field is required.';
  }
  if (name.length > 30) {
    return 'Must be 30 characters or fewer.';
  }
  return null;
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
