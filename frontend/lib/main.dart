import 'package:flutter/material.dart';

void main() {
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الفائق يمن - Alfaeq Yemen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        fontFamily: 'Cairo',
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.flash_on_rounded,
                  size: 80,
                  color: Colors.cyanAccent,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'الفائق يمن',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Alfaeq Yemen Super App',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.cyan,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(
                color: Colors.cyanAccent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
