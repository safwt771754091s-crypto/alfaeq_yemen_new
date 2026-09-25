import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side Unsloth inference client.
/// Provider credentials never enter the Flutter application.
class UnslothAiService {
  UnslothAiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> chatCompletion({
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double temperature = 0.2,
    int maxTokens = 1024,
    String toolChoice = 'auto',
  }) async {
    final response = await _client.functions.invoke(
      'ai-gateway',
      body: <String, dynamic>{
        'messages': messages,
        'tools': tools,
        'tool_choice': toolChoice,
        if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': false,
      },
    );

    if (response.status < 200 || response.status >= 300) {
      throw StateError(_extractError(response.data));
    }

    final data = response.data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    throw StateError('Unsloth returned an unexpected response.');
  }

  Future<String> chat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double temperature = 0.2,
    int maxTokens = 1024,
  }) async {
    final data = await chatCompletion(
      messages: messages,
      tools: const [],
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
    final content = _content(data);
    if (content.isEmpty) throw StateError('Unsloth returned an empty response.');
    return content;
  }

  String extractContent(Map<String, dynamic> data) => _content(data);

  String _content(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = choices.first['message'];
      if (message is Map) {
        final content = message['content'];
        if (content is String) return content.trim();
      }
    }
    return '';
  }

  List<Map<String, dynamic>> extractToolCalls(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return const [];
    }
    final message = choices.first['message'];
    if (message is! Map) return const [];
    final raw = message['tool_calls'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic> extractAssistantMessage(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = choices.first['message'];
      if (message is Map) return Map<String, dynamic>.from(message);
    }
    return <String, dynamic>{'role': 'assistant', 'content': ''};
  }

  String _extractError(dynamic data) {
    if (data is Map) {
      final error = data['error'];
      if (error is String) return error;
      if (error is Map) {
        final message = error['message'];
        if (message is String) return message;
      }
    }
    if (data is String && data.isNotEmpty) {
      try {
        return _extractError(jsonDecode(data));
      } catch (_) {
        return data;
      }
    }
    return 'AI gateway request failed.';
  }
}
