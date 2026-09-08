import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Secure routing policy for the developer AI layer.
///
/// This is intentionally a policy/router layer, not a client-side API-key
/// proxy. Provider credentials must remain on a trusted backend.
class AiProviderRouter {
  AiProviderRouter({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const supportedProviders = <String>[
    'firebase_gemini',
    'openai_compatible',
    'anthropic_compatible',
    'deepseek',
    'kimi',
    'openrouter',
  ];

  static const _developerRoles = <String>{'developer', 'admin', 'owner'};

  /// Chooses a provider without exposing provider credentials to the app.
  ///
  /// The returned route is a policy decision for a trusted backend/router.
  String chooseRoute({String? preferredProvider, bool production = true}) {
    final preferred = preferredProvider?.trim();
    if (preferred != null && supportedProviders.contains(preferred)) {
      return preferred;
    }
    return production ? 'firebase_gemini' : 'firebase_gemini';
  }

  List<String> fallbackChain({String? preferredProvider}) {
    final first = chooseRoute(preferredProvider: preferredProvider);
    final chain = <String>[first];
    for (final provider in const [
      'deepseek',
      'kimi',
      'openrouter',
      'openai_compatible',
      'anthropic_compatible',
      'firebase_gemini',
    ]) {
      if (!chain.contains(provider)) chain.add(provider);
    }
    return chain;
  }

  bool isProviderSupported(String provider) => supportedProviders.contains(provider);

  bool canUseDeveloperRouter(String role) => _developerRoles.contains(role);

  /// Records routing decisions without recording prompts, secrets, or customer data.
  Future<void> auditRoute({
    required String provider,
    required String result,
    required String role,
    String operation = 'ai_provider_route',
    Map<String, dynamic>? metadata,
  }) async {
    final user = _auth.currentUser;
    if (user == null || !canUseDeveloperRouter(role)) return;
    await _db.collection('auditLogs').add({
      'actorUid': user.uid,
      'actorEmail': user.email,
      'role': role,
      'action': operation,
      'result': result,
      'details': {
        'provider': provider,
        'metadata': metadata ?? const <String, dynamic>{},
      },
      'source': 'ai_provider_router',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Produces a safe, non-secret diagnostic snapshot for the developer center.
  Map<String, dynamic> diagnostics({String? preferredProvider}) => {
        'primary': chooseRoute(preferredProvider: preferredProvider),
        'fallbacks': fallbackChain(preferredProvider: preferredProvider),
        'supportedProviders': supportedProviders,
        'credentials': 'server_only',
        'customerDataForwarding': false,
      };
}
