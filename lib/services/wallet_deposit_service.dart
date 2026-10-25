import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

/// Bank deposits (إيداع بنكي) into the الفائق يمن wallet via the official
/// Al-Kuraimi accounts. Creation is open to any signed-in user; approval is
/// master-owner only and credits the wallet server-side.
class WalletDepositService {
  static final _db = SupabaseService.client;
  static const receiptBucket = 'deposits';

  Future<List<Map<String, dynamic>>> bankAccounts() async {
    final rows = await _db
        .from('master_bank_accounts')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Uploads a receipt image and returns its storage path (bucket is private).
  Future<String> uploadReceipt(Uint8List bytes, String extension) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) throw StateError('يجب تسجيل الدخول أولاً.');
    final ext = extension.replaceAll('.', '').toLowerCase();
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$safeExt';
    await _db.storage.from(receiptBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
        );
    return path;
  }

  Future<Map<String, dynamic>> create({
    required String currency,
    required num amount,
    required String receiptRef,
    String? receiptPath,
    String? bankAccountId,
  }) async {
    final res = await _db.rpc('wallet_deposit_create', params: {
      'p_currency': currency,
      'p_amount': amount,
      'p_receipt_ref': receiptRef,
      'p_receipt_url': receiptPath,
      'p_bank_account_id': bankAccountId,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Own deposits for a customer; every deposit for the master owner.
  Future<List<Map<String, dynamic>>> list({String? status, int limit = 100}) async {
    final res = await _db.rpc('wallet_deposits_list', params: {
      'p_status': status,
      'p_limit': limit,
    });
    return (res as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> decide({
    required String depositId,
    required bool approve,
    String? note,
  }) async {
    final res = await _db.rpc('wallet_deposit_decide', params: {
      'p_deposit_id': depositId,
      'p_approve': approve,
      'p_note': note,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  /// Short-lived signed URL so the owner can view a private receipt image.
  Future<String?> receiptUrl(String path) async {
    if (path.isEmpty) return null;
    try {
      return await _db.storage.from(receiptBucket).createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }
}
