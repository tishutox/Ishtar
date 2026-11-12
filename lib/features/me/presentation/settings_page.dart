import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/core/responsive/content_layout.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:lumii_quest/widgets/settings_section.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final StreamSubscription<AuthState> _authSubscription;
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // onAuthStateChange replays the last event on subscribe, so a signed-out
    // visitor would receive a stale `signedOut` and immediately navigate away.
    // Only react when this page actually opened while signed in.
    final signedInAtOpen = Supabase.instance.client.auth.currentUser != null;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (mounted &&
          state.event == AuthChangeEvent.signedOut &&
          signedInAtOpen) {
        context.go('/');
      }
    });
    _load();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final profile = await ProfileRepository().getById(user.id);
      if (mounted) {
        setState(() {
          _profile = profile;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editProfile() async {
    await context.push<bool>('/edit-profile');
    if (mounted) _load();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link could not be opened.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
      ),
      body: ListView(
        padding: ContentLayout.pagePadding,
        children: [
          if (user != null) ...[
            ContentLayout.widthBox(child: _buildHeader(user)),
            ContentLayout.sectionGap,
          ],
          ContentLayout.widthBox(
            child: SettingsSection(
              title: 'Account',
              children: [
                if (user != null)
                  _SettingsLinkTile(
                    label: 'Account',
                    icon: AppIcons.circleUserRound,
                    onTap: () => context.push('/account'),
                  ),
                _SettingsLinkTile(
                  label: 'Data Privacy & Safety',
                  icon: AppIcons.fingerprintPattern,
                  onTap: () => context.push('/privacy'),
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: const SettingsSection(
              title: 'App Settings',
              children: [
                _SettingsTile(
                  icon: AppIcons.languages,
                  label: 'Language & Region',
                ),
                _SettingsTile(
                  icon: AppIcons.accessibility,
                  label: 'Accessibility',
                ),
              ],
            ),
          ),
          ContentLayout.sectionGap,
          ContentLayout.widthBox(
            child: SettingsSection(
              title: 'Support Us',
              children: [
                _SettingsLinkTile(
                  label: 'GitHub',
                  icon: AppIcons.github,
                  onTap: () => _openExternal('https://github.com/tishutox/Ishtar'),
                ),
                _SettingsLinkTile(
                  label: 'Instagram',
                  icon: AppIcons.instagram,
                  onTap: () =>
                      _openExternal('https://www.instagram.com/ishtar.ong'),
                ),
              ],
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 24),
            ContentLayout.widthBox(
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _signOut,
                  icon: const AppIcon(AppIcons.logOut),
                  label: const Text('Sign Out'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(User user) {
    if (_loading) {
      return const Card(
        child: SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final rawDisplayName = metadata['display_name'];
    final metadataDisplayName = rawDisplayName is String &&
            rawDisplayName.isNotEmpty
        ? rawDisplayName
        : null;
    final rawAvatar = metadata['avatar_url'];
    final metadataAvatar = rawAvatar is String && rawAvatar.isNotEmpty
        ? rawAvatar
        : null;

    return _ProfileHeader(
      displayName:
          _profile?.displayName ?? metadataDisplayName ?? 'Ishtar member',
      email: user.email ?? '',
      avatarUrl: _profile?.avatarUrl ?? metadataAvatar,
      bannerUrl: _profile?.bannerUrl,
      onEdit: _editProfile,
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.email,
    required this.onEdit,
    this.avatarUrl,
    this.bannerUrl,
  });

  final String displayName;
  final String email;
  final String? avatarUrl;
  final String? bannerUrl;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final surface = theme.colorScheme.surface;
    final onSurface = theme.colorScheme.onSurface;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(aspectRatio: 3, child: _banner(primary)),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: surface.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: 'Edit profile',
                    onPressed: onEdit,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: AppIcon(AppIcons.pencilRuler, color: primary),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(0, -24),
                  child: _avatar(primary, surface),
                ),
                Text(
                  displayName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(Color primary) {
    final placeholder = Center(
      child: AppIcon(AppIcons.image, size: 36, color: primary),
    );
    return ColoredBox(
      color: primary.withValues(alpha: 0.16),
      child: bannerUrl == null
          ? placeholder
          : Image.network(
              bannerUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }

  Widget _avatar(Color primary, Color surface) {
    final fallback = ColoredBox(
      color: primary.withValues(alpha: 0.16),
      child: Center(
        child: Text(
          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
          style: TextStyle(
            color: primary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
    return SizedBox.square(
      dimension: 72,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
        child: ClipOval(
          child: avatarUrl == null
              ? fallback
              : Image.network(
                  avatarUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: AppIcon(icon, color: primary),
      title: Text(label),
      trailing: Transform.translate(
        offset: const Offset(4, 0),
        child: AppIcon(AppIcons.chevronRight, color: primary),
      ),
    );
  }
}

class _SettingsLinkTile extends StatelessWidget {
  const _SettingsLinkTile({required this.label, this.icon, this.onTap});

  final String label;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      leading: icon == null ? null : AppIcon(icon!, color: primary),
      title: Text(label),
      trailing: Transform.translate(
        offset: const Offset(4, 0),
        child: AppIcon(AppIcons.chevronRight, color: primary),
      ),
      onTap: onTap,
    );
  }
}
