import 'dart:convert';

import '../services/unsloth_ai_service.dart';
import 'ai_permission_gateway.dart';
import 'ai_tools.dart';
import 'alfaeq_prompt_library.dart';

/// Production AI orchestration for Alfaeq Yemen.
///
/// Inference runs through Supabase -> Unsloth. Tool execution remains behind
/// the existing permission gateway and explicit confirmation flow.
class AlfaeqAiService {
  static const String modelName = '';
  static const int _maxToolRounds = 6;

  final AlfaeqAiToolRegistry _tools;
  final AlfaeqAiPermissionGateway _permissions;
  final UnslothAiService _ai;
  final List<Map<String, dynamic>> _messages = [];
  _PendingAiAction? _pendingAction;

  AlfaeqAiService({
    AlfaeqAiToolRegistry? tools,
    AlfaeqAiPermissionGateway? permissions,
    UnslothAiService? ai,
  })  : _tools = tools ?? AlfaeqAiToolRegistry(),
        _permissions = permissions ?? AlfaeqAiPermissionGateway(),
        _ai = ai ?? UnslothAiService() {
    _resetSystemMessage();
  }

  void _resetSystemMessage() {
    _messages.add({
      'role': 'system',
      'content': '''
${AlfaeqPromptLibrary.baseSystem}
استخدم الأدوات للحصول على بيانات حقيقية ولا تخمّن بيانات تشغيلية.
لا تطلب أو تكشف كلمات المرور أو مفاتيح API أو الرموز السرية أو بيانات الدفع الحساسة.
كل أداة تمر عبر بوابة الصلاحيات، والعمليات القابلة للتغيير تحتاج تأكيد المستخدم.
بيانات المنتجات والسلة والطلبات الحالية تأتي من طبقة البيانات الحقيقية في المنصة.
عند إنشاء الطلب: راجع المنتجات والكميات والعنوان وطريقة الدفع، ثم اطلب تأكيداً صريحاً.
create_order_draft ينشئ طلباً معلّقاً فقط ولا ينفذ أي دفع.
''',
    });
  }

  bool get hasPendingConfirmation => _pendingAction != null;
  String? get pendingActionName => _pendingAction?.name;

  String get pendingActionDescription {
    final pending = _pendingAction;
    if (pending == null) return '';
    final args = pending.args;
    switch (pending.name) {
      case 'create_order_draft':
        final rawItems = args['items'];
        final items = rawItems is List ? rawItems : const [];
        final itemLines = <String>[];
        for (final raw in items.take(20)) {
          if (raw is! Map) continue;
          final productId = (raw['productId'] ?? '').toString();
          final quantity = (raw['quantity'] as num?)?.toInt() ?? 0;
          final name = (raw['name'] ?? '').toString().trim();
          final label = name.isNotEmpty ? name : 'منتج $productId';
          if (quantity > 0) itemLines.add('• $label × $quantity');
        }
        final payment = (args['paymentMethod'] ?? '').toString();
        final address = (args['address'] ?? '').toString().trim();
        final buffer = StringBuffer('سيتم إنشاء طلب معلّق فقط بعد التحقق من بيانات المنتجات والأسعار الحالية.');
        if (itemLines.isNotEmpty) buffer.write('\n\nالمنتجات:\n${itemLines.join('\n')}');
        if (payment.isNotEmpty) buffer.write('\n\nطريقة الدفع: ${_paymentLabel(payment)}');
        if (address.isNotEmpty) buffer.write('\nعنوان التوصيل: $address');
        return buffer.toString();
      case 'add_to_cart':
        return 'إضافة المنتج ${args['productId']} بكمية ${args['quantity']} إلى سلتك.';
      case 'update_cart_item':
        return 'تعديل كمية المنتج ${args['productId']} إلى ${args['quantity']}.';
      case 'remove_from_cart':
        return 'حذف المنتج ${args['productId']} من سلتك.';
      default:
        return 'تنفيذ العملية: ${pending.name}.';
    }
  }

  String _paymentLabel(String value) {
    switch (value) {
      case 'cash_on_delivery': return 'الدفع عند الاستلام';
      case 'al_kuraimi': return 'تحويل الكريمي';
      case 'cash_wallet': return 'محفظة كاش';
      case 'jeeb_wallet': return 'محفظة جيب';
      default: return value;
    }
  }

