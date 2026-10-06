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
  bool _register = false, _loading = false, _obscure = true;

  @override
  void initState() {
    super.initState();
    _register = _routeRequestsRegister();
  }

  /// Supports deep links like `.../#/signup` or `.../?mode=register` from any
  /// host, so a customer can land directly on the create-account form.
  bool _routeRequestsRegister() {
    try {
      final route = Uri.base.fragment.toLowerCase();
      final query = Uri.base.queryParameters['mode']?.toLowerCase();
      return route.contains('signup') || route.contains('register') ||
          route.contains('create') || query == 'register' || query == 'signup';
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() { _name.dispose(); _email.dispose(); _password.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      if (_register) {
        final response = await _auth.register(name: _name.text, email: _email.text, password: _password.text);
        if (!mounted) return;
        if (response.session == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إنشاء الحساب. افتح رسالة التأكيد في بريدك الإلكتروني ثم سجّل الدخول.'),
              duration: Duration(seconds: 6),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إنشاء الحساب وتسجيل الدخول بنجاح.')),
          );
        }
      } else {
        await _auth.signIn(email: _email.text, password: _password.text);
        await _auth.bootstrapPrimaryAdminIfEligible();
      }
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_authMessage(e.toString()))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _google() async {
    setState(() => _loading = true);
    try {
      await _auth.signInWithGoogle();
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('إذا كان البريد مسجّلاً فسيصلك رابط لتعيين كلمة مرور جديدة. تفقّد صندوق الوارد والبريد المزعج.'),
        duration: Duration(seconds: 7),
      ));
    } on Exception catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_authMessage(e.toString()))));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  String _authMessage(String error) {
    // Supabase Auth error codes.
    if (error.contains('invalid_credentials') || error.contains('Invalid login credentials')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    }
    if (error.contains('email_not_confirmed')) {
      return 'الحساب موجود، لكن البريد الإلكتروني غير مؤكد. افتح رسالة التأكيد في بريدك ثم حاول تسجيل الدخول.';
    }
    if (error.contains('user_already_exists') || error.contains('already been registered')) {
      return 'هذا البريد مسجل بالفعل. استخدم تسجيل الدخول أو استعادة كلمة المرور.';
    }
    if (error.contains('email_address_invalid') || error.contains('invalid format')) {
      return 'أدخل بريدًا إلكترونيًا صحيحًا (مثال: name@gmail.com).';
    }
    if (error.contains('weak_password')) return 'كلمة المرور ضعيفة. استخدم 6 أحرف أو أكثر.';
    if (error.contains('over_email_send_rate_limit') || error.contains('rate limit')) {
      return 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.';
    }
    if (error.contains('Error sending recovery email') || error.contains('Error sending confirmation email') || error.contains('Error sending email') || error.contains('Error sending magic link')) {
      return 'تعذّر إرسال البريد الآن. لم يتم ضبط مزوّد البريد (SMTP) بعد، تواصل مع الدعم لإتمام الإعداد.';
    }
    if (error.contains('signup_disabled')) return 'إنشاء الحسابات معطّل حالياً. تواصل مع الدعم.';
    if (error.contains('provider is not enabled') || error.contains('validation_failed')) {
      return 'تسجيل الدخول بحساب Google غير مفعّل حالياً. استخدم البريد وكلمة المرور.';
    }
    if (error.contains('popup-closed-by-user')) return 'تم إغلاق نافذة Google قبل إكمال الدخول.';
    if (error.contains('cancelled') || error.contains('canceled')) return 'تم إلغاء تسجيل الدخول بحساب Google.';
    if (error.contains('account-exists-with-different-credential')) return 'يوجد حساب بهذا البريد بطريقة دخول أخرى. استخدم البريد وكلمة المرور أولاً.';
    if (error.contains('email not confirmed') || error.contains('user not confirmed')) {
      return 'الحساب موجود، لكن البريد الإلكتروني غير مؤكد. افتح رسالة التأكيد في بريدك ثم حاول تسجيل الدخول.';
    }
    if (error.contains('user already registered') || error.contains('already registered')) {
      return 'هذا البريد مسجل بالفعل. استخدم تسجيل الدخول أو استعادة كلمة المرور.';
    }
    if (error.contains('permission-denied')) return 'تم تسجيل الدخول، لكن الحساب لا يملك الصلاحيات المطلوبة.';
    if (error.contains('invalid-credential') || error.contains('wrong-password')) return 'البريد الإلكتروني أو كلمة المرور غير صحيحة.';
    if (error.contains('user-not-found')) return 'لا يوجد حساب بهذا البريد الإلكتروني.';
    if (error.contains('email-already-in-use')) return 'البريد الإلكتروني مستخدم بالفعل.';
    if (error.contains('weak-password')) return 'كلمة المرور ضعيفة. استخدم 6 أحرف أو أكثر.';
    if (error.contains('invalid-email')) return 'أدخل بريدًا إلكترونيًا صحيحًا.';
    if (error.contains('network-request-failed') || error.contains('Failed to fetch') || error.contains('SocketException') || error.contains('ClientException') || error.contains('XMLHttpRequest') || error.contains('Unable to connect') || error.contains('Connection failed') || error.contains('Connection closed') || error.contains('connection reset') || error.contains('HandshakeException') || error.contains('TimeoutException') || error.contains('timed out')) {
      return 'تعذر الاتصال بخادم الفائق يمن. تحقق من اتصال الإنترنت ثم أعد المحاولة.';
    }
    final normalized = error.replaceAll(RegExp(r'\s+'), ' ').trim();
    return 'تعذر إتمام العملية: $normalized';
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
            ],
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)), validator: (v) => v == null || !v.contains('@') ? 'أدخل بريدًا صحيحًا' : null), const SizedBox(height: 12),
            TextFormField(controller: _password, obscureText: _obscure, onFieldSubmitted: (_) => _submit(), decoration: InputDecoration(labelText: 'كلمة المرور', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))), validator: (v) => v == null || v.length < 6 ? 'كلمة المرور 6 أحرف على الأقل' : null),
            if (!_register) ...[const SizedBox(height: 8), SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _loading ? null : _forgotPassword, icon: const Icon(Icons.lock_reset_rounded), label: const Text('نسيت كلمة المرور؟', style: TextStyle(fontWeight: FontWeight.w800))))],
            const SizedBox(height: 14), SizedBox(width: double.infinity, child: FilledButton(onPressed: _loading ? null : _submit, child: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_register ? 'إنشاء الحساب' : 'تسجيل الدخول'))),
            if (AuthService.googleAuthEnabled) ...[
              const SizedBox(height: 10),
              Row(children: const [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('أو')), Expanded(child: Divider())]),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _loading ? null : _google, icon: const Icon(Icons.g_mobiledata, size: 30), label: const Text('الدخول عبر حساب Google', style: TextStyle(fontWeight: FontWeight.w800)))),
            ],
            TextButton(onPressed: _loading ? null : () => setState(() => _register = !_register), child: Text(_register ? 'لديك حساب؟ تسجيل الدخول' : 'ليس لديك حساب؟ إنشاء حساب')),
            if (!_register) const Padding(padding: EdgeInsets.only(top: 4), child: Text('روابط التجار تُفتح تلقائياً عند الدخول من رابط دعوة التاجر.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12))),
          ])))),
        ]),
      )))),
    ),
  );
}
