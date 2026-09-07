import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'ai_tools.dart';

/// Production AI gateway for Alfaeq Yemen.
///
/// The model can request only the allow-listed tools in AlfaeqAiToolRegistry.
/// Mutating or sensitive operations remain outside the client AI boundary.
class AlfaeqAiService {
  static const String modelName = 'gemini-3.5-flash';
  static const int _maxToolRounds = 6;

  final AlfaeqAiToolRegistry _tools;
  ChatSession? _chat;

  AlfaeqAiService({AlfaeqAiToolRegistry? tools})
      : _tools = tools ?? AlfaeqAiToolRegistry();

  GenerativeModel _model() {
    final ai = FirebaseAI.googleAI(
      auth: FirebaseAuth.instance,
      appCheck: FirebaseAppCheck.instance,
      useLimitedUseAppCheckTokens: true,
    );
    return ai.generativeModel(
      model: modelName,
      tools: [Tool.functionDeclarations(_tools.declarations)],
      systemInstruction: Content.system('''
أنت الوكيل الذكي الرسمي لمنصة الفائق يمن.
الفائق يمن منصة Super App عالمية تبدأ من اليمن وتتوسع إلى الخليج وأفريقيا والعالم، وهدفها تقديم تجربة متفوقة في الذكاء والخدمات والأمان والسرعة.

قواعد الوكيل:
- تحدث بالعربية افتراضياً، وادعم اللغات الأخرى عند الطلب.
- استخدم الأدوات عندما تحتاج بيانات حقيقية من المنصة، ولا تخمّن بيانات تشغيلية.
- لا تدّعي تنفيذ عملية لم تنفذ فعلياً.
- لا تطلب أو تكشف كلمات المرور أو مفاتيح API أو الرموز السرية أو بيانات الدفع الحساسة.
- الأدوات الحالية للقراءة الآمنة فقط. لا تنفذ دفعاً أو شراءً أو إلغاءً أو تغيير صلاحيات أو عملية إدارية حساسة.
- أي عملية تغيير مستقبلية يجب أن تمر عبر طبقة صلاحيات موثوقة، وتتحقق من هوية المستخدم ودوره، وتطلب تأكيداً صريحاً للعمليات عالية الخطورة.
- لا تحاول التحايل على الصلاحيات أو قواعد Firestore.
- عند فشل أداة أو عدم توفر بيانات، صرّح بذلك بوضوح.
- اجعل الإجابة النهائية مفهومة ومختصرة، واذكر عندما استخدمت بيانات حقيقية من المنصة.
'''),
    );
  }

  Future<void> _audit({required String action, required String result, Map<String, dynamic>? details}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('auditLogs').add({
        'actorUid': user.uid,
        'actorEmail': user.email,
        'role': 'ai_agent',
        'action': action,
        'result': result,
        'details': details ?? <String, dynamic>{},
        'source': 'ai_agent',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<String> sendMessage(String message) async {
    final text = message.trim();
    if (text.isEmpty) return '';
    final session = _chat ??= _model().startChat(maxTurns: 40);
    var response = await session.sendMessage(Content.text(text));

    for (var round = 0; round < _maxToolRounds; round++) {
      final calls = response.functionCalls.toList();
      if (calls.isEmpty) break;

      for (final call in calls) {
        await _audit(action: 'ai_tool_requested', result: 'requested', details: {'tool': call.name, 'args': call.args});
        final result = await _tools.execute(call.name, call.args, audit: _audit);
        await _audit(action: 'ai_tool_executed', result: result['ok'] == true ? 'success' : 'failed', details: {'tool': call.name});
        response = await session.sendMessage(Content.functionResponse(call.name, result, id: call.id));
      }
    }

    final answer = response.text?.trim();
    return answer?.isNotEmpty == true ? answer! : 'لم يصل رد نصي من خدمة الذكاء الاصطناعي.';
  }

  Stream<String> streamMessage(String message) async* {
    final text = message.trim();
    if (text.isEmpty) return;
    // Streaming remains available for normal conversational turns. Tool calls
    // use the deterministic sendMessage path so every tool result is audited.
    final session = _chat ??= _model().startChat(maxTurns: 40);
    await for (final response in session.sendMessageStream(Content.text(text))) {
      final chunk = response.text;
      if (chunk != null && chunk.isNotEmpty) yield chunk;
    }
  }

  void resetConversation() {
    _chat = null;
  }
}
