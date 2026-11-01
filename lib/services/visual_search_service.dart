import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';
import 'unsloth_ai_service.dart';

/// Where the user wants to get the product picture from.
enum VisualSource { gallery, camera }

/// A gateway/provider failure whose [toString] is already the user-facing
/// Arabic message (same convention as [AiGatewayException]).
class VisualSearchException implements Exception {
  final String message;
  const VisualSearchException(this.message);
  @override
  String toString() => message;
}

/// Result of a visual product search: what the model guessed, the uploaded
/// picture URL (empty when the user is not signed in), and the matching
/// catalog rows.
class VisualMatchResult {
  final String guess;
  final String uploadedUrl;
  final List<Map<String, dynamic>> products;
  const VisualMatchResult({
    required this.guess,
    required this.uploadedUrl,
    required this.products,
  });

  bool get hasGuess => guess.trim().isNotEmpty;
}

/// WeChat-style "search by picture": the user supplies a photo (from the
/// gallery or the camera), the model names the product, and the catalog is
/// searched with that name. The picture is also uploaded to Supabase Storage
/// so it can be reused as the product image.
class VisualSearchService {
  VisualSearchService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;
  static final ImagePicker _picker = ImagePicker();

  /// Opens the gallery or the camera and returns the chosen image bytes, or
  /// null when the user cancels.
  Future<({Uint8List bytes, String extension})?> pick(VisualSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source == VisualSource.camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    return (bytes: bytes, extension: _extensionOf(file.name));
  }

