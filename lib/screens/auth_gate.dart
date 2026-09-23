import 'dart:async';
import 'package:flutter/material.dart';
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
  @override State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = const AuthService();
  StreamSubscription<AuthUser?>? _sub;
  @override void initState() {
    super.initState();
    _sub = _auth.authStateChanges.listen((user) {
      if (user != null) {
        _auth.startPresence();
        SuperAlfaeqCatalogImporter().importIfNeeded().catchError((_) => 0);
      } else {
        _auth.stopPresence();
      }
    });
  }
  @override void dispose() { _sub?.cancel(); _auth.stopPresence(); super.dispose(); }
  @override Widget build(BuildContext context) => StreamBuilder<AuthUser?>(
    stream: _auth.authStateChanges,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (snapshot.data == null) return const LoginPage();
      return FutureBuilder<String>(
        future: _auth.role(),
        builder: (context, roleSnapshot) {
          if (roleSnapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          switch (roleSnapshot.data ?? 'customer') {
            case 'owner':
            case 'admin': return const AdminDashboard();
            case 'developer': return const DeveloperPage();
            case 'merchant': return const MerchantPortalPage();
            case 'driver': return const DriverCenterPage();
            default: return const CustomerSessionShell(child: WorldHomePage());
          }
        },
      );
    },
  );
}
