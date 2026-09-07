import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'ai_permission_gateway.dart';
import 'ai_tools.dart';

/// Production AI gateway for Alfaeq Yemen.
///
/// Model tool calls never execute directly. Every action passes through the
/// permission gateway. Reversible actions can pause for an explicit UI
/// confirmation before the tool is executed.
class AlfaeqAiService {
  static const String modelName = 'gemini-3.5-flash';
  static const int _maxToolRounds = 6;

  final AlfaeqAiToolRegistry _tools;
  final AlfaeqAiPermissionGateway _permissions;
  ChatSession? _chat;
  _PendingAiAction? _pendingAction;

  AlfaeqAiService({
    AlfaeqAiToolRegistry? tools,
    AlfaeqAiPermissionGateway? permissions,
  })  : _tools = tools ?? AlfaeqAiToolRegistry(),
        _permissions = permissions ?? AlfaeqAiPermissionGateway();

  bool get hasPendingConfirmation => _pendingAction != null;
  String? get pendingActionName => _pendingAction?.name;

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
- عمليات القراءة الآمنة يمكن تنفيذها تلقائياً.

بروتوكول التجارة والشراء:
1. عند طلب المستخدم شراء منتج أو مراجعة مشترياته، استخدم get_my_cart للحصول على السلة الحقيقية للمستخدم.
2. لا تعتمد على أسعار أو أسماء يكتبها المستخدم أو النموذج إذا كانت بيانات المنتج موجودة في Firestore؛ المصدر المرجعي هو المنتج النشط في المنصة.
3. قبل إنشاء الطلب، اعرض للمستخدم ملخصاً واضحاً يتضمن المنتجات والكميات والأسعار والإجمالي وطريقة الدفع والعنوان، واطلب تأكيداً صريحاً.
4. إنشاء الطلب يتم فقط عبر create_order_draft وبعد التأكيد الصريح الذي توفره واجهة المستخدم. لا تعتبر مجرد قول النموذج أو رسالة سابقة تأكيداً تنفيذياً.
5. create_order_draft ينشئ طلباً معلّقاً فقط؛ لا تخصم أموالاً ولا تنفذ تحويلاً ولا تعتبر طريقة الدفع المختارة عملية دفع ناجحة.
6. إذا تغير السعر أو أصبح المنتج غير متاح أثناء الإنشاء، لا تدّع النجاح؛ أعد عرض المشكلة واطلب من المستخدم مراجعة السلة.
7. بعد نجاح إنشاء الطلب، أعط المستخدم رقم الطلب وحالته والإجمالي، ثم استخدم get_my_order لمتابعة حالته عند الطلب.
8. لا تنشئ طلباً من بيانات مشتريات خارج السلة عندما يكون المستخدم في مسار الشراء العادي، إلا إذا طلب ذلك صراحة وكان قد راجع البيانات المطلوبة.

الأمان والصلاحيات:
- لا تنفذ دفعاً أو تغيير صلاحيات أو عملية إدارية حساسة من داخل العميل.
- أي عملية حساسة مستقبلية يجب أن تمر عبر خدمة موثوقة على الخادم، وتتحقق من الهوية والدور وApp Check وتسجيل التدقيق.
- لا تحاول التحايل على الصلاحيات أو قواعد Firestore.
- عند رفض الصلاحية أو فشل الأداة، صرّح بذلك بوضوح ولا تدّعي النجاح.
- لا تعرض بيانات مستخدم آخر أو طلباً لا يخص الحساب الحالي.
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
    Map<String, Object?> args, {
    bool userConfirmed = false,
  }) async {
    final decision = await _permissions.authorize(
      tool,
      userConfirmed: userConfirmed,
    );
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
      details: {
        'tool': tool,
        'role': decision.role,
        'level': decision.level?.name,
        'confirmed': userConfirmed,
      },
    );

    return _tools.execute(
      tool,
      args,
      audit: _audit,
      userConfirmed: userConfirmed,
    );
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
        if (result['permission'] == 'confirmation_required') {
          _pendingAction = _PendingAiAction(
            name: call.name,
            args: Map<String, Object?>.from(call.args),
            id: call.id,
          );
          await _audit(
            action: 'ai_action_waiting_confirmation',
            result: 'pending',
            details: {'tool': call.name},
          );
          return 'هذه العملية تحتاج تأكيدك الصريح قبل التنفيذ. راجع التفاصيل ثم اضغط «تأكيد التنفيذ». ';
        }

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

  /// Executes the action previously paused by the gateway after the user
  /// presses the confirmation control in the UI.
  Future<String> confirmPendingAction() async {
    final pending = _pendingAction;
    if (pending == null) return 'لا توجد عملية معلقة للتأكيد.';
    _pendingAction = null;

    final session = _chat;
    if (session == null) return 'انتهت جلسة العملية. أعد طلب العملية من جديد.';

    final result = await _executeThroughGateway(
      pending.name,
      pending.args,
      userConfirmed: true,
    );
    await _audit(
      action: 'ai_tool_executed',
      result: result['ok'] == true ? 'success' : 'blocked',
      details: {
        'tool': pending.name,
        'permission': result['permission'],
        'confirmedByUser': true,
      },
    );

    var response = await session.sendMessage(
      Content.functionResponse(pending.name, result, id: pending.id),
    );

    for (var round = 0; round < _maxToolRounds; round++) {
      final calls = response.functionCalls.toList();
      if (calls.isEmpty) break;
      for (final call in calls) {
        await _audit(
          action: 'ai_tool_requested',
          result: 'requested',
          details: {'tool': call.name, 'args': call.args},
        );
        final next = await _executeThroughGateway(call.name, call.args);
        if (next['permission'] == 'confirmation_required') {
          _pendingAction = _PendingAiAction(
            name: call.name,
            args: Map<String, Object?>.from(call.args),
            id: call.id,
          );
          return 'توجد عملية أخرى تحتاج تأكيدك الصريح قبل التنفيذ.';
        }
        await _audit(
          action: 'ai_tool_executed',
          result: next['ok'] == true ? 'success' : 'blocked',
          details: {'tool': call.name, 'permission': next['permission']},
        );
        response = await session.sendMessage(
          Content.functionResponse(call.name, next, id: call.id),
        );
      }
    }

    final answer = response.text?.trim();
    return answer?.isNotEmpty == true
        ? answer!
        : (result['message']?.toString() ?? 'تمت معالجة العملية.');
  }

  void cancelPendingAction() {
    final pending = _pendingAction;
    _pendingAction = null;
    if (pending != null) {
      _audit(
        action: 'ai_action_confirmation_cancelled',
        result: 'cancelled',
        details: {'tool': pending.name},
      );
    }
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
    _pendingAction = null;
    _chat = null;
  }
}

class _PendingAiAction {
  final String name;
  final Map<String, Object?> args;
  final String? id;

  const _PendingAiAction({
    required this.name,
    required this.args,
    required this.id,
  });
}
