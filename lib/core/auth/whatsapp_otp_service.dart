import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client for the secure WhatsApp OTP backend.
///
/// The WhatsApp access token is intentionally never stored in the Flutter app.
/// Configure the HTTPS endpoint with --dart-define=WHATSAPP_OTP_ENDPOINT=...
class WhatsAppOtpService {
  WhatsAppOtpService._();

  static final WhatsAppOtpService instance = WhatsAppOtpService._();

  static const endpoint = String.fromEnvironment('WHATSAPP_OTP_ENDPOINT');

  Future<void> requestCode(String phone) async {
    if (endpoint.isEmpty) {
      throw StateError('خدمة التحقق عبر واتساب غير مهيأة بعد.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('يجب تسجيل الدخول قبل طلب رمز التحقق.');

    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'request', 'phone': phone}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('WhatsApp OTP request failed: ${response.statusCode} ${response.body}');
      throw StateError('تعذر إرسال رمز التحقق عبر واتساب. حاول مرة أخرى.');
    }
  }

  Future<void> verifyCode({required String phone, required String code}) async {
    if (endpoint.isEmpty) {
      throw StateError('خدمة التحقق عبر واتساب غير مهيأة بعد.');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('انتهت جلسة التسجيل. ابدأ من جديد.');

    final token = await user.getIdToken(true);
    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'action': 'verify', 'phone': phone, 'code': code}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('رمز التحقق غير صحيح أو انتهت صلاحيته.');
    }

    await user.getIdToken(true);
  }
}
