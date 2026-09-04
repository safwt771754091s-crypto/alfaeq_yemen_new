import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'account_registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isResettingPassword = false;

  String get _cleanEmail => _emailController.text.trim().replaceAll(RegExp(r'\s+'), '');

  Future<void> _signIn() async {
    final email = _cleanEmail;
    if (email.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل البريد الإلكتروني وكلمة المرور')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      final user = credential.user!;
      await user.reload();
      final refreshedUser = FirebaseAuth.instance.currentUser!;
      final tokenResult = await refreshedUser.getIdTokenResult(true);
      final whatsappVerified = tokenResult.claims?['whatsappVerified'] == true;

      if (!refreshedUser.emailVerified && !whatsappVerified) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('الحساب غير مؤكد'),
            content: const Text('أكد رقم واتساب أو البريد الإلكتروني قبل الدخول إلى الفائق يمن.'),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await user.sendEmailVerification();
                    if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('تمت إعادة إرسال رسالة تأكيد البريد')));
                  } on FirebaseAuthException catch (e) {
                    if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('تعذر إرسال رسالة التأكيد: ${e.message ?? e.code}')));
                  }
                },
                child: const Text('إعادة إرسال البريد'),
              ),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً')),
            ],
          ),
        );
        return;
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'invalid-email' => 'البريد الإلكتروني غير صحيح.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
        'user-disabled' => 'هذا الحساب معطل. تواصل مع الإدارة.',
        'network-request-failed' => 'تعذر الاتصال. تحقق من الإنترنت.',
        _ => 'تعذر تسجيل الدخول: ${e.message ?? e.code}',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _cleanEmail;
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل بريدك الإلكتروني أولاً ثم اضغط نسيت كلمة المرور')));
      return;
    }
    setState(() => _isResettingPassword = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال رابط إعادة تعيين كلمة المرور إلى بريدك الإلكتروني')));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'invalid-email' => 'البريد الإلكتروني غير صحيح.',
        'user-not-found' => 'لا يوجد حساب مرتبط بهذا البريد.',
        'network-request-failed' => 'تعذر الاتصال. تحقق من الإنترنت.',
        _ => 'تعذر إرسال رابط إعادة التعيين: ${e.message ?? e.code}',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isResettingPassword = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسجيل الدخول - الفائق يمن')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('مرحباً بك في تطبيق الفائق يمن', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _isResettingPassword ? null : _resetPassword,
                  child: _isResettingPassword ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('نسيت كلمة المرور؟'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(onPressed: _signIn, child: const Text('دخول', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountRegistrationScreen())),
                child: const Text('إنشاء حساب جديد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
