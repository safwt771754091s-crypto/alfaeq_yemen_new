import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/auth_service.dart';
import 'location_picker_page.dart';

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
  bool _register = false, _loading = false, _obscure = true;
  GeoPoint? _pendingLocation;

  @override
  void dispose() { _name.dispose(); _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _pickLocation() async {
    final point = await Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => const LocationPickerPage()));
    if (point != null && mounted) setState(() => _pendingLocation = GeoPoint(point.latitude, point.longitude));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_register && _pendingLocation == null) {
      await _pickLocation();
      if (_pendingLocation == null) return;
    }
    setState(() => _loading = true);
    try {
      if (_register) {
        await _auth.register(name: _name.text, email: _email.text, password: _password.text, location: _pendingLocation!, locationSource: 'map_or_device');
      } else {
        await _auth.signIn(email: _email.text, password: _password.text);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_authMessage(e.toString()))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل بريدك الإلكتروني أولاً.'))); return; }
    setState(() => _loading = true);
    try {
      await _auth.sendPasswordReset(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال رابط استعادة كلمة المرور إلى بريدك الإلكتروني.')));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_authMessage(e.toString()))));
    } finally { if (mounted) setState(() => _loading = false); }
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
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(20), margin: const EdgeInsets.only(bottom: 18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFF1565C0), Color(0xFF42A5F5)])), child: const Column(children: [Icon(Icons.local_offer_rounded, color: Colors.white, size: 34), SizedBox(height: 8), Text('عروض الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)), SizedBox(height: 4), Text('تسوّق، احجز، واستفد من خدماتنا من مكان واحد', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14))])),
          Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(24), child: Form(key: _formKey, child: Column(children: [
            const CircleAvatar(radius: 36, child: Icon(Icons.storefront, size: 38)), const SizedBox(height: 16),
            const Text('الفائق يمن', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), const SizedBox(height: 6),
            Text(_register ? 'إنشاء حساب جديد' : 'تسجيل الدخول إلى حسابك'), const SizedBox(height: 24),
            if (_register) ...[
              TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person_outline)), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل الاسم' : null),
              const SizedBox(height: 12),
              Card(elevation: 0, color: _pendingLocation == null ? null : Theme.of(context).colorScheme.primaryContainer, child: ListTile(leading: const Icon(Icons.location_on_outlined), title: Text(_pendingLocation == null ? 'تحديد الموقع مطلوب' : 'تم تحديد موقع الحساب'), subtitle: Text(_pendingLocation == null ? 'حدد موقعك من الخريطة أو استخدم موقع الهاتف.' : '${_pendingLocation!.latitude.toStringAsFixed(5)}, ${_pendingLocation!.longitude.toStringAsFixed(5)}'), trailing: IconButton(onPressed: _loading ? null : _pickLocation, icon: const Icon(Icons.map_outlined)), onTap: _loading ? null : _pickLocation)),
              const SizedBox(height: 12),
            ],
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)), validator: (v) => v == null || !v.contains('@') ? 'أدخل بريدًا صحيحًا' : null), const SizedBox(height: 12),
            TextFormField(controller: _password, obscureText: _obscure, onFieldSubmitted: (_) => _submit(), decoration: InputDecoration(labelText: 'كلمة المرور', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))), validator: (v) => v == null || v.length < 6 ? 'كلمة المرور 6 أحرف على الأقل' : null),
            if (!_register) ...[const SizedBox(height: 8), SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _loading ? null : _forgotPassword, icon: const Icon(Icons.lock_reset_rounded), label: const Text('نسيت كلمة المرور؟', style: TextStyle(fontWeight: FontWeight.w800))))],
            const SizedBox(height: 12), SizedBox(width: double.infinity, child: FilledButton(onPressed: _loading ? null : _submit, child: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'إنشاء الحساب' : 'تسجيل الدخول'))),
            TextButton(onPressed: _loading ? null : () => setState(() { _register = !_register; _pendingLocation = null; }), child: Text(_register ? 'لديك حساب؟ تسجيل الدخول' : 'ليس لديك حساب؟ إنشاء حساب')),
          ]))),
        ]),
      )))),
    ),
  );
}
