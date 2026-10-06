import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Alfaeq Yemen commercial security architecture', () {
    test('merchant portal remains role-gated', () {
      final source = File('lib/screens/merchant_portal_page.dart').readAsStringSync();
      expect(source, contains("import '../services/auth_service.dart';"));
      expect(source, contains("role == 'merchant'"));
      expect(source, contains("role == 'admin'"));
      expect(source, contains("role == 'owner'"));
      expect(source, contains('const MerchantCenterPage()'));
      expect(source, contains('const MerchantOrdersPage()'));
    });

    test('merchant orders use Supabase ownership and server-side transitions', () {
      final orders = File('lib/screens/merchant_orders_page.dart').readAsStringSync();
      final migration = File('supabase/migrations/20260923160000_stage4_merchant_order_transitions.sql').readAsStringSync();
      expect(orders, contains("from('stores').select('id').eq('owner_id',uid)"));
      expect(orders, contains("rpc('transition_order'"));
      expect(migration, contains('security definer'));
      expect(migration, contains('s.owner_id = uid'));
      expect(migration, contains("raise exception 'not authorized'"));
      expect(migration, contains("raise exception 'invalid merchant order transition'"));
    });

    test('order creation stays on the Supabase transactional RPC', () {
      final orders = File('lib/services/order_service.dart').readAsStringSync();
      final migration = File('supabase/migrations/20260922190300_production_rpc_hardening.sql').readAsStringSync();
      expect(orders, contains("rpc('create_order'"));
      expect(migration, contains('create or replace function public.create_order'));
    });

    test('commercial notifications stay on Supabase', () {
      final page = File('lib/screens/notifications_page.dart').readAsStringSync();
      expect(page, contains("from('notifications')"));
      expect(page, contains("read_at"));
    });

    test('wallet money movement stays server-side and currency-aware', () {
      final qr = File('lib/screens/wallet_qr_page.dart').readAsStringSync();
      // Transfers run in the RPC; the client never edits balances directly.
      expect(qr, contains("rpc('wallet_transfer'"));
      expect(qr, isNot(contains("from('wallets').update")));
      // The transfer currency comes from the user's real wallet, not a literal.
      expect(qr, contains('walletInfo()'));
      expect(qr, isNot(contains("'p_currency': 'YER'")));
    });

    test('wallet checkout is currency-aware and converts USD totals', () {
      final cart = File('lib/screens/cart_page.dart').readAsStringSync();
      // Same-currency debit uses the raw total; otherwise the USD total is
      // converted into the wallet currency before the balance check.
      expect(cart, contains('_walletCurrency == _currency'));
      expect(cart, contains('convert(_total.toDouble(), _walletCurrency)'));
      expect(cart, contains('_walletCovers'));
    });

    test('wallet currency integrity migration guards relabelling and duplicates', () {
      final migration = File('supabase/migrations/20261005120000_wallet_currency_integrity_v1.sql').readAsStringSync();
      expect(migration, contains('create or replace function private.wallet_credit_internal'));
      expect(migration, contains('create or replace function private.wallet_debit_internal'));
      expect(migration, contains('wallet_currency_mismatch'));
      expect(migration, contains('on conflict (uid) do nothing'));
    });


    test('commercial support chat uses server-side RPCs', () {
      final page = File('lib/screens/support_chat_page.dart').readAsStringSync();
      expect(page, contains("rpc('create_support_thread'"));
      expect(page, contains("rpc('send_chat_message'"));
      expect(page, contains("from('chat_messages')"));
    });

    test('commercial app exposes Alfaeq Intelligence only as the user execution assistant', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      final ai = File('lib/screens/ai_assistant_page.dart').readAsStringSync();
      expect(home, contains("import 'ai_assistant_page.dart';"));
      expect(home, contains('AiAssistantPage()'));
      expect(ai, contains('AlfaeqAiService'));
      expect(ai, contains('تأكيد التنفيذ'));
    });

    test('product search matches name, description and barcode', () {
      final search = File('lib/services/unified_search_service.dart').readAsStringSync();
      expect(search, contains("metadata->>barcode.ilike"));
      final tools = File('lib/ai/ai_tools.dart').readAsStringSync();
      expect(tools, contains("metadata->>barcode.ilike"));
      expect(tools, contains(".limit(_max)"));
    });

    test('section page search box filters products', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(home, contains('class _WorldSectionPageState'));
      expect(home, contains('onChanged: (v) => setState(() => _query = v)'));
      expect(home, contains("metadata") , reason: 'section filter reads product metadata for barcode');
      expect(home, contains('_productsFuture'));
    });

    test('home offers read published promotions linked to active products', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(home, contains('activePromotions'));
      expect(home, contains('_promotionDeals'));
      expect(home, contains("from('products')"));
    });

    test('store and section listings filter server-side instead of truncating', () {
      final store = File('lib/screens/store_detail_page.dart').readAsStringSync();
      expect(store, contains('activeProducts(storeId: widget.store.id'));
      expect(store, isNot(contains('activeProducts(limit: 5000)')));
      final program = File('lib/screens/mini_programs_page.dart').readAsStringSync();
      expect(program, contains('activeProducts(sectionId: widget.section.id'));
      expect(program, isNot(contains('activeProducts(limit: 500)')));
    });

    test('public update CTA opens its real link', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(home, contains("import 'package:url_launcher/url_launcher.dart';"));
      expect(home, contains('launchUrl(uri'));
    });

    test('camera barcode scanner is wired into search', () {
      final scanner = File('lib/screens/barcode_scanner_page.dart').readAsStringSync();
      expect(scanner, contains('MobileScanner('));
      expect(scanner, contains('BarcodeFormat.ean13'));
      final search = File('lib/screens/search_page.dart').readAsStringSync();
      expect(search, contains('BarcodeScannerPage()'));
      expect(search, contains('_scanBarcode'));
    });

    test('home storefront exposes a featured products grid', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(home, contains('_FeaturedProductsSection('));
      expect(home, contains('activeProducts(limit: 200)'));
      expect(home, contains('منتجات مختارة لك'));
    });

    test('account center exposes WeChat-style profile controls', () {
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(home, contains("import 'account_center_page.dart';"));
      expect(home, contains('AccountCenterPage()'));

      final page = File('lib/screens/account_center_page.dart').readAsStringSync();
      expect(page, contains('uploadAvatar'));
      expect(page, contains('changePassword'));
      expect(page, contains('changeEmail'));
      expect(page, contains("FileType.image"));
      expect(page, contains('تغيير الصورة'));

      final service = File('lib/services/profile_service.dart').readAsStringSync();
      expect(service, contains("storage.from(_avatarBucket).uploadBinary"));
      expect(service, contains("from('users').upsert"));
      expect(service, contains('signInWithPassword'), reason: 'password change re-authenticates');
    });

    test('password reset is delivered through the Resend edge function', () {
      final auth = File('lib/services/auth_service.dart').readAsStringSync();
      expect(auth, contains("functions.invoke(\n        'request-password-reset'"));
      final fn = File('supabase/functions/request-password-reset/index.ts').readAsStringSync();
      expect(fn, contains('admin.auth.admin.generateLink'));
      expect(fn, contains('type: "recovery"'));
      expect(fn, contains('api.resend.com/emails'));
      expect(fn, isNot(contains('"detail"')), reason: 'no provider detail leaks to callers');
    });

    test('startup retries the backend connection and offers a reconnect action', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('for (var attempt = 0; attempt < 3; attempt++)'));
      expect(main, contains('إعادة المحاولة'));
      expect(main, contains('تعذر الاتصال بخادم الفائق يمن'));
    });
  });
}
