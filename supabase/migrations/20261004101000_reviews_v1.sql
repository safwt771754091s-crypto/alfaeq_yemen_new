-- Activate product reviews. The reviews table already existed with RLS but had
-- no constraints, indexes, aggregates, or notifications, so a product page could
-- not show a rating and the feature was effectively dead.
--
-- Additive: defaults/constraints/indexes on the existing table + two reader RPCs
-- (author resolved from auth.users so the users table is never exposed) + an
-- owner notification trigger.

alter table public.reviews
  alter column id set default ('rev_' || replace(gen_random_uuid()::text, '-', ''));

alter table public.reviews
  add constraint reviews_rating_range
  check (rating is null or (rating >= 1 and rating <= 5)) not valid;
alter table public.reviews validate constraint reviews_rating_range;

-- One review per user per target.
create unique index if not exists reviews_one_per_user_product
  on public.reviews(product_id, user_id) where product_id is not null;
create unique index if not exists reviews_one_per_user_store
  on public.reviews(store_id, user_id) where store_id is not null and product_id is null;
create index if not exists reviews_product_idx on public.reviews(product_id);
create index if not exists reviews_store_idx on public.reviews(store_id);

create or replace function private.notify_review_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner text;
  v_name text;
begin
  if new.product_id is not null then
    select coalesce(s.owner_id, p.owner_id), p.name
      into v_owner, v_name
    from public.products p
    left join public.stores s on s.id = p.store_id
    where p.id = new.product_id;
  elsif new.store_id is not null then
    select s.owner_id, s.name into v_owner, v_name
    from public.stores s where s.id = new.store_id;
  end if;

  if v_owner is not null and v_owner <> new.user_id then
    insert into public.notifications(user_id, type, title, body, data)
    values (
      v_owner,
      'review',
      'تقييم جديد',
      'تلقّيت تقييماً جديداً على ' || coalesce(v_name, 'منتجك') || '.',
      jsonb_build_object(
        'product_id', new.product_id,
        'store_id', new.store_id,
        'review_id', new.id,
        'rating', new.rating
      )
    );
  end if;
  return new;
end
$function$;

drop trigger if exists reviews_notify_owner on public.reviews;
create trigger reviews_notify_owner
  after insert on public.reviews
  for each row execute function private.notify_review_created();

-- Per-product rating + latest reviews, with the author resolved from auth.
create or replace function public.product_reviews(p_product_id text, p_limit int default 50)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'average', coalesce(
      (select round(avg(rating)::numeric, 2) from public.reviews where product_id = p_product_id),
      0),
    'count', (select count(*) from public.reviews where product_id = p_product_id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', r.id,
          'rating', r.rating,
          'body', r.body,
          'user_id', r.user_id,
          'author_name', coalesce(
            nullif(u.raw_user_meta_data ->> 'full_name', ''),
            nullif(u.raw_user_meta_data ->> 'name', ''),
            split_part(u.email, '@', 1),
            'مستخدم'),
          'avatar_url', coalesce(u.raw_user_meta_data ->> 'avatar_url', ''),
          'created_at', r.created_at
        ))
      from (
        select r.* from public.reviews r
        where r.product_id = p_product_id
        order by r.created_at desc
        limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) r
      left join auth.users u on u.id::text = r.user_id
    ), '[]'::jsonb)
  );
$function$;

-- Lightweight rating summary for a set of products (for grid badges).
create or replace function public.reviews_summary(p_product_ids text[])
returns table(product_id text, average numeric, review_count bigint)
language sql
security definer
set search_path = ''
as $function$
  select product_id, round(avg(rating)::numeric, 2) as average, count(*) as review_count
  from public.reviews
  where product_id = any(p_product_ids)
  group by product_id;
$function$;

revoke all on function public.product_reviews(text, int) from public;
revoke all on function public.reviews_summary(text[]) from public;
grant execute on function public.product_reviews(text, int) to anon, authenticated;
grant execute on function public.reviews_summary(text[]) to anon, authenticated;
