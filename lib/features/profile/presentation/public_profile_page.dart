import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/profile/data/profile_repository.dart';
import 'package:lumii_quest/features/profile/domain/user_profile.dart';
import 'package:lumii_quest/features/profile/domain/zodiac.dart';
import 'package:lumii_quest/features/profile/presentation/profile_header.dart';

/// Public profile view reachable via the `lumiiquest://u/<username>` deep link
/// or the `https://tishutox.github.io/Ishtar/app/u/<username>` web URL.
class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({super.key, required this.username});

  final String username;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _repository = ProfileRepository();
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await _repository.getByUsername(widget.username);
    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          icon: const AppIcon(AppIcons.chevronLeft),
        ),
        title: Text(widget.username),
        surfaceTintColor: Colors.transparent,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final profile = _profile;
    if (profile == null) {
      return const Center(child: Text('Profile not found.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ProfileHeader(
          displayName: profile.displayName,
          bio: profile.bio,
          avatarUrl: profile.avatarUrl,
          bannerUrl: profile.bannerUrl,
          zodiac: ZodiacSign.fromName(profile.zodiac),
        ),
      ],
    );
  }
}
