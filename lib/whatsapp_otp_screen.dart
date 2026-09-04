import 'package:flutter/material.dart';

import 'core/auth/whatsapp_otp_service.dart';

class WhatsAppOtpScreen extends StatefulWidget {
  const WhatsAppOtpScreen({super.key, required this.phone});

  final String phone;

  @override
  State<WhatsAppOtpScreen> createState() => _WhatsAppOtpScreenState();
}

class _WhatsAppOtpScreenState extends State<WhatsAppOtpScreen> {
  final _code = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  bool _sent = false;

  Future<void> _sendCode() async {
    setState(() => _sending = true);
    try {
      await WhatsAppOtpService.instance.requestCode(widget.phone);
      if (!mounted) return;
      setState(() => _sent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال رمز التحقق إلى واتساب')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رمز التحقق المكوّن من 6 أرقام')),
      );
      return;
    }
    setState(() => _verifying = true);
    try {
      await WhatsAppOtpService.instance.verifyCode(phone: widget.phone, code: code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تأكيد رقم واتساب بنجاح')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تأكيد رقم واتساب')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.chat, size: 64),
            const SizedBox(height: 16),
            const Text(
              'تأكيد الحساب عبر واتساب',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'سنرسل رمزًا من 6 أرقام إلى الرقم:\n${widget.phone}',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _sending ? null : _sendCode,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_sent ? 'إعادة إرسال الرمز' : 'إرسال الرمز عبر واتساب'),
              ),
            ),
            if (_sent) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'رمز التحقق',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _verifying ? null : _verify,
                  child: _verifying
                      ? const CircularProgressIndicator()
                      : const Text('تأكيد الرقم'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'ملاحظة: رمز واتساب يُرسل من خادم آمن، ولا يتم وضع مفتاح WhatsApp داخل التطبيق.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
