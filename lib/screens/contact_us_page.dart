import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _navy = Color(0xFF0E2A47);
const _blue = Color(0xFF1565C0);
const _surface = Color(0xFFF4F7FB);

/// Official contact channels for the Alfaeq Yemen platform. Kept in one place
/// so the number and address can be reused by the about dialog and the footer.
class AlfaeqContact {
  const AlfaeqContact._();
  static const whatsappNumber = '967783482882';
  static const phoneNumber = '+967783482882';
  static const displayPhone = '00967783482882';
  static const email = 'albyysks@gmail.com';
}

/// "تواصل معنا" — WhatsApp, phone call and email, with copy shortcuts.
class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذّر فتح التطبيق المناسب على هذا الجهاز.')));
    }
  }

  Future<void> _copy(BuildContext context, String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم نسخ $label ✅')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _surface,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Text('تواصل معنا', style: TextStyle(fontWeight: FontWeight.w900)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(20)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الفائق يمن', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  SizedBox(height: 6),
                  Text('فريق الدعم جاهز لمساعدتك عبر واتساب أو البريد الإلكتروني.', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _channel(
              context,
              icon: Icons.chat_bubble_outline,
              color: const Color(0xFF25D366),
              title: 'واتساب',
              subtitle: AlfaeqContact.displayPhone,
              onTap: () => _open(context, Uri.parse('https://wa.me/${AlfaeqContact.whatsappNumber}')),
              onCopy: () => _copy(context, AlfaeqContact.displayPhone, 'رقم واتساب'),
            ),
            _channel(
              context,
              icon: Icons.call_outlined,
              color: _blue,
              title: 'اتصال هاتفي',
              subtitle: AlfaeqContact.displayPhone,
              onTap: () => _open(context, Uri.parse('tel:${AlfaeqContact.phoneNumber}')),
              onCopy: () => _copy(context, AlfaeqContact.phoneNumber, 'رقم الهاتف'),
            ),
            _channel(
              context,
              icon: Icons.email_outlined,
              color: const Color(0xFFD93025),
              title: 'البريد الإلكتروني',
              subtitle: AlfaeqContact.email,
              onTap: () => _open(context, Uri.parse('mailto:${AlfaeqContact.email}?subject=${Uri.encodeComponent('استفسار عبر تطبيق الفائق يمن')}')),
              onCopy: () => _copy(context, AlfaeqContact.email, 'البريد الإلكتروني'),
            ),
            const SizedBox(height: 10),
            const Text(
              'أوقات الرد عادةً خلال ساعات العمل. للأمور العاجلة استخدم واتساب.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channel(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required VoidCallback onCopy,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFE3E8EF))),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: _navy)),
        subtitle: Text(subtitle, textDirection: TextDirection.ltr),
        trailing: IconButton(
          tooltip: 'نسخ',
          icon: const Icon(Icons.copy_all_outlined, color: Colors.black45),
          onPressed: onCopy,
        ),
      ),
    );
  }
}
