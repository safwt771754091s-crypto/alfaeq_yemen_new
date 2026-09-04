import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for the secure WhatsApp OTP backend.
/// WhatsApp credentials are never stored in the Flutter app.
class WhatsAppOtpService {
  WhatsAppOtpService._();

  static final WhatsAppOtpService instance = WhatsAppOtpService._();

  static const endpoint = String.fromEnvironment(
    'WHATSAPP_OTP_ENDPOINT',
    defaultValue: 'https://me-central2-alfaeq-yemen-fed37.cloudfunctions.net/whatsappOtp',
  );

  Future<void> requestCode(String phone) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول قبل طلب رمز التحقق.');

    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'action': 'request', 'phone': phone}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('WhatsApp OTP request failed: ${response.statusCode} ${response.body}');
      String? error;
      try {
        final body = jsonDecode(response.body);
        error = body is Map ? body['error'] as String? : null;
      } catch (_) {}
      throw StateError(_messageFor(error));
    }
  }

  Future<void> verifyCode({required String phone, required String code}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('انتهت جلسة التسجيل. ابدأ من جديد.');

    final token = await user.getIdToken(true);
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'action': 'verify', 'phone': phone, 'code': code}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? error;
      try {
        final body = jsonDecode(response.body);
        error = body is Map ? body['error'] as String? : null;
      } catch (_) {}
      throw StateError(_messageFor(error));
    }
    await user.getIdToken(true);
  }

  String _messageFor(String? error) {
    return switch (error) {
      'WHATSAPP_NOT_CONFIGURED' => 'خدمة واتساب لم تُهيأ بعد على الخادم.',
      'WHATSAPP_SEND_FAILED' => 'تعذر إرسال الرسالة عبر واتساب. حاول لاحقًا.',
      'TOO_MANY_REQUESTS' => 'انتظر دقيقة قبل إعادة إرسال الرمز.',
      'TOO_MANY_ATTEMPTS' => 'تم تجاوز عدد المحاولات. اطلب رمزًا جديدًا لاحقًا.',
      'INVALID_OTP' => 'رمز التحقق غير صحيح.',
      'OTP_EXPIRED' => 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.',
      'PHONE_MISMATCH' => 'رقم الهاتف لا يطابق طلب التحقق.',
      'OTP_NOT_FOUND' => 'لا يوجد رمز فعال. اطلب رمزًا جديدًا.',
      'INVALID_PHONE' => 'رقم الهاتف غير صحيح. استخدم مفتاح الدولة.',
      'UNAUTHENTICATED' => 'انتهت جلسة الحساب. سجّل الدخول وحاول مرة أخرى.',
      _ => 'تعذر إكمال التحقق عبر واتساب. حاول مرة أخرى.',
    };
  }
}
