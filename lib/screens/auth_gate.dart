import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/super_alfaeq_catalog_importer.dart';
import 'admin_dashboard.dart';
import 'customer_session_shell.dart';
import 'developer_page.dart';
import 'driver_center_page.dart';
import 'login_page.dart';
import 'merchant_portal_page.dart';
import 'world_home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final AuthService _auth = AuthService();
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _auth.authStateChanges.listen((user) {
      if (user != null) {
        _auth.startPresence();
        SuperAlfaeqCatalogImporter().importIfNeeded().catchError((_) => 0);
      } else {
        _auth.stopPresence();
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    _auth.stopPresence();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_auth.currentUser == null) return;
    if (state == AppLifecycleState.resumed) {
      _auth.startPresence();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _auth.stopPresence();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) return const LoginPage();

    return FutureBuilder<String>(
      future: _auth.role(),
      builder: (context, roleSnapshot) {
        if (roleSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = roleSnapshot.data ?? 'customer';
        switch (role) {
          case 'owner':
          case 'admin':
            SuperAlfaeqCatalogImporter().importIfNeeded().catchError((_) => 0);
            return const AdminDashboard();
          case 'developer':
            return const DeveloperPage();
          case 'merchant':
            return const MerchantPortalPage();
          case 'driver':
            return const DriverCenterPage();
          case 'customer':
          case 'finance':
          case 'support':
          default:
            return const CustomerSessionShell(child: WorldHomePage());
        }
      },
    );
  }
}
