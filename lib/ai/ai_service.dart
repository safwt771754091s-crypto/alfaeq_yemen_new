import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'ai_permission_gateway.dart';
import 'ai_tools.dart';

/// Production AI gateway for Alfaeq Yemen.
///
/// Model tool calls are never executed directly. Every action passes through
/// AlfaeqAiPermissionGateway first, then through the allow-listed tool registry.
class AlfaeqAiService {
  static const String modelName = 'gemini-3.5-flash';
  static const int _maxToolRounds = 6;

  final AlfaeqAiToolRegistry _tools;
  final AlfaeqAiPermissionGateway _permissions;
  ChatSession? _chat;

  AlfaeqAiService({
    AlfaeqAiToolRegistry? tools,
    AlfaeqAiPermissionGateway? permissions,
  })  : _tools = tools ?? AlfaeqAiToolRegistry(),
        _permissions = permissions ?? AlfaeqAiPermissionGateway();

  GenerativeModel _model() {
    final ai = FirebaseAI.googleAI(
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
- كل طلب أداة يمر أولاً عبر بوابة الصلاحيات. لا تحاول تجاوزها.
- الأدوات الحالية للقراءة الآمنة فقط. لا تنفذ دفعاً أو شراءً أو إلغاءً أو تغيير صلاحيات أو عملية إدارية حساسة.
- أي عملية تغيير مستقبلية يجب أن تمر عبر طبقة صلاحيات موثوقة، وتتحقق من هوية المستخدم ودوره، وتطلب تأكيداً صريحاً للعمليات عالية الخطورة.
- لا تحاول التحايل على الصلاحيات أو قواعد Firestore.
- عند رفض الصلاحية أو فشل الأداة، صرّح بذلك بوضوح ولا تدّعي النجاح.
- اجعل الإجابة النهائية مفهومة ومختصرة، واذكر عندما استخدمت بيانات حقيقية من المنصة.
'''),
    );
  }

  Future<void> _audit({
    required String action,
    required String result,
    Map<String, dynamic>? details,
  }) async {
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

  Future<Map<String, Object?>> _executeThroughGateway(
    String tool,
    Map<String, Object?> args,
  ) async {
    final decision = await _permissions.authorize(tool);
    if (!decision.allowed) {
      await _audit(
        action: 'ai_permission_$tool',
        result: decision.requiresConfirmation ? 'confirmation_required' : 'denied',
        details: {
          'tool': tool,
          'role': decision.role,
          'level': decision.level?.name,
          'message': decision.message,
        },
      );
      return {
        'ok': false,
        'error': decision.message,
        'permission': decision.requiresConfirmation
            ? 'confirmation_required'
            : 'denied',
      };
    }

    await _audit(
      action: 'ai_permission_$tool',
      result: 'allowed',
      details: {'tool': tool, 'role': decision.role, 'level': decision.level?.name},
    );

    return _tools.execute(tool, args, audit: _audit);
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
        await _audit(
          action: 'ai_tool_requested',
          result: 'requested',
          details: {'tool': call.name, 'args': call.args},
        );
        final result = await _executeThroughGateway(call.name, call.args);
        await _audit(
          action: 'ai_tool_executed',
          result: result['ok'] == true ? 'success' : 'blocked',
          details: {'tool': call.name, 'permission': result['permission']},
        );
        response = await session.sendMessage(
          Content.functionResponse(call.name, result, id: call.id),
        );
      }
    }

    final answer = response.text?.trim();
    return answer?.isNotEmpty == true
        ? answer!
        : 'لم يصل رد نصي من خدمة الذكاء الاصطناعي.';
  }

  Stream<String> streamMessage(String message) async* {
    final text = message.trim();
    if (text.isEmpty) return;
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
