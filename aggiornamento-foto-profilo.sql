-- Saveat: foto/logo profilo facoltativi, migrazione incrementale.
begin;
set local lock_timeout='5s';
alter table public.saveat_profiles add column if not exists avatar_path text check(length(avatar_path)<=180);
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('saveat-avatars','saveat-avatars',true,2097152,array['image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
do $bucket$ begin if not exists(select 1 from storage.buckets where id='saveat-avatars' and public=true and file_size_limit=2097152 and allowed_mime_types=array['image/jpeg','image/png','image/webp']) then raise exception 'Configurazione bucket inattesa';end if;end $bucket$;
-- Non modifica policy o bucket degli alimenti.
do $policy$ begin if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saveat_avatar_public_read') then create policy saveat_avatar_public_read on storage.objects for select to anon,authenticated using(bucket_id='saveat-avatars');end if;end $policy$;
do $policy$ begin if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saveat_avatar_owner_insert') then create policy saveat_avatar_owner_insert on storage.objects for insert to authenticated with check(bucket_id='saveat-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$');end if;end $policy$;
do $policy$ begin if not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects' and policyname='saveat_avatar_owner_delete') then create policy saveat_avatar_owner_delete on storage.objects for delete to authenticated using(bucket_id='saveat-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);end if;end $policy$;
create or replace function public.saveat_set_avatar(p_path text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Accedi per modificare la foto';end if;
 if p_path is not null and (split_part(p_path,'/',1)<>auth.uid()::text or p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|png|webp)$' or not exists(select 1 from storage.objects where bucket_id='saveat-avatars' and name=p_path and metadata->>'mimetype' in ('image/jpeg','image/png','image/webp') and (metadata->>'size')::bigint<=2097152)) then raise exception 'Foto non accessibile o non valida';end if;
 update public.saveat_profiles set avatar_path=p_path where id=auth.uid();
 if not found then raise exception 'Completa il profilo';end if;
end;$$;
revoke all on function public.saveat_set_avatar(text) from public,anon;
grant execute on function public.saveat_set_avatar(text) to authenticated;
-- Proiezione pubblica minima, senza esporre dati privati del profilo.
create or replace function public.saveat_public_avatars(p_owner_ids uuid[]) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'avatar_path',p.avatar_path)),'[]'::jsonb) from public.saveat_profiles p where p.id=any(p_owner_ids[1:100]) and p.avatar_path is not null and (p.id=auth.uid() or exists(select 1 from public.saveat_listings l where l.owner_id=p.id and ((l.status='active' and l.pickup_end>now()) or public.saveat_has_reservation(l.id))));
$$;
revoke all on function public.saveat_public_avatars(uuid[]) from public;
grant execute on function public.saveat_public_avatars(uuid[]) to anon,authenticated;
notify pgrst,'reload schema';
commit;
