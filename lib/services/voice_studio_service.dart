import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class VoiceStudioService {
  static const baseUrl = String.fromEnvironment(
    'VOICESTUDIO_BASE_URL',
    defaultValue: '',
  );

  static const apiKey = String.fromEnvironment(
    'VOICESTUDIO_API_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;

  static Uri _uri(String path) {
    final base = baseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    return Uri.parse('\${base}\$path');
  }

  static Map<String, String> _headers({String? contentType}) {
    return {
      if (contentType != null) 'Content-Type': contentType,
      if (apiKey.trim().isNotEmpty)
        'Authorization': 'Bearer \${apiKey.trim()}',
    };
  }

  static Future<Map<String, dynamic>> health() async {
    _requireConfigured();
    final response = await http.get(_uri('/health'), headers: _headers());
    _throwIfFailed(response);
    return _decodeObject(response.body);
  }

  static Future<List<Map<String, dynamic>>> listVoices() async {
    _requireConfigured();
    final response = await http.get(
      _uri('/v1/audio/voices'),
      headers: _headers(),
    );
    _throwIfFailed(response);

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (decoded is Map && decoded['voices'] is List) {
      return (decoded['voices'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    throw const FormatException('VoiceStudio returned an invalid voices payload.');
  }

  static Future<Uint8List> synthesize({
    required String text,
    String? voice,
    String model = 'tts-1',
    String responseFormat = 'wav',
  }) async {
    _requireConfigured();
    final response = await http.post(
      _uri('/v1/audio/speech'),
      headers: _headers(contentType: 'application/json'),
      body: jsonEncode({
        'model': model,
        if (voice != null && voice.trim().isNotEmpty) 'voice': voice.trim(),
        'input': text,
        'response_format': responseFormat,
      }),
    );
    _throwIfFailed(response);
    if (response.bodyBytes.isEmpty) {
      throw const FormatException('VoiceStudio returned empty audio.');
    }
    return response.bodyBytes;
  }

  static Future<String> transcribe({
    required Uint8List audio,
    required String filename,
    String model = 'whisper-1',
  }) async {
    _requireConfigured();

    final request = http.MultipartRequest(
      'POST',
      _uri('/v1/audio/transcriptions'),
    );
    if (apiKey.trim().isNotEmpty) {
      request.headers['Authorization'] = 'Bearer \${apiKey.trim()}';
    }
    request.fields['model'] = model;
    request.fields['response_format'] = 'json';
    request.files.add(
      http.MultipartFile.fromBytes('file', audio, filename: filename),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceStudioException(response.statusCode, _extractError(body));
    }

    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['text'] is String) {
      return decoded['text'] as String;
    }
    if (decoded is String) return decoded;
    throw const FormatException('VoiceStudio returned an invalid transcript.');
  }

  static void _requireConfigured() {
    if (!isConfigured) {
      throw const VoiceStudioException(
        0,
        'VoiceStudio غير مُهيأ: اضبط VOICESTUDIO_BASE_URL أولاً.',
      );
    }
  }

  static Map<String, dynamic> _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('VoiceStudio returned an invalid object.');
  }

  static void _throwIfFailed(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceStudioException(
        response.statusCode,
        _extractError(response.body),
      );
    }
  }

  static String _extractError(String body) {
    if (body.trim().isEmpty) return 'VoiceStudio request failed.';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final value = decoded['detail'] ?? decoded['error'] ?? decoded['message'];
        if (value != null) return value.toString();
      }
    } catch (_) {}
    return body;
  }
}

class VoiceStudioException implements Exception {
  const VoiceStudioException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'VoiceStudioException(\$statusCode): \$message';
}
