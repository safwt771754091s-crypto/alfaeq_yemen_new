import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'driver_center_page.dart';
import 'login_page.dart';
import 'super_app_shell_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == null) return const LoginPage();
        return FutureBuilder<String>(
          future: AuthService().role(),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            final role = roleSnapshot.data ?? 'customer';
            if (role == 'driver') return const DriverCenterPage();
            return const SuperAppShellPage();
          },
        );
      },
    );
  }
}
