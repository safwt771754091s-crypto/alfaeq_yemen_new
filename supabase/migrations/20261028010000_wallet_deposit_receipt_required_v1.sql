-- إلزام صورة السند في طلبات إيداع المحفظة (إثبات الحوالة).
--
-- سياسة العمل: أي شخص يشحن محفظته يحوّل المبلغ إلى حساب الكريمي الرسمي حسب
-- العملة (يمني/سعودي/دولار) ويرفع صورة السند كإثبات. هذا التغيير يجعل الصورة
-- إلزامية على مستوى قاعدة البيانات لا الواجهة فقط، حتى لا يُقبل طلب بلا إثبات.
--
-- إضافي فقط: لا يُحذف أي شيء. الطلبات القديمة التي بلا صورة تُملأ بقيمة وصفية
-- حتى يبقى القيد الجديد صالحاً، وتبقى قابلة للمراجعة يدوياً.

-- 1) املأ الطلبات القديمة الخالية من صورة بقيمة وصفية (لا تُرفض ولا تُحذف).
update public.wallet_deposits
   set receipt_url = 'legacy:no-receipt-attached'
 where receipt_url is null or btrim(receipt_url) = '';

-- 2) صورة السند إلزامية لكل طلب جديد.
alter table public.wallet_deposits
  alter column receipt_url set not null;

-- 3) امنع حتى القيمة الفارغة/المسافات.
alter table public.wallet_deposits
  drop constraint if exists wallet_deposits_receipt_url_present;
alter table public.wallet_deposits
  add constraint wallet_deposits_receipt_url_present
  check (btrim(receipt_url) <> '');

-- 4) RPC الإنشاء: ارفض الطلب إذا لم تُرفع صورة السند.
create or replace function public.wallet_deposit_create(
  p_currency text,
  p_amount numeric,
  p_receipt_ref text,
  p_receipt_url text default null,
  p_bank_account_id uuid default null
)
returns public.wallet_deposits
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  d public.wallet_deposits%rowtype;
  v_uid text := auth.uid()::text;
  v_cur text := upper(btrim(coalesce(p_currency, '')));
  v_ref text := btrim(coalesce(p_receipt_ref, ''));
  v_url text := btrim(coalesce(p_receipt_url, ''));
begin
  if v_uid is null then raise exception 'authentication_required'; end if;
  if v_cur not in ('YER','SAR','USD') then raise exception 'invalid_currency'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_amount'; end if;
  if v_ref = '' then raise exception 'receipt_required'; end if;
  if v_url = '' then raise exception 'receipt_image_required'; end if;

  insert into public.wallet_deposits (uid, currency, amount, bank_account_id, receipt_ref, receipt_url, status)
  values (v_uid, v_cur, p_amount, p_bank_account_id, v_ref, v_url, 'pending')
  returning * into d;

  return d;
end $$;

revoke all on function public.wallet_deposit_create(text, numeric, text, text, uuid) from public, anon;
grant execute on function public.wallet_deposit_create(text, numeric, text, text, uuid) to authenticated;

-- 5) الاعتماد: يدعم الشحن بأي عملة (يمني/سعودي/دولار).
--
-- المحفظة صف واحد لكل مستخدم بعملة واحدة. المستخدم قد يشحن بعملة مختلفة عن
-- عملة محفظته (مثلاً محفظته يمني ويودع دولار). سابقاً كان ذلك يفشل بخطأ
-- wallet_currency_mismatch فيُرفض الإيداع. الآن نحوّل المبلغ إلى عملة المحفظة
-- بسعر الصرف الرسمي، ونحتفظ بالعملة والمبلغ الأصليين في السجل للمراجعة.
create or replace function private.deposit_credit(
  p_uid text,
  p_amount numeric,
  p_currency text,
  p_deposit_id uuid
)
returns numeric
language plpgsql security definer
set search_path = pg_catalog, public, auth, private
as $$
declare
  w public.wallets%rowtype;
  b numeric;
  v_key text := 'deposit:' || p_deposit_id::text;
  v_cur text := upper(btrim(coalesce(p_currency, 'YER')));
  v_credit numeric;
begin
  if exists (select 1 from public.wallet_ledger where idempotency_key = v_key) then
    select available_balance into b from public.wallets where uid = p_uid;
    return coalesce(b, 0);
  end if;

  select * into w from public.wallets where uid = p_uid for update;
  if w.uid is null then
    insert into public.wallets (uid, currency, status, available_balance, metadata, version, owner_uid, account_type)
    values (p_uid, v_cur, 'active', 0, '{}'::jsonb, 0, p_uid, 'customer')
    returning * into w;
  end if;

  if upper(w.currency) <> v_cur then
    if w.available_balance = 0 then
      -- محفظة فارغة: اعتمد عملة الإيداع نفسها.
      update public.wallets set currency = v_cur, version = version + 1, updated_at = now() where uid = p_uid;
      w.currency := v_cur;
      v_credit := p_amount;
    else
      -- محفظة ممولة بعملة أخرى: حوّل الإيداع إلى عملة المحفظة.
      v_credit := private.fx_convert(p_amount, v_cur, w.currency);
    end if;
  else
    v_credit := p_amount;
  end if;

  b := w.available_balance + v_credit;
  update public.wallets set available_balance = b, version = version + 1, updated_at = now() where uid = p_uid;
  insert into public.wallet_ledger
    (wallet_uid, user_id, entry_type, amount, balance_after, reference_type, reference_id, idempotency_key, metadata)
  values
    (p_uid, p_uid, 'credit', v_credit, b, 'deposit', p_deposit_id::text, v_key,
     jsonb_build_object('currency', upper(w.currency), 'source', 'bank_deposit',
                        'deposit_currency', v_cur, 'deposit_amount', p_amount));
  return b;
end $$;
revoke all on function private.deposit_credit(text, numeric, text, uuid) from public, anon, authenticated;
grant execute on function private.deposit_credit(text, numeric, text, uuid) to service_role;
