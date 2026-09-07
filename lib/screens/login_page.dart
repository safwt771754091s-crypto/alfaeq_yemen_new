import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthService();
  bool _register = false;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_register) {
        await _auth.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
        );
      } else {
        await _auth.signIn(email: _email.text, password: _password.text);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_authMessage(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _authMessage(String error) {
    if (error.contains('invalid-credential') || error.contains('wrong-password')) return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    if (error.contains('user-not-found')) return 'لا يوجد حساب بهذا البريد الإلكتروني.';
    if (error.contains('email-already-in-use')) return 'البريد الإلكتروني مستخدم بالفعل.';
    if (error.contains('weak-password')) return 'كلمة المرور ضعيفة. استخدم 6 أحرف أو أكثر.';
    if (error.contains('invalid-email')) return 'أدخل بريدًا إلكترونيًا صحيحًا.';
    if (error.contains('network-request-failed')) return 'تحقق من اتصال الإنترنت.';
    return 'تعذر إتمام العملية. حاول مرة أخرى.';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const CircleAvatar(radius: 36, child: Icon(Icons.storefront, size: 38)),
                          const SizedBox(height: 16),
                          const Text('الفائق يمن', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 6),
                          Text(_register ? 'إنشاء حساب جديد' : 'تسجيل الدخول إلى حسابك'),
                          const SizedBox(height: 24),
                          if (_register) ...[
                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person_outline)),
                              validator: (v) => v == null || v.trim().isEmpty ? 'أدخل الاسم' : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
                            validator: (v) => v == null || !v.contains('@') ? 'أدخل بريدًا صحيحًا' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off)),
                            ),
                            validator: (v) => v == null || v.length < 6 ? 'كلمة المرور 6 أحرف على الأقل' : null,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _loading ? null : _submit,
                              child: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'إنشاء الحساب' : 'تسجيل الدخول'),
                            ),
                          ),
                          TextButton(
                            onPressed: _loading ? null : () => setState(() => _register = !_register),
                            child: Text(_register ? 'لديك حساب؟ تسجيل الدخول' : 'ليس لديك حساب؟ إنشاء حساب'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
