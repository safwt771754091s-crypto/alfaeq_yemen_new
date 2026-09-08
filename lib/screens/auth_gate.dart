import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'driver_center_page.dart';
import 'location_required_page.dart';
import 'login_page.dart';
import 'world_home_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.data == null) return const LoginPage();
        return FutureBuilder<String>(
          future: AuthService().role(),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final role = roleSnapshot.data ?? 'customer';
            if (role == 'driver') return const DriverCenterPage();
            final privileged = role == 'admin' || role == 'owner' || role == 'developer';
            if (privileged) return const WorldHomePage();
            return FutureBuilder<bool>(
              future: AuthService().hasRequiredLocation(),
              builder: (context, locationSnapshot) {
                if (locationSnapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
                if (locationSnapshot.data != true) {
                  return LocationRequiredPage(
                    onLocationReady: (latitude, longitude) async {
                      await AuthService().saveUserLocation(
                        location: GeoPoint(latitude, longitude),
                        source: 'required_onboarding',
                      );
                    },
                  );
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
