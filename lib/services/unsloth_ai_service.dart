import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnslothAiService {
  final SupabaseClient _client;
  UnslothAiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> chatCompletion({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double temperature = .2,
    int maxTokens = 1024,
    String toolChoice = 'auto',
  }) async {
    // `functions.invoke` throws FunctionsHttpException for any non-2xx status
    // instead of returning it, so a returned-status check is unreachable unless
    // the exception is caught first. Without this, provider errors (429/503/401)
    // leaked raw SDK text into the UI instead of the Arabic guidance below.
    try {
      final r = await _client.functions.invoke('ai-gateway', body: {
        'messages': messages,
        'tools': tools,
        'tool_choice': toolChoice,
        if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': false,
      });
      if (r.data is Map) return Map<String, dynamic>.from(r.data);
      if (r.data is String) {
        final d = jsonDecode(r.data);
        if (d is Map) return Map<String, dynamic>.from(d);
      }
      throw StateError('استجابة غير صالحة من بوابة الذكاء.');
    } on FunctionException catch (e) {
      // Covers FunctionsHttpException (non-2xx) and FunctionsFetchException
      // (network/transport failure, status 0).
      throw StateError(describeError(e.details));
    }
  }

  /// Maps a gateway/provider error payload to user-facing Arabic guidance.
  /// Public and static so it can be unit tested without a network round-trip.
  static String describeError(dynamic d) {
    final raw = d is Map && d['error'] is String
        ? d['error'] as String
        : d is Map && d['error'] is Map && d['error']['message'] is String
            ? d['error']['message'] as String
            : '';
    switch (raw) {
      case 'ai_provider_not_configured':
      case 'ai_gateway_not_configured':
        return 'بوابة الذكاء غير مهيأة على الخادم. يجب ضبط أسرار المشغل (AI_BASE_URL وAI_MODEL وAI_API_KEY) في إعدادات Supabase ثم إعادة نشر دالة ai-gateway.';
      case 'server_configuration_missing':
        return 'إعدادات خادم Supabase ناقصة لدالة الذكاء.';
      case 'invalid_session':
      case 'missing_authorization':
        return 'انتهت الجلسة أو غير مصرح. سجّل الدخول مرة أخرى ثم أعد المحاولة.';
      case 'ai_provider_unreachable':
        return 'تعذر الوصول إلى مزود الذكاء من الخادم. تحقق من AI_BASE_URL واتصال الشبكة.';
      case 'ai_provider_rate_limited':
        return 'مزود الذكاء مشغول الآن (تجاوز حد الطلبات). انتظر قليلاً ثم أعد المحاولة، أو فعّل خطة أعلى لدى مزود الذكاء.';
      case 'ai_provider_unavailable':
        return 'مزود الذكاء غير متاح مؤقتاً بسبب الضغط. أعد المحاولة بعد قليل.';
      case 'ai_provider_auth_failed':
        return 'مفتاح مزود الذكاء مرفوض من الخادم (خطأ مصادقة 401). تحقق من صلاحية AI_API_KEY: مفاتيح Google الجديدة ببادئة AQ. قد تُرفض حتى بعد التفعيل؛ أنشئ مفتاحاً جديداً من Google AI Studio أو استخدم مزوداً متوافقاً آخر ثم حدّث الأسرار وأعد نشر ai-gateway.';
      default:
        return raw.isNotEmpty ? raw : 'فشل طلب بوابة الذكاء.';
    }
  }

  String extractContent(Map<String, dynamic> d) {
    final c = d['choices'];
    if (c is List && c.isNotEmpty && c.first is Map) {
      final m = c.first['message'];
      if (m is Map && m['content'] is String) return m['content'].trim();
    }
    return '';
  }

  List<Map<String, dynamic>> extractToolCalls(Map<String, dynamic> d) {
    final c = d['choices'];
    if (c is! List || c.isEmpty || c.first is! Map) return const [];
    final m = c.first['message'];
    final x = m is Map ? m['tool_calls'] : null;
    if (x is! List) return const [];
    return x.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic> extractAssistantMessage(Map<String, dynamic> d) {
    final c = d['choices'];
    if (c is List && c.isNotEmpty && c.first is Map && c.first['message'] is Map) {
      return Map<String, dynamic>.from(c.first['message']);
    }
    return {'role': 'assistant', 'content': ''};
  }
}
