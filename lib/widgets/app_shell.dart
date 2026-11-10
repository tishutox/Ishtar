import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumii_quest/features/ishtar/presentation/ishtar_dashboard.dart';
import 'package:lumii_quest/features/me/presentation/me_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Root screen: shows the sign-in wizard until a user is authenticated,
/// then the Ishtar AI chat.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      _,
    ) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Supabase.instance.client.auth.currentUser == null) {
      return const MePage();
    }
    return const IshtarDashboard();
  }
}
