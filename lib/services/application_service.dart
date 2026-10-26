import 'supabase_service.dart';

/// Self-service applications to become a merchant (تاجر) or a driver (مندوب).
///
/// Submission is open to any signed-in customer; approval is staff-only and
/// happens in the admin review pages. The database RPCs (see migration
/// 20261026010000_merchant_driver_applications_v1.sql) enforce both rules and
/// perform the real side effects (store creation, role promotion).
class ApplicationService {
  static String? get _uid => SupabaseService.client.auth.currentUser?.id;

  Future<Map<String, dynamic>?> myMerchantApplication() async {
    final uid = _uid;
    if (uid == null) return null;
    final rows = await SupabaseService.client
        .from('merchant_applications')
        .select()
        .eq('uid', uid)
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<Map<String, dynamic>?> myDriverApplication() async {
    final uid = _uid;
    if (uid == null) return null;
    final rows = await SupabaseService.client
        .from('driver_applications')
        .select()
        .eq('uid', uid)
        .order('created_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  Future<void> submitMerchantApplication({
    required String applicantName,
    required String phone,
    required String storeName,
    String? sectionId,
    String? city,
    String? address,
    String? notes,
  }) async {
    await SupabaseService.client.rpc('merchant_application_submit', params: {
      'p_applicant_name': applicantName,
      'p_phone': phone,
      'p_store_name': storeName,
      'p_section_id': sectionId,
      'p_city': city,
      'p_address': address,
      'p_notes': notes,
    });
  }

  Future<void> submitDriverApplication({
    required String applicantName,
    required String phone,
    String? vehicleType,
    String? vehiclePlate,
    String? city,
    String? notes,
  }) async {
    await SupabaseService.client.rpc('driver_application_submit', params: {
      'p_applicant_name': applicantName,
      'p_phone': phone,
      'p_vehicle_type': vehicleType,
      'p_vehicle_plate': vehiclePlate,
      'p_city': city,
      'p_notes': notes,
    });
  }

  Future<void> cancelMerchantApplication(String id) async {
    await SupabaseService.client.rpc('merchant_application_cancel', params: {'p_application_id': id});
  }

  Future<void> cancelDriverApplication(String id) async {
    await SupabaseService.client.rpc('driver_application_cancel', params: {'p_application_id': id});
  }

  Stream<List<Map<String, dynamic>>> pendingMerchantApplicationsStream() {
    return SupabaseService.client
        .from('merchant_applications')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(100);
  }

  Stream<List<Map<String, dynamic>>> pendingDriverApplicationsStream() {
    return SupabaseService.client
        .from('driver_applications')
        .stream(primaryKey: ['id'])
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(100);
  }

  Future<void> decideMerchantApplication({
    required String id,
    required bool approve,
    String? reviewNotes,
  }) async {
    await SupabaseService.client.rpc('merchant_application_decide', params: {
      'p_application_id': id,
      'p_approve': approve,
      'p_review_notes': reviewNotes,
    });
  }

  Future<void> decideDriverApplication({
    required String id,
    required bool approve,
    String? reviewNotes,
  }) async {
    await SupabaseService.client.rpc('driver_application_decide', params: {
      'p_application_id': id,
      'p_approve': approve,
      'p_review_notes': reviewNotes,
    });
  }
}
