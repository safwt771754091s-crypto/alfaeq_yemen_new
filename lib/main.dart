import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'الفائق يمن',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      // جعل الواجهة الرئيسية هي الـ Super App مباشرة
      home: const HomeScreen(),
    );
  }