  List<Map<String, dynamic>> get _toolSchemas => [
    _tool('search_catalog', 'Search products and stores.', {
      'query': {'type': 'string', 'description': 'Arabic or English search phrase.'},
      'type': {'type': 'string', 'enum': ['products', 'stores', 'both']},
    }, required: ['query']),
    _tool('get_my_orders', 'Read the signed-in user orders.', {
      'status': {'type': 'string', 'enum': ['all', 'pending', 'confirmed', 'preparing', 'shipped', 'delivered', 'cancelled']},
    }),
    _tool('get_my_order', 'Read one order belonging to the signed-in user.', {
      'orderId': {'type': 'string'},
    }, required: ['orderId']),
    _tool('get_my_account_summary', 'Read a safe account summary.', {}),
    _tool('get_security_summary', 'Read a non-sensitive security summary for authorized staff.', {}),
    _tool('get_my_cart', 'Read the signed-in user cart.', {}),
    _tool('add_to_cart', 'Add an active product to the cart.', {
      'productId': {'type': 'string'},
      'quantity': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    }, required: ['productId', 'quantity']),
    _tool('update_cart_item', 'Set a cart item quantity.', {
      'productId': {'type': 'string'},
      'quantity': {'type': 'integer', 'minimum': 1, 'maximum': 100},
    }, required: ['productId', 'quantity']),
    _tool('remove_from_cart', 'Remove a product from the cart.', {
      'productId': {'type': 'string'},
    }, required: ['productId']),
    _tool('create_order_draft', 'Create a pending order after explicit user confirmation. Never process payment.', {
      'items': {
        'type': 'array',
        'minItems': 1,
        'maxItems': 20,
        'items': {
          'type': 'object',
          'properties': {
            'productId': {'type': 'string'},
            'name': {'type': 'string'},
            'quantity': {'type': 'integer', 'minimum': 1, 'maximum': 100},
            'price': {'type': 'number'},
            'storeId': {'type': 'string'},
          },
          'required': ['productId', 'name', 'quantity'],
        },
      },
      'address': {'type': 'string'},
      'paymentMethod': {'type': 'string', 'enum': ['cash_on_delivery', 'al_kuraimi', 'cash_wallet', 'jeeb_wallet']},
    }, required: ['items', 'address', 'paymentMethod']),
  ];

  Map<String, dynamic> _tool(
    String name,
    String description,
    Map<String, dynamic> properties, {
    List<String> required = const [],
  }) => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
        'additionalProperties': false,
      },
    },
  };

  Future<void> _audit({
    required String action,
    required String result,
    Map<String, dynamic>? details,
  }) async {
    // Tool registry already owns the detailed audit path. This hook deliberately
    // avoids writing provider secrets, prompts, or customer payloads.
  }

  Future<Map<String, Object?>> _execute(
    String name,
    Map<String, Object?> args, {
    bool confirmed = false,
  }) async {
    final decision = await _permissions.authorize(name, userConfirmed: confirmed);
    if (!decision.allowed) {
      return {
        'ok': false,
        'error': decision.message,
        'permission': decision.requiresConfirmation ? 'confirmation_required' : 'denied',
      };
    }
    return _tools.execute(
      name,
      args,
      audit: _audit,
      userConfirmed: confirmed,
    );
  }

  Future<String> _runUntilText() async {
    for (var round = 0; round < _maxToolRounds; round++) {
      final data = await _ai.chatCompletion(
        messages: List<Map<String, dynamic>>.from(_messages),
        tools: _toolSchemas,
        model: modelName.isEmpty ? null : modelName,
        temperature: 0.2,
        maxTokens: 1400,
      );

      final assistant = _ai.extractAssistantMessage(data);
      final calls = _ai.extractToolCalls(data);
      _messages.add(assistant);

      if (calls.isEmpty) {
        final answer = _ai.extractContent(data);
        return answer.isNotEmpty ? answer : 'لم يصل رد نصي من خدمة الذكاء الاصطناعي.';
      }

      for (final call in calls) {
        final function = call['function'];
        if (function is! Map) continue;
        final name = (function['name'] ?? '').toString();
        final rawArguments = function['arguments'];
        Map<String, dynamic> decoded = {};
        if (rawArguments is String && rawArguments.trim().isNotEmpty) {
          try {
            final parsed = jsonDecode(rawArguments);
            if (parsed is Map) decoded = Map<String, dynamic>.from(parsed);
          } catch (_) {
            decoded = {};
          }
        } else if (rawArguments is Map) {
          decoded = Map<String, dynamic>.from(rawArguments);
        }

        final result = await _execute(name, Map<String, Object?>.from(decoded));
        if (result['permission'] == 'confirmation_required') {
          _pendingAction = _PendingAiAction(
            name: name,
            args: Map<String, Object?>.from(decoded),
            id: (call['id'] ?? '').toString(),
          );
          return 'هذه العملية تحتاج تأكيدك الصريح قبل التنفيذ. راجع التفاصيل ثم اضغط «تأكيد التنفيذ».';
        }

        _messages.add({
          'role': 'tool',
          'tool_call_id': (call['id'] ?? '').toString(),
          'name': name,
          'content': jsonEncode(result),
        });
      }
    }
    return 'توقفت العملية بعد الوصول إلى الحد الآمن لاستدعاءات الأدوات.';
  }

  Future<String> sendMessage(String message) async {
    final text = message.trim();
    if (text.isEmpty) return '';
    _messages.add({'role': 'user', 'content': text});
    try {
      return await _runUntilText();
    } catch (e) {
      return 'تعذر الاتصال بخدمة ذكاء الفائق يمن حالياً. تحقق من إعداد Supabase وUnsloth ثم أعد المحاولة.';
    }
  }

  Future<String> confirmPendingAction() async {
    final pending = _pendingAction;
    if (pending == null) return 'لا توجد عملية معلقة للتأكيد.';
    _pendingAction = null;

    final result = await _execute(pending.name, pending.args, confirmed: true);
    _messages.add({
      'role': 'tool',
      'tool_call_id': pending.id ?? '',
      'name': pending.name,
      'content': jsonEncode(result),
    });
    try {
      return await _runUntilText();
    } catch (_) {
      return result['message']?.toString() ?? 'تم تنفيذ العملية، لكن تعذر الحصول على الرد النهائي من الذكاء الاصطناعي.';
    }
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
    final answer = await sendMessage(message);
    if (answer.isNotEmpty) yield answer;
  }

  void resetConversation() {
    _messages.clear();
    _resetSystemMessage();
    _pendingAction = null;
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
