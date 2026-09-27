import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class WalletService {
  const WalletService();

  Future<Map<String, dynamic>> ensureMyWallet({
    String currency = 'YER',
    String accountType = 'customer',
  }) async {
    final response = await SupabaseService.client.rpc(
      'ensure_my_wallet',
      params: {
        'p_currency': currency,
        'p_account_type': accountType,
      },
    );
    if (response is Map) return Map<String, dynamic>.from(response);
    throw const PostgrestException(message: 'تعذر إنشاء المحفظة.');
  }
}
