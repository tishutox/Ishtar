import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lumii_quest/features/ishtar/presentation/ishtar_dashboard.dart';
import 'package:lumii_quest/features/me/data/pin_service.dart';
import 'package:lumii_quest/features/me/presentation/pin_lock_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Root screen: opens directly into the Ishtar AI chat. Signed-in users are
/// gated by the optional login PIN; signed-out users can chat immediately.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final StreamSubscription<AuthState> _authSubscription;
  bool _pinEnabled = false;
  bool _pinChecked = false;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.signedIn) {
        setState(() => _pinChecked = false);
        unawaited(_loadPinState());
      }
      setState(() {});
    });
    unawaited(_loadPinState());
  }

  Future<void> _loadPinState() async {
    final enabled = await PinService().isEnabled();
    if (!mounted) return;
    setState(() {
      _pinEnabled = enabled;
      _pinChecked = true;
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
      return const IshtarDashboard();
    }
    if (!_pinChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_pinEnabled) {
      return PinLockPage(
        onUnlocked: () => setState(() => _pinEnabled = false),
      );
    }
    return const IshtarDashboard();
  }
}
