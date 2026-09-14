import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'admin_dashboard.dart';
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

class _AuthGateState extends State<AuthGate> {
  final AuthService _auth = AuthService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _auth.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == null) return const LoginPage();

        return FutureBuilder<String>(
          future: _auth.role(),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            final role = roleSnapshot.data ?? 'customer';

            switch (role) {
              case 'owner':
              case 'admin':
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
                return const WorldHomePage();
            }
          },
        );
      },
    );
  }
}
