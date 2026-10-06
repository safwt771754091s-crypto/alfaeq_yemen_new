import '../services/auth_service.dart';

enum AiActionLevel { read, reversible, sensitive }

class AiPermissionDecision {
  final bool allowed, requiresConfirmation;
  final String message;
  final String? role;
  final AiActionLevel? level;
  const AiPermissionDecision({required this.allowed,required this.requiresConfirmation,required this.message,this.role,this.level});
  factory AiPermissionDecision.allowed({required String role,required AiActionLevel level})=>AiPermissionDecision(allowed:true,requiresConfirmation:false,message:'مسموح',role:role,level:level);
  factory AiPermissionDecision.denied(String message,{String? role})=>AiPermissionDecision(allowed:false,requiresConfirmation:false,message:message,role:role);
  factory AiPermissionDecision.confirmationRequired(String message,{String? role,AiActionLevel? level})=>AiPermissionDecision(allowed:false,requiresConfirmation:true,message:message,role:role,level:level);
}
class AlfaeqAiPermissionGateway {
  final AuthService _auth;
  AlfaeqAiPermissionGateway({AuthService? auth}):_auth=auth??AuthService();
  static const _policies={
    'search_catalog':(AiActionLevel.read,<String>{'customer','merchant','driver','developer','admin','owner'},false),
    'get_my_orders':(AiActionLevel.read,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'get_my_order':(AiActionLevel.read,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'get_my_account_summary':(AiActionLevel.read,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'get_my_cart':(AiActionLevel.read,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'get_my_wallet':(AiActionLevel.read,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'find_nearby_stores':(AiActionLevel.read,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'add_to_cart':(AiActionLevel.reversible,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'update_cart_item':(AiActionLevel.reversible,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'remove_from_cart':(AiActionLevel.reversible,<String>{'customer','merchant','driver','developer','admin','owner'},true),
    'create_order_draft':(AiActionLevel.reversible,<String>{'customer','merchant','driver','developer','admin','owner'},true),
  };
  Future<AiPermissionDecision> authorize(String action,{bool userConfirmed=false}) async {
    final p=_policies[action]; if(p==null)return AiPermissionDecision.denied('هذه العملية غير مسجلة في بوابة صلاحيات ذكاء الفائق.');
    final user=_auth.currentUser; if(p.$3&&user==null)return AiPermissionDecision.denied('يجب تسجيل الدخول أولاً.');
    final role=await _auth.role(); if(user!=null&&!p.$2.contains(role))return AiPermissionDecision.denied('ليس لديك صلاحية لتنفيذ هذه العملية.',role:role);
    if(p.$1!=AiActionLevel.read&&!userConfirmed)return AiPermissionDecision.confirmationRequired('هذه العملية تتطلب تأكيداً صريحاً قبل التنفيذ.',role:role,level:p.$1);
    return AiPermissionDecision.allowed(role:user==null?'anonymous':role,level:p.$1);
  }
}