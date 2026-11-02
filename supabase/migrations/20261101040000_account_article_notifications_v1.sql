-- Official Account article notifications (إشعارات مقالات الحسابات الرسمية) —
-- when an account publishes an article, every follower gets an in-app (and,
-- via the existing push pipeline, device) notification. In the spirit of
-- WeChat 公众号 subscription messages.
--
-- Additive only: one nullable column, one RPC and one notify function. The
-- public.notifications row is inserted by a SECURITY DEFINER function so it
-- works regardless of the caller's RLS on the followers table, and it reuses
-- the private.notify_user helper so the push fan-out trigger fires unchanged.

-- Client-supplied deep-link context stored on the article so a notification's
-- data payload can carry the account name/avatar without an extra round-trip.
alter table public.account_articles
  add column if not exists data jsonb not null default '{}'::jsonb;

-- Publishes an article and notifies the account's followers. The author must
-- own the account; the article body is read back from the inserted row.
create or replace function public.publish_account_article(
  p_account_id uuid,
  p_title text,
  p_body text,
  p_cover_url text default null,
  p_published boolean default true
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_article_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication_required';
  end if;
  if not exists (select 1 from public.official_accounts a where a.id = p_account_id and a.owner_id = v_uid) then
    raise exception 'not_account_owner';
  end if;
  if p_title is null or length(btrim(p_title)) = 0 then
    raise exception 'invalid_title';
  end if;

  insert into public.account_articles (account_id, author_id, title, cover_url, body, published, data)
  values (p_account_id, v_uid, btrim(p_title), p_cover_url, coalesce(p_body, ''), coalesce(p_published, true), '{}'::jsonb)
  returning id into v_article_id;

  if coalesce(p_published, true) then
    perform private.notify_account_article(v_article_id);
  end if;

  return v_article_id;
end $$;

-- Inserts one notification per follower (never the author) for a published
-- article. SECURITY DEFINER so followers can be read despite RLS; re-running
-- for the same article is a no-op thanks to the unique dedupe below.
create or replace function private.notify_account_article(p_article_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_article record;
  v_avatar text;
  v_excerpt text;
begin
  select ar.id, ar.account_id, ar.author_id, ar.title, ar.cover_url, ar.body, ar.published,
         a.name as account_name, a.avatar_url as account_avatar
    into v_article
  from public.account_articles ar
  join public.official_accounts a on a.id = ar.account_id
  where ar.id = p_article_id;

  if v_article is null or not v_article.published then
    return;
  end if;

  v_avatar := coalesce(v_article.cover_url, v_article.account_avatar);
  v_excerpt := left(btrim(coalesce(v_article.body, '')), 120);

  insert into public.notifications (user_id, type, title, body, data)
  select f.user_id::text,
         'account_article',
         v_article.account_name,
         coalesce(nullif(v_excerpt, ''), v_article.title),
         jsonb_build_object(
           'account_id', v_article.account_id,
           'article_id', v_article.id,
           'article_title', v_article.title,
           'account_name', v_article.account_name,
           'avatar_url', v_avatar
         )
  from public.account_followers f
  where f.account_id = v_article.account_id
    and f.user_id is distinct from v_article.author_id
    and not exists (
      select 1 from public.notifications n
      where n.user_id = f.user_id::text
        and n.type = 'account_article'
        and n.data->>'article_id' = v_article.id::text
    );
end $$;

revoke all on function public.publish_account_article(uuid, text, text, text, boolean) from public, anon;
revoke all on function private.notify_account_article(uuid) from public, anon, authenticated;
grant execute on function public.publish_account_article(uuid, text, text, text, boolean) to authenticated, service_role;

-- Backfill: articles published before this migration (and any that bypassed the
-- RPC) still notify their followers exactly once.
select private.notify_account_article(ar.id)
from public.account_articles ar
where ar.published;
