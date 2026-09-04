import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'core/auth/app_role.dart';
import 'core/auth/role_service.dart';

class AccountRegistrationScreen extends StatefulWidget {
  const AccountRegistrationScreen({super.key});
  @override State<AccountRegistrationScreen> createState() => _AccountRegistrationScreenState();
}

class _AccountRegistrationScreenState extends State<AccountRegistrationScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  AppRole _role = AppRole.customer;
  bool _loading = false;

  String get _cleanEmail => _email.text.trim().replaceAll(RegExp(r'\s+'), '');
  bool _validEmail(String email) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  Future<void> _register() async {
    final email = _cleanEmail;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل الاسم'))); return;
    }
    if (!_validEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل بريداً صحيحاً مثل name@gmail.com'))); return;
    }
    if (_password.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('كلمة المرور يجب أن تكون 6 أحرف على الأقل'))); return;
    }
    setState(() => _loading = true);
    try {
      await RoleService.instance.createAccount(name: _name.text.trim(), email: email, phone: _phone.text.trim(), password: _password.text, requestedRole: _role);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إنشاء الحساب بنجاح')));
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'invalid-email' => 'البريد الإلكتروني غير صحيح. تأكد من عدم وجود مسافات.',
        'email-already-in-use' => 'هذا البريد مستخدم مسبقاً. استخدم تسجيل الدخول.',
        'weak-password' => 'كلمة المرور ضعيفة، استخدم 6 أحرف أو أكثر.',
        'network-request-failed' => 'تعذر الاتصال بـ Firebase. تحقق من الإنترنت.',
        _ => 'تعذر إنشاء الحساب: ${e.message ?? e.code}',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إنشاء الحساب: $e')));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override void dispose() { _name.dispose(); _email.dispose(); _phone.dispose(); _password.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب - الفائق يمن')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('أنشئ حسابك في الفائق يمن', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        DropdownButtonFormField<AppRole>(value: _role, decoration: const InputDecoration(labelText: 'نوع الحساب', border: OutlineInputBorder()), items: const [AppRole.customer, AppRole.merchant, AppRole.driver].map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(), onChanged: (v) => setState(() => _role = v ?? AppRole.customer)),
        const SizedBox(height: 12),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder())),
        const SizedBox(height: 12), TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder())),
        const SizedBox(height: 12), TextField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', hintText: 'name@gmail.com', border: OutlineInputBorder())),
        const SizedBox(height: 12), TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
        const SizedBox(height: 20), SizedBox(height: 52, child: _loading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: _register, child: const Text('إنشاء الحساب', style: TextStyle(fontSize: 18)))),
        const SizedBox(height: 12), const Text('صلاحيات المدير ومدير النظام لا تُمنح من التسجيل العام.', textAlign: TextAlign.center),
      ]),
    ),
  );
}
