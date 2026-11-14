import 'package:flutter/material.dart';
import 'package:lumii_quest/core/icons/app_icons.dart';
import 'package:lumii_quest/features/profile/domain/zodiac.dart';

/// Banner with an overlapping avatar, display name (+ zodiac) and bio — the
/// same visual as the Settings profile header.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.displayName,
    required this.bio,
    this.avatarUrl,
    this.bannerUrl,
    this.zodiac,
    this.topRight,
  });

  final String displayName;
  final String bio;
  final String? avatarUrl;
  final String? bannerUrl;
  final ZodiacSign? zodiac;
  final Widget? topRight;

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
              if (topRight != null)
                Positioned(top: 8, right: 8, child: topRight!),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (zodiac != null) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: zodiac!.label,
                        child: AppIcon(
                          zodiac!.icon,
                          size: 22,
                          color: onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ],
                ),
                if (bio.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(bio, style: theme.textTheme.bodyMedium),
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
