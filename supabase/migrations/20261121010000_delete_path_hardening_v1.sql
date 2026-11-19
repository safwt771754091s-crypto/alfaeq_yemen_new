-- Delete-path hardening (2026-11-21).
--
-- Companion to 20261120010000_security_audit_hardening_v1.sql. Two verified
-- defects in the delete paths, both reproduced against the deployed project.
--
--   D1 CRITICAL  public.message_reactions was created with
--                `revoke all ... from anon` and no DELETE grant to
--                `authenticated`. Every toggle-off therefore fails with
--                42501, so a reaction can be added but never removed.
--                Reproduced live: DELETE /rest/v1/message_reactions ->
--                {"code":"42501","hint":"GRANT SELECT, DELETE ON public.message_reactions"}.
--   D2 HIGH      Deleting a moment or a reel removed only the row. The media
--                objects stay in the public `moments` / `reels` buckets, so a
--                "deleted" photo or video remains readable by anyone with the
--                URL. Reproduced live: an orphaned moments object still
--                returned HTTP 200 from the public object endpoint.
--                Fixed on the client (the delete calls now remove their own
--                storage objects); this migration only adds the policy the
--                storage API needs, which was already present for the upload
--                path and is unchanged in behaviour.
--
-- Additive and idempotent: safe to re-run. No table is dropped, no row is
-- rewritten, and no existing grant is widened beyond the one missing
-- privilege. Evidence is recorded in progress.md.

-- ---------------------------------------------------------------------------
-- D1: the row policy already restricts deletes to the reaction's own author
-- (`user_id = auth.uid()::text`), so granting DELETE exposes nothing new --
-- without the grant the policy can never be evaluated.
-- ---------------------------------------------------------------------------
grant delete on table public.message_reactions to authenticated;

-- ---------------------------------------------------------------------------
-- D2: deleting a media object requires a matching storage policy. Both
-- buckets already had owner-scoped insert/update/delete policies from their
-- original migrations; these re-create them idempotently so the client-side
-- cleanup cannot silently no-op if a policy was ever dropped.
-- ---------------------------------------------------------------------------
drop policy if exists moments_media_delete on storage.objects;
create policy moments_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'moments' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists reels_media_delete on storage.objects;
create policy reels_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'reels' and (storage.foldername(name))[1] = auth.uid()::text);
