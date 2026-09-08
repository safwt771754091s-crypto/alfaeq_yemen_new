import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/admin_dashboard.dart';
import 'screens/ai_assistant_page.dart';
import 'screens/auth_gate.dart';
import 'screens/developer_page.dart';
import 'screens/my_orders_page.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AlfaeqYemenApp());
}

class AlfaeqYemenApp extends StatelessWidget {
  const AlfaeqYemenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'الفائق يمن',
      theme: ThemeData(useMaterial3: true),
      home: const AuthGate(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _openAdmin(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
  }

  void _openDeveloper(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperPage()));
  }

  Future<void> _signOut(BuildContext context) async {
    await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الفائق يمن'),
          actions: [
            IconButton(
              tooltip: 'ذكاء الفائق',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AiAssistantPage()),
              ),
            ),
            IconButton(
              tooltip: 'طلباتي',
              icon: const Icon(Icons.receipt_long_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyOrdersPage()),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'ai') Navigator.push(context, MaterialPageRoute(builder: (_) => const AiAssistantPage()));
                if (value == 'orders') Navigator.push(context, MaterialPageRoute(builder: (_) => const MyOrdersPage()));
                if (value == 'admin') _openAdmin(context);
                if (value == 'developer') _openDeveloper(context);
                if (value == 'logout') _signOut(context);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'ai', child: ListTile(leading: Icon(Icons.auto_awesome), title: Text('ذكاء الفائق'))),
                PopupMenuItem(value: 'orders', child: ListTile(leading: Icon(Icons.receipt_long_outlined), title: Text('طلباتي وتتبع الطلبات'))),
                PopupMenuItem(value: 'admin', child: ListTile(leading: Icon(Icons.admin_panel_settings_outlined), title: Text('لوحة الإدارة'))),
                PopupMenuItem(value: 'developer', child: ListTile(leading: Icon(Icons.code), title: Text('صفحة المطور'))),
                PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('تسجيل الخروج'))),
              ],
            ),
          ],
        ),
        body: const Center(
          child: Text(
            'أهلاً في الفائق يمن',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
