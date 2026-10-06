import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/currency_service.dart';
import '../services/profile_service.dart';
import '../widgets/currency_selector.dart';
import 'cart_page.dart';
import 'conversations_page.dart';
import 'location_picker_page.dart';
import 'moments_page.dart';
import 'my_orders_page.dart';
import 'notifications_page.dart';
import 'support_chat_page.dart';
import 'wallet_vouchers_page.dart';
import 'world_home_page.dart';

const _navy = Color(0xFF0E2A47);
const _blue = Color(0xFF1565C0);
const _surface = Color(0xFFF4F7FB);

/// WeChat-style "أنا" account center: avatar, personal info, security and
/// full account controls in one place.
class AccountCenterPage extends StatefulWidget {
  const AccountCenterPage({super.key, this.onOpenTab});

  /// Lets the shell switch tabs (e.g. cart / orders) when embedded.
  final ValueChanged<int>? onOpenTab;

  @override
  State<AccountCenterPage> createState() => _AccountCenterPageState();
}

class _AccountCenterPageState extends State<AccountCenterPage> {
  final _profile = ProfileService();
  final _auth = AuthService();
  Map<String, dynamic> _data = const {};
  Map<String, dynamic> _stats = const {'orders': 0, 'balance': 0};
  String _version = '';
  bool _loading = true;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {}
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final data = await _profile.load();
      final stats = await _profile.stats();
      if (!mounted) return;
      setState(() {
        _data = data;
        _stats = stats;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _name {
    final n = (_data['name'] ?? '').toString().trim();
    if (n.isNotEmpty) return n;
    final email = (_data['email'] ?? '').toString();
    return email.contains('@') ? email.split('@').first : 'مستخدم الفائق';
  }

  String get _email => (_data['email'] ?? '').toString();
  String? get _avatarUrl {
    final url = _data['avatar_url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  void _open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final url = await _profile.uploadAvatar(file.bytes!, file.extension ?? 'jpg');
      await _profile.updateProfile(avatarUrl: url);
      await _reload();
      _toast('تم تحديث الصورة الشخصية.');
    } catch (e) {
      _toast('تعذر تحديث الصورة: $e');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editProfile() async {
    final nameCtrl = TextEditingController(text: _name);
    final phoneCtrl = TextEditingController(text: (_data['phone'] ?? '').toString());
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل الملف الشخصي'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'رقم الجوال', prefixIcon: Icon(Icons.phone_outlined)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await _profile.updateProfile(name: nameCtrl.text, phone: phoneCtrl.text);
      await _reload();
      _toast('تم حفظ البيانات.');
    } catch (e) {
      _toast('تعذر الحفظ: $e');
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغيير كلمة المرور'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الحالية')),
            const SizedBox(height: 12),
            TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
            const SizedBox(height: 12),
            TextField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تغيير')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (next.text.length < 6) {
      _toast('كلمة المرور الجديدة 6 أحرف على الأقل.');
      return;
    }
    if (next.text != confirm.text) {
      _toast('كلمتا المرور غير متطابقتين.');
      return;
    }
    try {
      await _profile.changePassword(
        currentPassword: current.text,
        newPassword: next.text,
      );
      _toast('تم تغيير كلمة المرور.');
    } catch (e) {
      final msg = e.toString();
      _toast(msg.contains('invalid_credentials')
          ? 'كلمة المرور الحالية غير صحيحة.'
          : 'تعذر تغيير كلمة المرور: $msg');
    }
  }

  Future<void> _changeEmail() async {
    final emailCtrl = TextEditingController(text: _email);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغيير البريد الإلكتروني'),
          content: TextField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'البريد الجديد', prefixIcon: Icon(Icons.email_outlined)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تغيير')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    if (!emailCtrl.text.contains('@')) {
      _toast('أدخل بريداً صحيحاً.');
      return;
    }
    try {
      await _profile.changeEmail(emailCtrl.text);
      _toast('تم إرسال رسالة تأكيد إلى البريد الجديد.');
    } catch (e) {
      _toast('تعذر تغيير البريد: $e');
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تسجيل الخروج'),
          content: const Text('هل تريد تسجيل الخروج من حسابك؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('خروج')),
          ],
        ),
      ),
    );
    if (ok == true) await _auth.signOut();
  }

  Future<void> _about() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('عن الفائق يمن'),
          content: Text(
            'منصة الفائق يمن التجارية الشاملة\n'
            'الإصدار: ${_version.isEmpty ? '—' : _version}\n'
            'تسوّق، احجز، وادفع من مكان واحد.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        body: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _header(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              _statsRow(),
              _group('الطلبات والمشتريات', [
                _tile(Icons.receipt_long_outlined, 'طلباتي وتتبع التوصيل', onTap: () => _open(const MyOrdersPage())),
                _tile(Icons.shopping_cart_outlined, 'السلة', onTap: () => _open(const CartPage())),
                _tile(Icons.location_on_outlined, 'عناويني', onTap: () => _open(const LocationPickerPage())),
              ]),
              _group('المحفظة والمدفوعات', [
                _tile(Icons.account_balance_wallet_outlined, 'محفظتي',
                    subtitle: '${CurrencyService.symbolFor(CurrencyService.instance.displayCurrency)} ${_stats['balance']}',
                    onTap: () => _open(const WalletCenterPage())),
                _tile(Icons.confirmation_number_outlined, 'رموز شحن المحفظة', onTap: () => _open(const WalletVouchersPage())),
                _tile(Icons.currency_exchange, 'العملة المعروضة',
                    subtitle: CurrencyService.labelFor(CurrencyService.instance.displayCurrency),
                    trailing: const CurrencySelector()),
              ]),
              _group('الأمان والحساب', [
                _tile(Icons.person_outline, 'تعديل الملف الشخصي', onTap: _editProfile),
                _tile(Icons.lock_outline, 'تغيير كلمة المرور', onTap: _changePassword),
                _tile(Icons.alternate_email, 'تغيير البريد الإلكتروني', subtitle: _email, onTap: _changeEmail),
              ]),
              _group('التواصل والخدمات', [
                _tile(Icons.chat_bubble_outline, 'المحادثات', onTap: () => _open(const ConversationsPage())),
                _tile(Icons.auto_awesome_outlined, 'اللحظات', onTap: () => _open(const MomentsPage())),
                _tile(Icons.support_agent_outlined, 'دعم الفائق', onTap: () => _open(const SupportChatPage())),
                _tile(Icons.grid_view_outlined, 'كل الخدمات', onTap: () => _open(const ServicesHubPage())),
                _tile(Icons.notifications_none, 'الإشعارات', onTap: () => _open(const NotificationsPage())),
              ]),
              _group('عام', [
                _tile(Icons.info_outline, 'عن التطبيق', subtitle: _version.isEmpty ? null : 'الإصدار $_version', onTap: _about),
                _tile(Icons.share_outlined, 'شارك التطبيق',
                    onTap: () => launchUrl(Uri.parse('https://safwt771754091s-crypto.github.io/alfaeq_yemen_new/'))),
              ]),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: _confirmLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('تسجيل الخروج', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(backgroundColor: _navy, minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [_navy, _blue]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(children: [
        Stack(children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white24,
            backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
            child: _avatarUrl == null
                ? Text(_name.characters.first, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900))
                : null,
          ),
          Positioned(
            bottom: 0, right: 0,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _uploadingAvatar ? null : _pickAvatar,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: _uploadingAvatar
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.photo_camera, size: 16, color: _blue),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(_email, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                child: Text('${(_data['role'] ?? 'customer')}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickAvatar,
                icon: const Icon(Icons.edit, size: 16, color: Colors.white),
                label: const Text('تغيير الصورة', style: TextStyle(color: Colors.white, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _statsRow() {
    Widget cell(String value, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(children: [
                Text(value, style: const TextStyle(color: _navy, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              ]),
            ),
          ),
        );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        cell('${_stats['orders']}', 'طلباتي', () => _open(const MyOrdersPage())),
        const SizedBox(height: 32, child: VerticalDivider()),
        cell('${_stats['balance']}', 'رصيد المحفظة', () => _open(const WalletCenterPage())),
        const SizedBox(height: 32, child: VerticalDivider()),
        cell('${_data['role'] ?? 'عميل'}', 'نوع الحساب', () {}),
      ]),
    );
  }

  Widget _group(String title, List<Widget> children) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        child: Text(title, style: const TextStyle(color: _navy, fontSize: 15, fontWeight: FontWeight.w900)),
      ),
      Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(children: children),
      ),
    ]);
  }

  Widget _tile(IconData icon, String title, {String? subtitle, Widget? trailing, VoidCallback? onTap}) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFFF1F6FF), child: Icon(icon, color: _blue, size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: subtitle == null ? null : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_left, color: Colors.black26)),
      onTap: onTap,
    );
  }
}
