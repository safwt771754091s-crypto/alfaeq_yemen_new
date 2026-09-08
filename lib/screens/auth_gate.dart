import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'driver_center_page.dart';
import 'location_required_page.dart';
import 'login_page.dart';
import 'world_home_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<void> _saveRequiredLocation(double latitude, double longitude) async {
    await AuthService().saveUserLocation(
      location: GeoPoint(latitude, longitude),
      source: 'required_onboarding',
    );
    if (mounted) setState(() {});
  }

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
            final privileged = role == 'admin' || role == 'owner' || role == 'developer';
            if (privileged) return const WorldHomePage();
            return FutureBuilder<bool>(
              future: AuthService().hasRequiredLocation(),
              builder: (context, locationSnapshot) {
                if (locationSnapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                if (locationSnapshot.data != true) {
                  return LocationRequiredPage(onLocationReady: _saveRequiredLocation);
                }
                return const WorldHomePage();
              },
            );
          },
        );
      },
    );
  }
}
