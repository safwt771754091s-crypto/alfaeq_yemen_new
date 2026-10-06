-- Fix the SAR exchange rate.
--
-- The original multi-currency migration seeded SAR as 410, which is the
-- YER-per-SAR figure. Since the base currency is USD, the USD->SAR rate must be
-- the riyal peg (~3.75). The bad value made every SAR price ~109x too high and
-- would have produced wrong charges for Saudi customers. YER is unchanged.

update public.settings
set value = jsonb_build_object(
      'base_currency', 'USD',
      'rates', jsonb_build_object('USD', 1, 'SAR', 3.75, 'YER', 1537.5),
      'updated_at', now()
    ),
    updated_at = now()
where id = 'fx_rates'
  and (value->'rates'->>'SAR') = '410';

-- Guard the staff editor against invalid input: every rate must be a positive
-- number and the USD base must be exactly 1 so conversions stay consistent.
create or replace function public.set_fx_rates(p_rates jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_value jsonb;
  v_rates jsonb;
  v_key text;
  v_amount numeric;
begin
  if not (select private.is_platform_staff()) then
    raise exception 'not authorized';
  end if;
  v_rates := p_rates->'rates';
  if jsonb_typeof(coalesce(v_rates,'null'::jsonb)) <> 'object' then
    raise exception 'invalid_rates';
  end if;
  if jsonb_typeof(coalesce(v_rates->'USD','null'::jsonb)) <> 'number'
     or (v_rates->>'USD')::numeric <> 1 then
    raise exception 'usd_rate_must_be_one';
  end if;
  for v_key, v_amount in select key, value::text::numeric from jsonb_each(v_rates) loop
    if upper(v_key) !~ '^[A-Z]{3}$' then raise exception 'invalid_currency_code'; end if;
    if v_amount <= 0 then raise exception 'rates_must_be_positive'; end if;
  end loop;
  v_value := jsonb_build_object('base_currency','USD','rates',v_rates,'updated_at',now());
  insert into public.settings(id, value, updated_by, updated_at)
  values ('fx_rates', v_value, auth.uid()::text, now())
  on conflict (id) do update set value = excluded.value, updated_by = excluded.updated_by, updated_at = now();
  return v_value;
end;
$$;

revoke all on function public.set_fx_rates(jsonb) from public, anon;
grant execute on function public.set_fx_rates(jsonb) to authenticated, service_role;