  /// Uploads the picture to the public `media` bucket under the signed-in
  /// user's folder and returns its public URL. Returns an empty string when
  /// there is no session (the visual search still works without an upload).
  Future<String> upload(Uint8List bytes, String extension) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return '';
    final ext = extension.replaceAll('.', '').toLowerCase();
    final path = '$uid/searches/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _client.storage.from('media').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(cacheControl: '31536000'),
        );
    return _client.storage.from('media').getPublicUrl(path);
  }

  /// Runs the full flow: upload (best effort) then ask the model to name the
  /// product and search the catalog for it.
  Future<VisualMatchResult> search(Uint8List bytes, String extension) async {
    final uploadedUrl = await _safeUpload(bytes, extension);
    final guess = await _guessProduct(bytes, extension);
    final products = await searchCatalog(guess);
    return VisualMatchResult(guess: guess, uploadedUrl: uploadedUrl, products: products);
  }

  Future<String> _safeUpload(Uint8List bytes, String extension) async {
    try {
      return await upload(bytes, extension);
    } catch (_) {
      // The upload is a convenience; a storage hiccup must not block the search.
      return '';
    }
  }

  static const _prompt = '''
أنت مساعد متجر. انظر إلى صورة المنتج واذكر اسمه بالعربية في عبارة قصيرة جداً.
أعد النتيجة بصيغة JSON فقط دون أي شرح:
{"name":"اسم المنتج","keywords":["كلمة","كلمة","كلمة"]}
اجعل keywords من 1 إلى 4 كلمات مفتاحية شائعة تُستخدم في المتاجر، وبدون أرقام ماركات إن لم تكن واضحة.
''';

  Future<String> _guessProduct(Uint8List bytes, String extension) async {
    final dataUri = 'data:${_mime(extension)};base64,${base64Encode(bytes)}';
    late final FunctionResponse res;
    try {
      res = await _client.functions.invoke('ai-gateway', body: {
        'messages': [
          {'role': 'system', 'content': _prompt},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'حدّد المنتج في هذه الصورة.'},
              {
                'type': 'image_url',
                'image_url': {'url': dataUri},
              },
            ],
          },
        ],
        'temperature': 0.1,
        'max_tokens': 200,
        'stream': false,
      });
    } on FunctionException catch (e) {
      throw VisualSearchException(_describeVisionError(e.details));
    } catch (_) {
      throw const VisualSearchException(
        'تعذّر الاتصال بخدمة التعرّف على الصور. تحقق من اتصالك ثم أعد المحاولة.',
      );
    }
    return parseGuess(_extractContent(res.data));
  }

  String _extractContent(dynamic data) {
    dynamic d = data;
    if (d is String) {
      try {
        d = jsonDecode(d);
      } catch (_) {
        return '';
      }
    }
    if (d is! Map) return '';
    final choices = d['choices'];
    if (choices is List && choices.isNotEmpty && choices.first is Map) {
      final message = (choices.first as Map)['message'];
      if (message is Map && message['content'] is String) {
        return (message['content'] as String).trim();
      }
    }
    return '';
  }

  /// The model may answer with plain text or a fenced JSON block; keep only the
  /// product name so the catalog query stays clean. Public for unit testing.
  static String parseGuess(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    text = text.replaceAll(RegExp(r'^```[a-zA-Z]*'), '').replaceAll('```', '').trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        final decoded = jsonDecode(text.substring(start, end + 1));
        if (decoded is Map) {
          final name = (decoded['name'] ?? '').toString().trim();
          if (name.isNotEmpty) return name;
          final keywords = decoded['keywords'];
          if (keywords is List && keywords.isNotEmpty) {
            return keywords.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).join(' ').trim();
          }
        }
      } catch (_) {
        // fall through to the plain-text path
      }
    }
    // No JSON: take the first line, strip quotes/bullets.
    final firstLine = text.split('\n').first.trim();
    return firstLine
        .replaceAll(RegExp(r'^[\s\-\*"\u00AB\u00BB]+'), '')
        .replaceAll(RegExp(r'[\s"\u00AB\u00BB]+$'), '')
        .trim();
  }

  /// Searches active products by the guessed name. Requires every significant
  /// word to appear (in the name or description) so results stay relevant;
  /// falls back to the loose match when nothing is strict enough.
  Future<List<Map<String, dynamic>>> searchCatalog(String guess, {int limit = 30}) async {
    final tokens = _tokens(guess);
    if (tokens.isEmpty || !SupabaseService.isInitialized) return const [];

    final orFilter = tokens.map((t) => 'name.ilike.%$t%,description.ilike.%$t%').join(',');
    List<Map<String, dynamic>> rows;
    try {
      final raw = await _client
          .from('products')
          .select()
          .eq('status', 'active')
          .or(orFilter)
          .order('name')
          .limit(limit * 2);
      rows = raw.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return const [];
    }
    if (rows.isEmpty) return const [];

    final strict = rows.where((p) {
      final hay = '${p['name'] ?? ''} ${p['description'] ?? ''}'.toLowerCase();
      return tokens.every(hay.contains);
    }).toList();
    final chosen = strict.isNotEmpty ? strict : rows;
    chosen.sort((a, b) => _score(b, tokens).compareTo(_score(a, tokens)));
    return chosen.take(limit).toList();
  }

  int _score(Map<String, dynamic> product, List<String> tokens) {
    final name = (product['name'] ?? '').toString().toLowerCase();
    final desc = (product['description'] ?? '').toString().toLowerCase();
    var score = 0;
    for (final t in tokens) {
      if (name.contains(t)) score += 2;
      if (desc.contains(t)) score += 1;
    }
    return score;
  }

  static const _stopwords = {
    'منتج', 'منتجاً', 'المنتج', 'صورة', 'الصورة', 'علبة', 'عبوة', 'كيس', 'حزمة',
    'قطعة', 'نوع', 'لون', 'الأصلي', 'أصلي', 'جديد', 'حجم', 'كبير', 'صغير',
    'a', 'an', 'the', 'of', 'product', 'image', 'photo', 'item', 'pack',
  };

  List<String> _tokens(String guess) {
    final cleaned = guess
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];
    final seen = <String>{};
    final tokens = <String>[];
    for (final word in cleaned.split(' ')) {
      final w = word.trim();
      if (w.length < 2 || _stopwords.contains(w) || seen.contains(w)) continue;
      seen.add(w);
      tokens.add(w);
      if (tokens.length == 4) break;
    }
    return tokens;
  }

  /// Maps gateway/provider errors to Arabic guidance. The built-in free
  /// providers answer text only, so an image request is the common failure and
  /// gets a specific, actionable message.
  static String _describeVisionError(dynamic details) {
    final text = details?.toString().toLowerCase() ?? '';
    final base = UnslothAiService.describeError(details);
    if (text.contains('image') || text.contains('vision') || text.contains('multimodal')) {
      return 'خدمة الذكاء الحالية لا تدعم قراءة الصور. للبحث الذكي بالصورة فعّل مزوّداً يدعم الصور '
          '(مثل Google AI Studio) في إعدادات الذكاء، أو اكتب اسم المنتج للبحث.';
    }
    return base;
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'jpg';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _mime(String extension) => switch (extension.replaceAll('.', '').toLowerCase()) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        'heic' => 'image/heic',
        'avif' => 'image/avif',
        _ => 'image/jpeg',
      };
}
