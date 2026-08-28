-- ============================================================================
-- Migration 0020: RLS for the "evidence" storage bucket
--
-- storage.objects has RLS enabled (0001) but no policies exist for it, so
-- every direct client-side upload/download against the "evidence" bucket
-- currently deny-alls. Files are keyed by path convention
-- {matter_id}/{evidence_id}/{filename} — the same matter-scoping the rest of
-- the schema already uses, via the existing app.has_matter_access() helper.
-- Read requires 'read'; upload requires 'contribute'. No update/delete
-- policy: evidence files are treated as append-only, same spirit as chain
-- of custody — a correction is a new version, not an edit in place.
-- ============================================================================

create policy evidence_files_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'evidence'
    and app.has_matter_access(((storage.foldername(name))[1])::uuid, 'read')
  );

create policy evidence_files_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'evidence'
    and app.has_matter_access(((storage.foldername(name))[1])::uuid, 'contribute')
  );
