import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:lumii_quest/features/profile/domain/zodiac.dart';
import 'package:lumii_quest/features/profile/presentation/profile_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's own profile, with banner/avatar header, a "More"
/// sheet (real account data) and edit/copy-link actions.
class OwnProfilePage extends StatefulWidget {
  const OwnProfilePage({super.key});

  @override
  State<OwnProfilePage> createState() => _OwnProfilePageState();
}

class _OwnProfilePageState extends State<OwnProfilePage> {
  final _repository = ProfileRepository();
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final profile = await _repository.getById(user.id);
    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  String? _metadata(String key) {
    final raw =
        Supabase.instance.client.auth.currentUser?.userMetadata?[key];
    return raw is String && raw.isNotEmpty ? raw : null;
  }

  String? get _birthday => _metadata('birthday');

  String _formatBirthday(String value) {
    final parts = value.split('-');
    if (parts.length != 3) return value;
    return '${parts[2]}.${parts[1]}.${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final displayName = profile?.displayName ?? _metadata('display_name') ?? '';
    final username = _metadata('username') ?? '';
    final avatarUrl = profile?.avatarUrl ?? _metadata('avatar_url');
    final zodiac = zodiacFromIso(_birthday);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
        title: Text(displayName.isEmpty ? 'Profile' : displayName),
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ProfileHeader(
                  displayName: displayName,
                  bio: profile?.bio ?? '',
                  avatarUrl: avatarUrl,
                  bannerUrl: profile?.bannerUrl,
                  zodiac: zodiac,
                  topRight: _topRightActions(context, username),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showMore,
                    icon: const AppIcon(AppIcons.chevronUp, size: 18),
                    label: const Text('More'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _topRightActions(BuildContext context, String username) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _headerAction(
          tooltip: 'Copy profile link',
          icon: AppIcons.link,
          onPressed: () => _copyProfileLink(context, username),
        ),
        const SizedBox(width: 8),
        _headerAction(
          tooltip: 'Edit profile',
          icon: AppIcons.pencilRuler,
          onPressed: () => context.push('/edit-profile'),
        ),
      ],
    );
  }

  Widget _headerAction({
    required String tooltip,
    required String icon,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        icon: AppIcon(icon, color: theme.colorScheme.primary),
      ),
    );
  }

  Future<void> _copyProfileLink(BuildContext context, String username) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://tishutox.github.io/Ishtar/app/u/$username'),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile link copied.')));
    }
  }

  void _showMore() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => _MoreSheet(
        firstName: _metadata('first_name') ?? '',
        lastName: _metadata('last_name') ?? '',
        birthday: _birthday == null ? '' : _formatBirthday(_birthday!),
      ),
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({
    required this.firstName,
    required this.lastName,
    required this.birthday,
  });

  final String firstName;
  final String lastName;
  final String birthday;

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
              'More',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _row('First name', firstName),
            _row('Last name', lastName),
            _row('Birthday', birthday),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93))),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: Color(0xFF1A1A1A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
