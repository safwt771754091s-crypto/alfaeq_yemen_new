import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
class UnslothAiService{
 final SupabaseClient _client;
 UnslothAiService({SupabaseClient? client}):_client=client??Supabase.instance.client;
 Future<Map<String,dynamic>> chatCompletion({required List<Map<String,dynamic>> messages,required List<Map<String,dynamic>> tools,String? model,double temperature=.2,int maxTokens=1024,String toolChoice='auto'})async{
  final r=await _client.functions.invoke('ai-gateway',body:{'messages':messages,'tools':tools,'tool_choice':toolChoice,if(model!=null&&model.trim().isNotEmpty)'model':model.trim(),'temperature':temperature,'max_tokens':maxTokens,'stream':false});
  if(r.status<200||r.status>=300)throw StateError(_error(r.data));
  if(r.data is Map)return Map<String,dynamic>.from(r.data);
  if(r.data is String){final d=jsonDecode(r.data);if(d is Map)return Map<String,dynamic>.from(d);}
  throw StateError('استجابة غير صالحة من بوابة الذكاء.');
 }
   String _error(dynamic d){
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
      default:
        return raw.isNotEmpty ? raw : 'فشل طلب بوابة الذكاء.';
    }
  }
 String extractContent(Map<String,dynamic> d){final c=d['choices'];if(c is List&&c.isNotEmpty&&c.first is Map){final m=c.first['message'];if(m is Map&&m['content'] is String)return m['content'].trim();}return '';}
 List<Map<String,dynamic>> extractToolCalls(Map<String,dynamic> d){final c=d['choices'];if(c is! List||c.isEmpty||c.first is! Map)return const [];final m=c.first['message'];final x=m is Map?m['tool_calls']:null;if(x is! List)return const [];return x.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();}
 Map<String,dynamic> extractAssistantMessage(Map<String,dynamic> d){final c=d['choices'];if(c is List&&c.isNotEmpty&&c.first is Map&&c.first['message'] is Map)return Map<String,dynamic>.from(c.first['message']);return {'role':'assistant','content':''};}
}