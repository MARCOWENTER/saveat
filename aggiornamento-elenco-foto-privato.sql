-- Restrizione elenco foto autorizzata e applicata il 16 ottobre 2026.
-- Nessuna foto eliminata; bucket pubblico e URL immagini invariati.
begin;
drop policy if exists saveat_avatar_public_read on storage.objects;
do $$begin if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saveat_avatar_owner_read') then
create policy saveat_avatar_owner_read on storage.objects for select to authenticated using(bucket_id='saveat-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
end if;end;$$;
commit;
