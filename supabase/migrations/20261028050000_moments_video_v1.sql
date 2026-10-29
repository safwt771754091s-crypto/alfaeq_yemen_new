-- Moments video (فيديو اللحظات): publish a short video into the WeChat-style
-- Moments feed and play it inline. Additive only: one nullable column, a relaxed
-- body-or-media check, an updated feed RPC and a wider media bucket. No existing
-- object is dropped and no existing row is rewritten.

-- ---------------------------------------------------------------------------
-- Column: keep photos in media_urls and add videos in a parallel array so the
-- existing photo UI keeps working unchanged.
-- ---------------------------------------------------------------------------
alter table public.moments add column if not exists video_urls text[] not null default '{}';

-- The old check required text or a photo; a video-only moment is now valid too.
alter table public.moments drop constraint if exists moments_body_or_media;
alter table public.moments add constraint moments_body_or_media check (
  length(btrim(content)) > 0
  or array_length(media_urls, 1) is not null
  or array_length(video_urls, 1) is not null
);

-- ---------------------------------------------------------------------------
-- Feed RPC: expose video_urls. Recreated because a function's OUT columns
-- cannot be altered in place.
-- ---------------------------------------------------------------------------
drop function if exists public.moments_feed(integer);
create or replace function public.moments_feed(p_limit integer default 40)
returns table (
  id uuid, author_id uuid, author_name text, author_avatar text,
  content text, media_urls text[], video_urls text[], visibility text,
  like_count integer, comment_count integer, created_at timestamptz, liked_by_me boolean
)
language sql stable security definer set search_path = public, pg_temp as $$
  select m.id, m.author_id,
    coalesce(nullif(u.raw_user_meta_data->>'full_name', ''), nullif(u.raw_user_meta_data->>'name', ''), 'مستخدم الفائق') as author_name,
    nullif(u.raw_user_meta_data->>'avatar_url', '') as author_avatar,
    m.content, m.media_urls, m.video_urls, m.visibility, m.like_count, m.comment_count, m.created_at,
    exists (select 1 from public.moment_likes l where l.moment_id = m.id and l.user_id = auth.uid()) as liked_by_me
  from public.moments m
  left join auth.users u on u.id = m.author_id
  where m.visibility = 'public' or m.author_id = auth.uid() or private.is_platform_staff()
  order by m.created_at desc
  limit greatest(1, least(coalesce(p_limit, 40), 100));
$$;

revoke all on function public.moments_feed(integer) from public, anon;
grant execute on function public.moments_feed(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Storage: the 'moments' bucket now accepts short videos as well. Video files
-- are larger than photos, so the per-file cap is raised to 50MB.
-- ---------------------------------------------------------------------------
update storage.buckets
set file_size_limit = 52428800,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp', 'image/gif',
      'video/mp4', 'video/webm', 'video/quicktime'
    ]
where id = 'moments';
