import 'package:supabase_flutter/supabase_flutter.dart';

/// Secure routing policy for the developer AI layer.
///
/// Provider credentials stay on the trusted AI gateway. The Flutter client
/// only receives a provider policy and never stores provider secrets.
class AiProviderRouter {
  AiProviderRouter({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  final SupabaseClient _client;

  static const supportedProviders = <String>[
    'unsloth',
    'openai_compatible',
    'anthropic_compatible',
    'deepseek',
    'kimi',
    'openrouter',
  ];

  static const _developerRoles = <String>{'developer', 'admin', 'owner'};

  String chooseRoute({String? preferredProvider, bool production = true}) {
    final preferred = preferredProvider?.trim();
    if (preferred != null && supportedProviders.contains(preferred)) {
      return preferred;
    }
    return production ? 'unsloth' : 'unsloth';
  }

  List<String> fallbackChain({String? preferredProvider}) {
    final first = chooseRoute(preferredProvider: preferredProvider);
    final chain = <String>[first];
    for (final provider in const [
      'openai_compatible',
      'anthropic_compatible',
      'deepseek',
      'kimi',
      'openrouter',
    ]) {
      if (!chain.contains(provider)) chain.add(provider);
    }
    return chain;
  }

  bool isProviderSupported(String provider) => supportedProviders.contains(provider);

  bool canUseDeveloperRouter(String role) => _developerRoles.contains(role);

  Future<void> auditRoute({
    required String provider,
    required String result,
    required String role,
    String operation = 'ai_provider_route',
    Map<String, dynamic>? metadata,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null || !canUseDeveloperRouter(role)) return;

    await _client.from('audit_logs').insert({
      'actor_uid': user.id,
      'actor_email': user.email,
      'role': role,
      'action': operation,
      'result': result,
      'details': {
        'provider': provider,
        'metadata': metadata ?? const <String, dynamic>{},
      },
      'source': 'ai_provider_router',
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Map<String, dynamic> diagnostics({String? preferredProvider}) => {
        'primary': chooseRoute(preferredProvider: preferredProvider),
        'fallbacks': fallbackChain(preferredProvider: preferredProvider),
        'supportedProviders': supportedProviders,
        'credentials': 'server_only',
        'customerDataForwarding': false,
      };
}

/// Local alias kept here so the router has no Firebase dependency.
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
}
