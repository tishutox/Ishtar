import 'dart:async';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/account/data/account_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _usernamePattern = RegExp(r'^[A-Za-z0-9._-]+$');

enum _AuthMode { signUp, signIn }

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<MePage> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _birthdayController = TextEditingController();

  _AuthMode _mode = _AuthMode.signUp;
  bool _showLanding = true;
  int _currentStep = 0;
  DateTime? _birthday;
  String? _country;
  bool _isSubmitting = false;
  bool _isUploadingAvatar = false;
  Uint8List? _registrationAvatarBytes;
  String? _registrationAvatarExtension;
  late final StreamSubscription<AuthState> _authSubscription;

  static const _countries = <String>[
    'Austria',
    'Belgium',
    'Bulgaria',
    'Croatia',
    'Cyprus',
    'Czech Republic',
    'Denmark',
    'Estonia',
    'Finland',
    'France',
    'Germany',
    'Greece',
    'Hungary',
    'Ireland',
    'Italy',
    'Latvia',
    'Lithuania',
    'Luxembourg',
    'Malta',
    'Netherlands',
    'Poland',
    'Portugal',
    'Romania',
    'Slovakia',
    'Slovenia',
    'Spain',
    'Sweden',
    'Switzerland',
    'Norway',
    'United States',
    'Canada',
    'Mexico',
    'Australia',
    'New Zealand',
    'Japan',
    'China',
  ];

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      _handleAuthState,
    );
  }

  void _handleAuthState(AuthState state) {
    if (!mounted) {
      return;
    }
    setState(() {});

    final session = state.session;
    if (state.event == AuthChangeEvent.signedIn &&
        session != null &&
        _registrationAvatarBytes != null &&
        !_isUploadingAvatar) {
      unawaited(_uploadPendingRegistrationAvatar(session.user));
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _birthdayController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _birthday = selected;
      _birthdayController.text =
          '${selected.day.toString().padLeft(2, '0')}.'
          '${selected.month.toString().padLeft(2, '0')}.'
          '${selected.year}';
    });
  }

  Future<void> _submit() async {
    final error = _currentStepError();
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _isSubmitting = true);
    final auth = Supabase.instance.client.auth;

    try {
      if (_mode == _AuthMode.signUp) {
        final response = await auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {
            'first_name': _firstNameController.text.trim(),
            'last_name': _lastNameController.text.trim(),
            'display_name': _displayNameController.text.trim(),
            'username': _usernameController.text.trim(),
            'birthday': _birthday!.toIso8601String().split('T').first,
            'country': _country,
          },
        );
        if (!mounted) {
          return;
        }
        final needsConfirmation = response.session == null;
        if (response.session != null &&
            _registrationAvatarBytes != null &&
            !_isUploadingAvatar) {
          await _uploadPendingRegistrationAvatar(response.session!.user);
        }
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              needsConfirmation
                  ? 'Account created. Check your email to confirm it.'
                  : 'Your account has been created.',
            ),
          ),
        );
        context.go('/');
      } else {
        await auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) {
          return;
        }
        context.go('/');
      }
    } on AuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyAuthError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
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

    setState(() => _isSubmitting = true);
    try {
      await AccountRepository().deleteCurrentAccount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your account has been deleted.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Account could not be deleted: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _pickRegistrationAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (image == null || !mounted) {
      return;
    }

    try {
      final avatar = await _readAvatar(image);
      setState(() {
        _registrationAvatarBytes = avatar.bytes;
        _registrationAvatarExtension = avatar.extension;
      });
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _uploadPendingRegistrationAvatar(User user) async {
    final bytes = _registrationAvatarBytes;
    final extension = _registrationAvatarExtension;
    if (bytes == null || extension == null || _isUploadingAvatar) {
      return;
    }

    setState(() => _isUploadingAvatar = true);
    try {
      await _uploadAvatar(user: user, bytes: bytes, extension: extension);
      if (mounted) {
        setState(() {
          _registrationAvatarBytes = null;
          _registrationAvatarExtension = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account and profile image saved.')),
        );
      }
    } on StorageException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account created, but image failed: ${error.message}',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created, but the image could not be saved.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAvatar = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return _SignedInProfile(
        user: user,
        onEdit: () async {
          await context.push<bool>('/edit-profile');
          if (mounted) setState(() {});
        },
        onView: (username) => context.push('/u/$username'),
        onFriends: () => context.push('/friends'),
        onDeleteAccount: _isSubmitting ? null : _deleteAccount,
        onSignOut: _signOut,
      );
    }

    if (_showLanding) {
      return _buildLanding(context);
    }

    return _buildWizard(context);
  }

  Widget _buildLanding(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppIcon(AppIcons.heart, size: 64, color: primary),
                  const SizedBox(height: 16),
                  Text(
                    'Ishtar',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect with friends and communities.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: () => _start(_AuthMode.signUp),
                    icon: const AppIcon(AppIcons.userPlus),
                    label: const Text('Sign Up'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _start(_AuthMode.signIn),
                    icon: const AppIcon(AppIcons.logIn),
                    label: const Text('Sign In'),
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: 'Back',
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go('/'),
              icon: const AppIcon(AppIcons.chevronLeft),
            ),
          ),
        ),
      ],
    );
  }

  void _start(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _showLanding = false;
      _currentStep = 0;
    });
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      setState(() {
        _showLanding = true;
        _currentStep = 0;
      });
    }
  }

  String? _currentStepError() {
    final isSignUp = _mode == _AuthMode.signUp;
    if (!isSignUp) {
      return _emailValidator(_emailController.text) ??
          _passwordValidator(_passwordController.text);
    }
    switch (_currentStep) {
      case 0:
        return _requiredMax(_firstNameController.text, 'First name', 30) ??
            _requiredMax(_lastNameController.text, 'Last name', 30) ??
            _requiredMax(_displayNameController.text, 'Display name', 20);
      case 1:
        return _usernameValidator(_usernameController.text) ??
            _emailValidator(_emailController.text) ??
            _passwordValidator(_passwordController.text);
      case 2:
        return _required(_birthdayController.text, 'Birthday') ??
            (_country == null ? 'Country is required.' : null);
    }
    return null;
  }

  void _next() {
    final error = _currentStepError();
    if (error != null) {
      _showMessage(error);
      return;
    }
    setState(() => _currentStep++);
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _buildWizard(BuildContext context) {
    final isSignUp = _mode == _AuthMode.signUp;
    final steps = _steps(isSignUp);
    final isLastStep = _currentStep == steps.length - 1;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: _goBack,
                icon: const AppIcon(AppIcons.chevronLeft),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isSignUp ? 'Create account' : 'Welcome back',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_currentStep + 1}/${steps.length}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final offset = Tween<Offset>(
                begin: const Offset(0.06, 0),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: offset, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<int>(_currentStep),
              child: ListView(
                padding: ContentLayout.pagePadding,
                children: [steps[_currentStep]],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                if (_currentStep > 0) ...[
                  OutlinedButton(
                    onPressed: _goBack,
                    child: const Text('Back'),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : isLastStep
                        ? _submit
                        : _next,
                    icon: AppIcon(
                      _isSubmitting
                          ? AppIcons.hourglass
                          : isLastStep
                          ? (isSignUp
                                ? AppIcons.userPlus
                                : AppIcons.logIn)
                          : AppIcons.chevronRight,
                    ),
                    label: Text(
                      _isSubmitting
                          ? 'Please wait...'
                          : isLastStep
                          ? (isSignUp ? 'Create account' : 'Sign in')
                          : 'Next',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _steps(bool isSignUp) {
    if (!isSignUp) {
      return [_accountStep(isSignUp: false)];
    }
    return [
      _profileStep(),
      _accountStep(isSignUp: true),
      _detailsStep(),
    ];
  }

  Widget _profileStep() {
    return ContentLayout.widthBox(
      child: _AuthSection(
        title: 'Profile',
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProfileImagePicker(
                imageBytes: _registrationAvatarBytes,
                onPressed: _pickRegistrationAvatar,
              ),
              const SizedBox(height: 18),
              _ResponsiveFields(
                children: [
                  _AuthTextField(
                    controller: _firstNameController,
                    label: 'First name',
                    icon: AppIcons.idCard,
                    maxLength: 30,
                    validator: (value) =>
                        _requiredMax(value, 'First name', 30),
                  ),
                  _AuthTextField(
                    controller: _lastNameController,
                    label: 'Last name',
                    icon: AppIcons.idCard,
                    maxLength: 30,
                    validator: (value) =>
                        _requiredMax(value, 'Last name', 30),
                  ),
                ],
              ),
              ContentLayout.sectionGap,
              _AuthTextField(
                controller: _displayNameController,
                label: 'Display name',
                icon: AppIcons.userRound,
                maxLength: 20,
                validator: (value) =>
                    _requiredMax(value, 'Display name', 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _accountStep({required bool isSignUp}) {
    return ContentLayout.widthBox(
      child: _AuthSection(
        title: 'Account',
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSignUp) ...[
                _AuthTextField(
                  controller: _usernameController,
                  label: 'Username',
                  icon: AppIcons.userRound,
                  maxLength: 20,
                  validator: _usernameValidator,
                ),
                ContentLayout.sectionGap,
              ],
              _ResponsiveFields(
                children: [
                  _AuthTextField(
                    controller: _emailController,
                    label: 'Email',
                    icon: AppIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                    validator: _emailValidator,
                  ),
                  _AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: AppIcons.eyeClosed,
                    obscureText: true,
                    validator: _passwordValidator,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsStep() {
    return ContentLayout.widthBox(
      child: _AuthSection(
        title: 'Details',
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ResponsiveFields(
                children: [
                  _AuthTextField(
                    controller: _birthdayController,
                    label: 'Birthday',
                    icon: AppIcons.cakeSlice,
                    readOnly: true,
                    onTap: _pickBirthday,
                    validator: (value) => _required(value, 'Birthday'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _country,
                    icon: const AppIcon(AppIcons.chevronDown),
                    decoration: _fieldDecoration(
                      label: 'Country',
                      icon: AppIcons.earth,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    items: _countries
                        .map(
                          (country) => DropdownMenuItem<String>(
                            value: country,
                            child: Text(country),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _country = value);
                    },
                    validator: (value) =>
                        value == null ? 'Country is required.' : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignedInProfile extends StatelessWidget {
  const _SignedInProfile({
    required this.user,
    required this.onEdit,
    required this.onView,
    required this.onFriends,
    required this.onDeleteAccount,
    required this.onSignOut,
  });

  final User user;
  final VoidCallback onEdit;
  final ValueChanged<String> onView;
  final VoidCallback onFriends;
  final VoidCallback? onDeleteAccount;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName = metadata['display_name'] as String?;
    final username = metadata['username'] as String?;
    final avatarUrl = metadata['avatar_url'] as String?;

    return ListView(
      padding: ContentLayout.pagePadding,
      children: [
        ContentLayout.widthBox(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CircularProfileImage(
                    size: 84,
                    imageProvider: avatarUrl == null
                        ? null
                        : NetworkImage(avatarUrl),
                    fallback: Text(
                      (displayName ?? user.email ?? '?')[0].toUpperCase(),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName ?? 'Ishtar member',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (username != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => onView(username),
                      child: Text('@$username'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onEdit,
                    icon: const AppIcon(AppIcons.pencilRuler),
                    label: const Text('Edit Profile'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onFriends,
                    icon: const AppIcon(AppIcons.bookHeart),
                    label: const Text('Friends list'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onSignOut,
                    icon: const AppIcon(AppIcons.logOut),
                    label: const Text('Sign out'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onPressed: onDeleteAccount,
                    icon: const AppIcon(AppIcons.trash),
                    label: const Text('Delete account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<({Uint8List bytes, String extension})> _readAvatar(XFile image) async {
  final bytes = await image.readAsBytes();
  if (bytes.lengthInBytes > 5 * 1024 * 1024) {
    throw const FormatException('The image must be smaller than 5 MB.');
  }
  return (bytes: bytes, extension: _imageExtension(image.name));
}

Future<void> _uploadAvatar({
  required User user,
  required Uint8List bytes,
  required String extension,
}) async {
  final path = '${user.id}/avatar.$extension';
  final storage = Supabase.instance.client.storage.from('avatars');
  await storage.uploadBinary(
    path,
    bytes,
    fileOptions: FileOptions(
      upsert: true,
      contentType: _imageContentType(extension),
      cacheControl: '3600',
    ),
  );

  final publicUrl = storage.getPublicUrl(path);
  final avatarUrl = '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  await Supabase.instance.client.auth.updateUser(
    UserAttributes(data: {'avatar_url': avatarUrl}),
  );
  await Supabase.instance.client
      .from('profiles')
      .update({'avatar_url': avatarUrl})
      .eq('id', user.id);
}

String _imageExtension(String fileName) {
  final extension = fileName.split('.').last.toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => 'jpg',
    'png' => 'png',
    'webp' => 'webp',
    _ => throw const FormatException('Choose a JPG, PNG or WebP image.'),
  };
}

String _imageContentType(String extension) {
  return switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

String _friendlyAuthError(Object error) {
  final message = error.toString();
  final normalized = message.toLowerCase();
  if (normalized.contains('failed host lookup') ||
      normalized.contains('socketexception')) {
    return 'Supabase could not be reached. Check your internet or DNS connection.';
  }
  return 'Account request failed. Please try again.';
}

class _AuthSection extends StatelessWidget {
  const _AuthSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }
}

class _ProfileImagePicker extends StatelessWidget {
  const _ProfileImagePicker({
    required this.imageBytes,
    required this.onPressed,
  });

  final Uint8List? imageBytes;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        _CircularProfileImage(
          size: 80,
          imageProvider: imageBytes == null ? null : MemoryImage(imageBytes!),
          fallback: AppIcon(AppIcons.imageUp, color: primary, size: 30),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const AppIcon(AppIcons.imageUp),
          label: Text(
            imageBytes == null
                ? 'Select profile image'
                : 'Change profile image',
          ),
        ),
      ],
    );
  }
}

class _CircularProfileImage extends StatelessWidget {
  const _CircularProfileImage({
    required this.size,
    required this.imageProvider,
    required this.fallback,
  });

  final double size;
  final ImageProvider? imageProvider;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final image = imageProvider;

    return Align(
      alignment: Alignment.center,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: ColoredBox(
            color: primary.withValues(alpha: 0.14),
            child: image == null
                ? Center(child: fallback)
                : Image(
                    image: image,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (_, _, _) => Center(child: fallback),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) ContentLayout.sectionGap,
                children[index],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) const SizedBox(width: 14),
              Expanded(child: children[index]),
            ],
          ],
        );
      },
    );
  }
}

class _AuthTextField extends StatefulWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    this.keyboardType,
    this.maxLength,
    this.obscureText = false,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController controller;
  final String label;
  final String icon;
  final String? Function(String?) validator;
  final TextInputType? keyboardType;
  final int? maxLength;
  final bool obscureText;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  State<_AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<_AuthTextField> {
  bool _isHidden = true;

  @override
  Widget build(BuildContext context) {
    final isPassword = widget.obscureText;
    return TextFormField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: isPassword && _isHidden,
      readOnly: widget.readOnly,
      onTap: widget.onTap,
      maxLength: widget.maxLength,
      inputFormatters: [
        if (widget.maxLength != null)
          LengthLimitingTextInputFormatter(widget.maxLength),
      ],
      decoration: _fieldDecoration(
        label: widget.label,
        icon: widget.icon,
        prefix: isPassword
            ? IconButton(
                tooltip: _isHidden ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _isHidden = !_isHidden),
                icon: AppIcon(_isHidden ? AppIcons.eyeClosed : AppIcons.eye),
              )
            : null,
      ),
      validator: widget.validator,
    );
  }
}

InputDecoration _fieldDecoration({
  required String label,
  required String icon,
  Widget? prefix,
}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: prefix ?? AppIcon(icon),
    counterText: '',
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
  );
}

String? _required(String? value, String label) {
  if (value == null || value.trim().isEmpty) {
    return '$label is required.';
  }
  return null;
}

String? _requiredMax(String? value, String label, int maxLength) {
  final requiredError = _required(value, label);
  if (requiredError != null) {
    return requiredError;
  }
  if (value!.trim().length > maxLength) {
    return '$label can be up to $maxLength characters.';
  }
  return null;
}

String? _emailValidator(String? value) {
  final requiredError = _required(value, 'Email');
  if (requiredError != null) {
    return requiredError;
  }
  if (!value!.contains('@') || !value.contains('.')) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? _usernameValidator(String? value) {
  final requiredError = _required(value, 'Username');
  if (requiredError != null) {
    return requiredError;
  }
  final username = value!.trim();
  if (username.length > 20) {
    return 'Username can be up to 20 characters.';
  }
  if (!_usernamePattern.hasMatch(username)) {
    return 'Use only A-Z, a-z, 0-9, -, _ and .';
  }
  return null;
}

String? _passwordValidator(String? value) {
  final requiredError = _required(value, 'Password');
  if (requiredError != null) {
    return requiredError;
  }
  final password = value!.trim();
  if (password.length < 8) {
    return 'Password needs at least 8 characters.';
  }
  return null;
}
