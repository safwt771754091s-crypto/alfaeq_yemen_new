import 'package:flutter/material.dart';
import '../models/app_database.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _passController = TextEditingController();
  String _selectedRole = 'admin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الدخول وإدارة الصلاحيات', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF1A365D),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            const Icon(Icons.admin_panel_settings, size: 70, color: Color(0xFF1A365D)),
            const SizedBox(height: 15),
            const Text('اختر نوع الحساب وصلاحيات الدخول:', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'نوع الصلاحية'),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('المدير العام (صلاحيات كاملة)')),
                DropdownMenuItem(value: 'finance', child: Text('المدير المالي (المحافظ والأرصدة)')),
                DropdownMenuItem(value: 'vendor', child: Text('مدير البائعين والتجار')),
                DropdownMenuItem(value: 'customer', child: Text('مستخدم / عميل عادي')),
              ],
              onChanged: (val) => setState(() => _selectedRole = val!),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
            ),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A365D),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                AppDatabase.currentUser['role'] = _selectedRole;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم تسجيل الدخول بنجاح بصلاحية: $_selectedRole')),
                );
                Navigator.pop(context);
              },
              child: const Text('تسجيل الدخول وتطبيق الصلاحيات', style: TextStyle(color: Colors.white, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

