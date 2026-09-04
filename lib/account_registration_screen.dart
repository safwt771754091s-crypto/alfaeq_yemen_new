import 'package:flutter/material.dart';

import 'core/auth/app_role.dart';
import 'core/auth/role_service.dart';

class AccountRegistrationScreen extends StatefulWidget {
  const AccountRegistrationScreen({super.key});

  @override
  State<AccountRegistrationScreen> createState() => _AccountRegistrationScreenState();
}

class _AccountRegistrationScreenState extends State<AccountRegistrationScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  AppRole _role = AppRole.customer;
  bool _loading = false;

  Future<void> _register() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل الاسم والبريد وكلمة مرور من 6 أحرف على الأقل')));
      return;
    }
    setState(() => _loading = true);
    try {
      await RoleService.instance.createAccount(
        name: _name.text,
        email: _email.text,
        phone: _phone.text,
        password: _password.text,
        requestedRole: _role,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء الحساب بنجاح')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الحساب: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إنشاء حساب - الفائق يمن')),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('اختر نوع الحساب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            DropdownButtonFormField<AppRole>(
              value: _role,
              decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'نوع الحساب'),
              items: const [AppRole.customer, AppRole.merchant, AppRole.driver]
                  .map((role) => DropdownMenuItem(value: role, child: Text(role.label)))
                  .toList(),
              onChanged: (value) => setState(() => _role = value ?? AppRole.customer),
            ),
            const SizedBox(height: 14),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(height: 52, child: _loading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: _register, child: const Text('إنشاء الحساب', style: TextStyle(fontSize: 18)))),
            const SizedBox(height: 12),
            const Text('حسابات المدير ومدير النظام لا تُمنح من التسجيل العام، بل تُنشأ أو تُعتمد من إدارة النظام.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
