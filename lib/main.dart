import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/firebase/firebase_service.dart';
import 'login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'الفائق يمن',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
        fontFamily: 'sans-serif',
      ),
      routes: {'/home': (_) => const HomeScreen(), '/login': (_) => const LoginScreen()},
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = snapshot.data;
          if (user == null) return const LoginScreen();
          return FutureBuilder<IdTokenResult>(
            future: user.getIdTokenResult(true),
            builder: (context, tokenSnapshot) {
              if (tokenSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              final claims = tokenSnapshot.data?.claims;
              final whatsappVerified = claims?['whatsappVerified'] == true;
              if (user.emailVerified || whatsappVerified) return const HomeScreen();
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            },
          );
        },
      ),
    );
  }
}
