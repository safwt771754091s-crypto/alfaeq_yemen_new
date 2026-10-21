import 'package:alfaeq_yemen/ai/ai_permission_gateway.dart';
import 'package:alfaeq_yemen/ai/ai_service.dart';
import 'package:alfaeq_yemen/ai/ai_tools.dart';
import 'package:alfaeq_yemen/services/unsloth_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The model provider is an external service that is not reachable in unit
/// tests, so it is faked. Everything else (message history management,
/// permission gating, pending-action lifecycle) is the real AlfaeqAiService.
class _FakeProvider extends UnslothAiService {
  _FakeProvider() : super(client: SupabaseClient('https://example.supabase.co', 'anon'));

  final List<List<Map<String, dynamic>>> calls = [];
  int _n = 0;

  @override
  Future<Map<String, dynamic>> chatCompletion({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double temperature = .2,
    int maxTokens = 1024,
    String toolChoice = 'auto',
  }) async {
    calls.add(messages.map((m) => Map<String, dynamic>.from(m)).toList());
    _n++;
    if (_n == 1) {
      return {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'add_to_cart',
                    'arguments': '{"productId":"p1","quantity":1}',
                  },
                },
              ],
            },
          },
        ],
      };
    }
    return {
      'choices': [
        {'message': {'role': 'assistant', 'content': 'تمام'}},
      ],
    };
  }
}

class _ConfirmPermission extends AlfaeqAiPermissionGateway {
  @override
  Future<AiPermissionDecision> authorize(String action, {bool userConfirmed = false}) async {
    if (userConfirmed) {
      return AiPermissionDecision.allowed(role: 'customer', level: AiActionLevel.reversible);
    }
    return AiPermissionDecision.confirmationRequired('تأكيد', level: AiActionLevel.reversible);
  }
}

void main() {
  group('AlfaeqAiService conversation history', () {
    test('cancelling a pending action leaves no dangling tool call', () async {
      final provider = _FakeProvider();
      final client = SupabaseClient('https://example.supabase.co', 'anon');
      final service = AlfaeqAiService(
        ai: provider,
        tools: AlfaeqAiToolRegistry(client: client),
        permissions: _ConfirmPermission(),
        client: client,
      );

      await service.sendMessage('أضف منتجاً');
      expect(service.hasPendingConfirmation, isTrue);

      service.cancelPendingAction();
      expect(service.hasPendingConfirmation, isFalse);

      final reply = await service.sendMessage('مرحباً');
      expect(reply, 'تمام');

      final sent = provider.calls.last;
      for (var i = 0; i < sent.length; i++) {
        final message = sent[i];
        final toolCalls = message['tool_calls'];
        if (message['role'] == 'assistant' && toolCalls is List && toolCalls.isNotEmpty) {
          final expected = toolCalls.map((call) => (call as Map)['id']).toSet();
          final answered = sent
              .skip(i + 1)
              .where((m) => m['role'] == 'tool')
              .map((m) => m['tool_call_id'])
              .toSet();
          expect(answered.containsAll(expected), isTrue,
              reason: 'every assistant tool_call must have a matching tool result');
        }
      }
    });

    test('a confirmation gate answers every sibling tool call', () async {
      final provider = _MultiCallProvider();
      final client = SupabaseClient('https://example.supabase.co', 'anon');
      final service = AlfaeqAiService(
        ai: provider,
        tools: AlfaeqAiToolRegistry(client: client),
        permissions: _ConfirmPermission(),
        client: client,
      );

      final reply = await service.sendMessage('نفّذ عمليتين');
      expect(service.hasPendingConfirmation, isTrue);

      // The follow-up request is built from the same history the provider saw.
      await service.sendMessage('مرحباً');
      final sent = provider.calls.last;
      for (var i = 0; i < sent.length; i++) {
        final message = sent[i];
        final toolCalls = message['tool_calls'];
        if (message['role'] == 'assistant' && toolCalls is List && toolCalls.isNotEmpty) {
          final expected = toolCalls.map((call) => (call as Map)['id']).toSet();
          final answered = sent
              .skip(i + 1)
              .where((m) => m['role'] == 'tool')
              .map((m) => m['tool_call_id'])
              .toSet();
          expect(answered.containsAll(expected), isTrue,
              reason: 'every sibling tool_call must be answered even when one needs confirmation');
        }
      }
      expect(reply.trim().isNotEmpty, isTrue);
    });
  });
}

/// Emits two tool calls in one assistant turn; the first is reversible and
/// therefore requires confirmation, the second is a plain read.
class _MultiCallProvider extends UnslothAiService {
  _MultiCallProvider() : super(client: SupabaseClient('https://example.supabase.co', 'anon'));

  final List<List<Map<String, dynamic>>> calls = [];

  @override
  Future<Map<String, dynamic>> chatCompletion({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double temperature = .2,
    int maxTokens = 1024,
    String toolChoice = 'auto',
  }) async {
    calls.add(messages.map((m) => Map<String, dynamic>.from(m)).toList());
    if (calls.length == 1) {
      return {
        'choices': [
          {
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_a',
                  'type': 'function',
                  'function': {
                    'name': 'add_to_cart',
                    'arguments': '{"productId":"p1","quantity":1}',
                  },
                },
                {
                  'id': 'call_b',
                  'type': 'function',
                  'function': {'name': 'get_my_cart', 'arguments': '{}'},
                },
              ],
            },
          },
        ],
      };
    }
    return {
      'choices': [
        {'message': {'role': 'assistant', 'content': 'تمام'}},
      ],
    };
  }
}
