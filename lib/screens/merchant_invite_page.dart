import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../services/auth_service.dart';
import 'auth_gate.dart';

class MerchantInvitePage extends StatefulWidget {
  final String token;
  const MerchantInvitePage({super.key, required this.token});

  @override
  State<MerchantInvitePage> createState() => _MerchantInvitePageState();
}

class _MerchantInvitePageState extends State<MerchantInvitePage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _password.text.length < 8) {
      setState(() => _message = 'أدخل الاسم والبريد وكلمة مرور لا تقل عن 8 أحرف.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await AuthService().register(name: _name.text.trim(), email: _email.text.trim(), password: _password.text);
      final callable = FirebaseFunctions.instance.httpsCallable('redeemMerchantInvite');
      await callable.call(<String, dynamic>{'token': widget.token});
      await AuthService().auth.currentUser?.getIdToken(true);
      if (!mounted) return;
      setState(() => _message = 'تم تفعيل حساب التاجر. يمكنك الآن الدخول إلى مركز التاجر وإضافة المتجر والأصناف.');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _message = e.message ?? 'تعذر تفعيل دعوة التاجر.');
    } on FirebaseException catch (e) {
      setState(() => _message = e.message ?? 'تعذر إنشاء الحساب.');
    } catch (e) {
      setState(() => _message = 'تعذر إكمال التسجيل: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('انضم كتاجر إلى الفائق يمن')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              shrinkWrap: true,
              children: [
                const Icon(Icons.storefront_outlined, size: 72),
                const SizedBox(height: 12),
                const Text('حساب تاجر رسمي', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('أنشئ حسابك من هذا الرابط ثم ستظهر لك بوابة التاجر لإضافة متجرك ومنتجاتك.', textAlign: TextAlign.center, style: TextStyle(height: 1.5)),
                const SizedBox(height: 24),
                TextField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'اسم التاجر أو المسؤول', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(controller: _password, obscureText: _obscure, decoration: InputDecoration(labelText: 'كلمة المرور', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off)))),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _join, icon: const Icon(Icons.verified_user_outlined), label: Text(_busy ? 'جاري تفعيل الحساب...' : 'إنشاء حساب التاجر'))),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_message!, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
