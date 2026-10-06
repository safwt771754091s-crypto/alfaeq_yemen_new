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

    test('password reset uses the built-in mailer first, Resend as fallback', () {
      final auth = File('lib/services/auth_service.dart').readAsStringSync();
      final resetStart = auth.indexOf('sendPasswordReset');
      final resetBody = auth.substring(resetStart, auth.indexOf('Future<AuthResponse> register'));
      expect(resetBody, contains('auth.resetPasswordForEmail'));
      expect(resetBody, contains("'request-password-reset'"));
      expect(
        resetBody.indexOf('auth.resetPasswordForEmail') < resetBody.indexOf("'request-password-reset'"),
        isTrue,
        reason: 'built-in mailer must be attempted before the edge-function fallback',
      );
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
      final login = File('lib/screens/login_page.dart').readAsStringSync();
      expect(login, contains("error.contains('Unable to connect')"));
      expect(login, contains("error.contains('ClientException')"));
    });

    test('admin overview derives presence without the missing users.is_online column', () {
      final admin = File('lib/screens/admin_dashboard.dart').readAsStringSync();
      expect(
        admin,
        isNot(contains("from('users').select('uid').eq('is_online'")),
        reason: 'public.users has no is_online column; the query used to 400 and blank the whole overview',
      );
      expect(admin, contains("from('login_events').select('uid,login_at')"));
      expect(admin, contains('hours: 24'));
    });

    test('catalog importer never probes the optional platform-api function on startup', () {
      final importer = File('lib/services/super_alfaeq_catalog_importer.dart').readAsStringSync();
      // The products table is authoritative; the edge function is only a
      // fallback when the table is empty, so a missing deployment cannot spam
      // the console with CORS errors during login.
      final readyBody = importer.substring(importer.indexOf('Future<bool> isReady'), importer.indexOf('Future<int> importIfNeeded'));
      expect(readyBody, contains("from('products')"));
      expect(readyBody, isNot(contains("'platform-api'")), reason: 'readiness must not hit the edge function first');
      expect(importer, contains('_remoteReady'));
    });

    test('wallet recharge vouchers are issued and redeemed through staff-gated RPCs', () {
      final migration = File('supabase/migrations/20261005180000_wallet_topup_vouchers_v1.sql').readAsStringSync();
      expect(migration, contains('create or replace function public.issue_wallet_vouchers'));
      expect(migration, contains('create or replace function public.redeem_wallet_voucher'));
      expect(migration, contains('private.is_platform_staff()'));
      expect(migration, contains('grant execute on function public.issue_wallet_vouchers'));
      final page = File('lib/screens/wallet_vouchers_page.dart').readAsStringSync();
      expect(page, contains("rpc('issue_wallet_vouchers'"));
      expect(page, contains("rpc('list_wallet_vouchers'"));
      final qr = File('lib/screens/wallet_qr_page.dart').readAsStringSync();
      expect(qr, contains("rpc('redeem_wallet_voucher'"));
    });

    test('edge functions invoked from the web client answer CORS preflight', () {
      // Every function the Flutter web bundle calls must handle OPTIONS,
      // otherwise the browser blocks the request before it reaches the handler.
      const browserInvoked = [
        'ai-gateway',
        'automation-event-gateway',
        'create-merchant-invite',
        'developer-control',
        'request-password-reset',
      ];
      for (final name in browserInvoked) {
        final source = File('supabase/functions/$name/index.ts').readAsStringSync();
        expect(source, contains('Access-Control-Allow-Origin'), reason: '$name must send CORS headers');
        expect(source, contains('OPTIONS'), reason: '$name must answer the preflight');
      }
    });

    test('realtime publication covers every table the app streams', () {
      // A `.stream()` call on a table missing from supabase_realtime never
      // delivers rows (the admin login log showed "تعذر قراءة سجل الدخول").
      final migration = File('supabase/migrations/20261005210000_realtime_publication_parity_v1.sql').readAsStringSync();
      for (final table in ['login_events', 'products', 'stores']) {
        expect(migration, contains(table), reason: '$table must be added to the publication');
      }
      expect(migration, contains('supabase_realtime'));
      final dashboard = File('lib/screens/admin_dashboard.dart').readAsStringSync();
      expect(dashboard, contains("from('login_events').stream("));
    });

    test('merchant invites carry a store section so approved stores are visible', () {
      // Stores created from an invite had section_id NULL, so
      // CatalogService.approvedStores(sectionId) never listed them.
      final migration = File('supabase/migrations/20261005220000_merchant_store_sections_v1.sql').readAsStringSync();
      expect(migration, contains('add column if not exists section_id'));
      expect(migration, contains("v_section := 'markets'"));
      final inviteFn = File('supabase/functions/create-merchant-invite/index.ts').readAsStringSync();
      expect(inviteFn, contains('section_id: section || "markets"'));
      final page = File('lib/screens/merchant_invites_page.dart').readAsStringSync();
      expect(page, contains("'section': _section"));
    });

    test('customer stores tab lists every approved store, not only sections', () {
      final catalog = File('lib/services/catalog_service.dart').readAsStringSync();
      expect(catalog, contains('allApprovedStores'));
      expect(catalog, contains("inFilter('status', ['approved', 'active'])"));
      final home = File('lib/screens/world_home_page.dart').readAsStringSync();
      expect(home, contains('CatalogService().allApprovedStores('));
      expect(home, contains('كل المتاجر المعتمدة'));
    });

    test('online payment layer never lets a client mark an order paid', () {
      final migration = File('supabase/migrations/20261005230000_payment_gateway_v1.sql').readAsStringSync();
      // money-moving RPCs are service-role only
      expect(migration, contains('revoke all on function public.mark_order_paid'));
      expect(migration, contains('from public, anon, authenticated'));
      expect(migration, contains('revoke all on function public.attach_payment_provider'));
      expect(migration, contains('create or replace function public.create_pending_order'));
      // the client-facing pending-order RPC is granted to authenticated only
      expect(migration, contains('grant execute on function public.create_pending_order'));
    });

    test('payment-gateway edge function handles CORS and verifies the Stripe webhook', () {
      final fn = File('supabase/functions/payment-gateway/index.ts').readAsStringSync();
      expect(fn, contains('if (req.method === "OPTIONS") return new Response("ok"'));
      expect(fn, contains('verifyStripeSignature'));
      expect(fn, contains('mark_order_paid'));
      final config = File('supabase/config.toml').readAsStringSync();
      expect(config, contains('[functions.payment-gateway]'));
    });

    test('checkout exposes configured online providers', () {
      final order = File('lib/services/order_service.dart').readAsStringSync();
      expect(order, contains('createPendingOrder'));
      expect(order, contains('paymentProviders'));
      final cart = File('lib/screens/cart_page.dart').readAsStringSync();
      expect(cart, contains('online_'));
      expect(cart, contains('_paymentProviders'));
    });

    test('chat realtime notifies members and tracks unread', () {
      final migration = File('supabase/migrations/20261005240000_chat_realtime_unread_v1.sql').readAsStringSync();
      expect(migration, contains('create trigger chat_message_notify'));
      expect(migration, contains("perform private.notify_user("));
      expect(migration, contains('create or replace function public.mark_thread_read'));
      expect(migration, contains('create or replace function public.my_thread_unread_counts'));
      expect(migration, contains("grant execute on function public.mark_thread_read(uuid) to authenticated"));
      final page = File('lib/screens/conversations_page.dart').readAsStringSync();
      expect(page, contains("rpc('my_thread_unread_counts')"));
      expect(page, contains("rpc('mark_thread_read'"));
    });

    test('push notification infrastructure is provider-ready', () {
      final migration = File('supabase/migrations/20261005250000_push_notifications_v1.sql').readAsStringSync();
      expect(migration, contains('create table if not exists public.device_tokens'));
      expect(migration, contains('create or replace function public.register_device_token'));
      expect(migration, contains('create trigger push_on_notification'));
      expect(migration, contains('net.http_post'));
      expect(File('supabase/functions/push-dispatch/index.ts').existsSync(), isTrue);
      final config = File('supabase/config.toml').readAsStringSync();
      expect(config, contains('[functions.push-dispatch]'));
      final service = File('lib/services/push_service.dart').readAsStringSync();
      expect(service, contains('register_device_token'));
    });

    test('local transfer payment flow is wired', () {
      final migration = File('supabase/migrations/20261005260000_local_transfer_payment_v1.sql').readAsStringSync();
      expect(migration, contains('create or replace function public.submit_local_payment'));
      expect(migration, contains('create or replace function public.approve_local_payment'));
      expect(migration, contains("grant execute on function public.submit_local_payment(text, text, text, text) to authenticated"));
      expect(migration, contains('private.is_platform_staff()'));
      final gateway = File('supabase/functions/payment-gateway/index.ts').readAsStringSync();
      expect(gateway, contains('local_transfer'));
      final cart = File('lib/screens/cart_page.dart').readAsStringSync();
      expect(cart, contains('_submitLocalTransfer'));
      expect(cart, contains("'local_transfer'"));
      final service = File('lib/services/order_service.dart').readAsStringSync();
      expect(service, contains('submitLocalPayment'));
      expect(service, contains('approveLocalPayment'));
    });

    test('fx rates are correct and staff-editable', () {
      final migration = File('supabase/migrations/20261005270000_fix_fx_rates_sar_v1.sql').readAsStringSync();
      // The USD base rate must stay 1 and SAR must be the riyal peg, not 410.
      expect(migration, contains("'SAR', 3.75"));
      expect(migration, contains("(value->'rates'->>'SAR') = '410'"));
      expect(migration, contains('usd_rate_must_be_one'));
      expect(migration, contains('rates_must_be_positive'));
      final service = File('lib/services/currency_service.dart').readAsStringSync();
      expect(service, contains('Future<void> updateRates'));
      expect(service, contains("rpc('set_fx_rates'"));
      expect(File('lib/screens/fx_rates_page.dart').existsSync(), isTrue);
      final dashboard = File('lib/screens/admin_dashboard.dart').readAsStringSync();
      expect(dashboard, contains('FxRatesPage'));
    });

    test('delivery lifecycle settles driver load and guards transitions', () {
      final migration = File('supabase/migrations/20261005280000_delivery_lifecycle_integrity_v1.sql').readAsStringSync();
      expect(migration, contains('create or replace function private.driver_update_order'));
      expect(migration, contains("active_order_count = greatest(0, active_order_count - 1)"));
      expect(migration, contains('perform public.release_order_inventory(p_order_id)'));
      expect(migration, contains('cannot_cancel_paid_order'));
      expect(migration, contains("'invalid customer transition'"));
      expect(migration, contains('create or replace function private.transition_order_internal'));
    });

    test('customers can cancel unpaid orders from the app', () {
      final service = File('lib/services/order_service.dart').readAsStringSync();
      expect(service, contains('Future<void> cancelMyOrder'));
      expect(service, contains("rpc('transition_order'"));
      final page = File('lib/screens/my_orders_page.dart').readAsStringSync();
      expect(page, contains('canCancel'));
      expect(page, contains('_cancel('));
      expect(page, contains('cannot_cancel_paid_order'));
    });

    test('merchant settlement converts order currency into the wallet currency', () {
      final migration = File('supabase/migrations/20261005290000_settlement_currency_integrity_v1.sql').readAsStringSync();
      expect(migration, contains('create or replace function private.fx_convert'));
      expect(migration, contains('create or replace function private.settle_order_to_merchant'));
      expect(migration, contains('private.fx_convert(v_entry.amount, v_order_currency, v_wallet.currency)'));
      expect(migration, contains("'order_amount', v_entry.amount"));
      expect(migration, contains("'wallet_currency', v_wallet.currency"));
    });
  });
}
