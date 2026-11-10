import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:lumii_quest/core/routing/app_router.dart';
import 'package:lumii_quest/core/theme/app_theme.dart';

class LumiiQuestApp extends StatefulWidget {
  const LumiiQuestApp({super.key});

  @override
  State<LumiiQuestApp> createState() => _LumiiQuestAppState();
}

class _LumiiQuestAppState extends State<LumiiQuestApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    unawaited(_handleInitialLink());
    _linkSubscription = _appLinks.uriLinkStream.listen(_openLink);
  }

  Future<void> _handleInitialLink() async {
    final uri = await _appLinks.getInitialLink();
    if (uri != null) {
      _openLink(uri);
    }
  }

  void _openLink(Uri uri) {
    final location = profileLocationFromUri(uri);
    if (location != null) {
      appRouter.go(location);
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Ishtar',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: appRouter,
    );
  }
}
