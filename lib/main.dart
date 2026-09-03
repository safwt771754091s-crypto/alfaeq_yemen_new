import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:async';

import 'core/firebase/firebase_service.dart';

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
      home: const HomeScreen(),
    );
  }
}

class CartModel extends ChangeNotifier {
  static final CartModel instance = CartModel._internal();
  CartModel._internal();

  final List<Map<String, dynamic>> items = [];

  double get totalAmount {
    double sum = 0;
    for (var item in items) {