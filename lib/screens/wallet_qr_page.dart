import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/supabase_service.dart';

/// WeChat Pay-style receive-code: a QR that identifies the signed-in user's
/// wallet so it can be presented to a payer. Balance is shown above the code.
class WalletQrPage extends StatelessWidget {
  const WalletQrPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول أولاً.')));
    }
    final name = ((user.userMetadata ?? const <String, dynamic>{})['full_name'] ??
            (user.userMetadata ?? const <String, dynamic>{})['name'] ??
            'مستخدم الفائق')
        .toString();
    final payload = 'alfaeq://pay?uid=${user.id}&name=${Uri.encodeComponent(name)}';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('رمز الدفع', style: TextStyle(fontWeight: FontWeight.w900))),
        body: FutureBuilder<Map<String, dynamic>?>(
          future: SupabaseService.client
              .from('wallets')
              .select()
              .eq('uid', user.id)
              .maybeSingle(),
          builder: (context, snapshot) {
            final data = snapshot.data == null ? <String, dynamic>{} : Map<String, dynamic>.from(snapshot.data!);
            final balance = num.tryParse('${data['available_balance'] ?? 0}') ?? 0;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A2540),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الرصيد المتاح', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Text('$balance YER',
                          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE3E8EF))),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Text('امسح الرمز للدفع لي',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(name, style: const TextStyle(color: Colors.black54)),
                        const SizedBox(height: 18),
                        QrImageView(
                          data: payload,
                          version: QrVersions.auto,
                          size: 240,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0A2540)),
                          dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square, color: Color(0xFF0A2540)),
                        ),
                        const SizedBox(height: 18),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: payload));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم نسخ رمز الدفع.')),
                              );
                            }
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('نسخ رمز الدفع'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Card(
                  elevation: 0,
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      'يُستخدم هذا الرمز لاستلام المبالغ في محفظتك. لا تشاركه إلا مع من تثق به، ولا تكتبه في أي تطبيق آخر.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
