import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Server-side Unsloth inference client.
///
/// Provider credentials stay outside the Flutter application. The Supabase
/// Edge Function validates the user's session and forwards the request.
class UnslothAiService {
  UnslothAiService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<String> chat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double temperature = 0.2,
    int maxTokens = 1024,
  }) async {
    final response = await _client.functions.invoke(
      'ai-gateway',
      body: <String, dynamic>{
        'messages': messages,
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
    if (data is Map<String, dynamic>) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final message = first['message'];
          if (message is Map<String, dynamic>) {
            final content = message['content'];
            if (content is String && content.trim().isNotEmpty) {
              return content.trim();
            }
          }
        }
      }
    }

    throw StateError('Unsloth returned an unexpected response.');
  }

  String _extractError(dynamic data) {
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is String) return error;
      if (error is Map<String, dynamic>) {
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
