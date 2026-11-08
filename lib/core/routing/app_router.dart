import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
export 'package:lumii_quest/core/routing/profile_links.dart';
import 'package:lumii_quest/features/account/presentation/account_page.dart';
import 'package:lumii_quest/features/me/presentation/own_profile_page.dart';
import 'package:lumii_quest/features/me/presentation/privacy_page.dart';
import 'package:lumii_quest/features/me/presentation/settings_page.dart';
import 'package:lumii_quest/features/profile/presentation/edit_profile_page.dart';
import 'package:lumii_quest/features/profile/presentation/public_profile_page.dart';
import 'package:lumii_quest/widgets/app_shell.dart';

final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const AppShell()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
    GoRoute(path: '/account', builder: (_, _) => const AccountPage()),
    GoRoute(path: '/privacy', builder: (_, _) => const PrivacyPage()),
    GoRoute(path: '/edit-profile', builder: (_, _) => const EditProfilePage()),
    GoRoute(path: '/own-profile', builder: (_, _) => const OwnProfilePage()),
    GoRoute(
      path: '/u/:username',
      builder: (_, state) =>
          PublicProfilePage(username: state.pathParameters['username'] ?? ''),
    ),
  ],
  errorBuilder: (_, state) =>
      Scaffold(body: Center(child: Text('Page not found: ${state.uri.path}'))),
);
