import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Central policy boundary for Alfaeq AI actions.
///
/// Default-deny: a tool must be explicitly registered here before the AI can
/// execute it. Read actions may run automatically when the caller is allowed.
/// Reversible/sensitive actions require explicit user confirmation and the
/// appropriate role. Sensitive operations should ultimately be executed by a
/// trusted backend function, not directly by the client.
class AlfaeqAiPermissionGateway {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AlfaeqAiPermissionGateway({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  static const Map<String, _AiActionPolicy> _policies = {
    'search_catalog': _AiActionPolicy(
      level: AiActionLevel.read,
      roles: <String>{'customer', 'merchant', 'driver', 'developer', 'admin', 'owner'},
      requiresSignIn: false,
    ),
    'get_my_orders': _AiActionPolicy(
      level: AiActionLevel.read,
      roles: <String>{'customer', 'merchant', 'driver', 'developer', 'admin', 'owner'},
      requiresSignIn: true,
    ),
    'get_my_account_summary': _AiActionPolicy(
      level: AiActionLevel.read,
      roles: <String>{'customer', 'merchant', 'driver', 'developer', 'admin', 'owner'},
      requiresSignIn: true,
    ),
    'get_security_summary': _AiActionPolicy(
      level: AiActionLevel.read,
      roles: <String>{'developer', 'admin', 'owner'},
      requiresSignIn: true,
    ),
    'create_order_draft': _AiActionPolicy(
      level: AiActionLevel.reversible,
      roles: <String>{'customer', 'merchant', 'driver', 'developer', 'admin', 'owner'},
      requiresSignIn: true,
    ),
  };

  Future<AiPermissionDecision> authorize(
    String action, {
    bool userConfirmed = false,
  }) async {
    final policy = _policies[action];
    if (policy == null) {
      return AiPermissionDecision.denied(
        'هذه العملية غير مسجلة في بوابة صلاحيات الوكيل.',
      );
    }

    final user = _auth.currentUser;
    if (policy.requiresSignIn && user == null) {
      return AiPermissionDecision.denied('يجب تسجيل الدخول أولاً.');
    }

    if (user == null) {
      return AiPermissionDecision.allowed(role: 'anonymous', level: policy.level);
    }

    final role = await _resolveRole(user);
    if (!policy.roles.contains(role)) {
      return AiPermissionDecision.denied(
        'ليس لديك صلاحية لتنفيذ هذه العملية.',
        role: role,
      );
    }

    if (policy.level != AiActionLevel.read && !userConfirmed) {
      return AiPermissionDecision.confirmationRequired(
        'هذه العملية تتطلب تأكيداً صريحاً قبل التنفيذ.',
        role: role,
        level: policy.level,
      );
    }

    return AiPermissionDecision.allowed(role: role, level: policy.level);
  }

  Future<String> _resolveRole(User user) async {
    try {
      final token = await user.getIdTokenResult(true);
      final claimRole = token.claims?['role']?.toString().toLowerCase();
      if (claimRole != null && claimRole.isNotEmpty) return claimRole;

      final doc = await _db.collection('users').doc(user.uid).get();
      final firestoreRole = doc.data()?['role']?.toString().toLowerCase();
      return firestoreRole == null || firestoreRole.isEmpty ? 'customer' : firestoreRole;
    } catch (_) {
      return 'customer';
    }
  }
}

enum AiActionLevel { read, reversible, sensitive }

class _AiActionPolicy {
  final AiActionLevel level;
  final Set<String> roles;
  final bool requiresSignIn;

  const _AiActionPolicy({
    required this.level,
    required this.roles,
    required this.requiresSignIn,
  });
}

class AiPermissionDecision {
  final bool allowed;
  final bool requiresConfirmation;
  final String message;
  final String? role;
  final AiActionLevel? level;

  const AiPermissionDecision({
    required this.allowed,
    required this.requiresConfirmation,
    required this.message,
    this.role,
    this.level,
  });

  factory AiPermissionDecision.allowed({
    required String role,
    required AiActionLevel level,
  }) => AiPermissionDecision(
        allowed: true,
        requiresConfirmation: false,
        message: 'مسموح',
        role: role,
        level: level,
      );

  factory AiPermissionDecision.denied(String message, {String? role}) =>
      AiPermissionDecision(
        allowed: false,
        requiresConfirmation: false,
        message: message,
        role: role,
      );

  factory AiPermissionDecision.confirmationRequired(
    String message, {
    String? role,
    AiActionLevel? level,
  }) => AiPermissionDecision(
        allowed: false,
        requiresConfirmation: true,
        message: message,
        role: role,
        level: level,
      );
}
