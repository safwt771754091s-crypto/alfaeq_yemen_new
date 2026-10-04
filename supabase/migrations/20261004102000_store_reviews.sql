-- Store review reader, mirroring public.product_reviews. The reviews table
-- already supports store-level rows (store_id set, product_id null).

create or replace function public.store_reviews(p_store_id text, p_limit int default 50)
returns jsonb
language sql
security definer
set search_path = ''
as $function$
  select jsonb_build_object(
    'average', coalesce(
      (select round(avg(rating)::numeric, 2) from public.reviews where store_id = p_store_id),
      0),
    'count', (select count(*) from public.reviews where store_id = p_store_id),
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
        where r.store_id = p_store_id
        order by r.created_at desc
        limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) r
      left join auth.users u on u.id::text = r.user_id
    ), '[]'::jsonb)
  );
$function$;

revoke all on function public.store_reviews(text, int) from public;
grant execute on function public.store_reviews(text, int) to anon, authenticated;
