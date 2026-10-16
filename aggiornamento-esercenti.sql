-- Saveat: esercenti solo pubblicazione; privati pubblicano e ritirano.
begin;
set local lock_timeout='5s';
-- Regole centrali: nessun B2B attivo. Non cambiano tipi account o storico.
create or replace function public.saveat_can_discover() returns boolean language sql stable security definer set search_path='' as $$
 select not exists(select 1 from public.saveat_profiles where id=auth.uid() and account_type='business');
$$;
create or replace function public.saveat_can_collect() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.saveat_profiles where id=auth.uid() and account_type='private');
$$;
revoke all on function public.saveat_can_discover(),public.saveat_can_collect() from public;
grant execute on function public.saveat_can_discover() to anon,authenticated;
grant execute on function public.saveat_can_collect() to authenticated;
-- Restrizione aggiuntiva: mantiene tutte le condizioni RLS già esistenti.
do $policy$ begin if not exists(select 1 from pg_policies where schemaname='public' and tablename='saveat_listings' and policyname='saveat_business_own_only') then create policy saveat_business_own_only on public.saveat_listings as restrictive for select to authenticated using(owner_id=(select auth.uid()) or (select public.saveat_can_discover()));end if;end $policy$;
-- Aggiorna esclusivamente le funzioni effettive, senza riscrivere SQL completo.
do $patch$ declare rec record;definition text;original text;guard text:=E'\n if not public.saveat_can_collect() then raise exception ''Gli account attività possono solo pubblicare eccedenze e gestire le consegne'';end if;\n';begin
 for rec in select oid,proname from pg_proc where pronamespace='public'::regnamespace and proname in ('saveat_reserve','saveat_reservation_edit_context','saveat_change_reservation') loop
 definition:=pg_get_functiondef(rec.oid);original:=definition;
 if position('public.saveat_can_collect()' in definition)=0 then
 if position(E'begin\n' in definition)>0 then definition:=replace(definition,E'begin\n',E'begin\n'||guard);elsif position(E'begin\r\n' in definition)>0 then definition:=replace(definition,E'begin\r\n',E'begin\r\n'||guard);else raise exception 'Corpo inatteso per %',rec.proname;end if;
 execute definition;
 end if;
 end loop;
 if (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('saveat_reserve','saveat_reservation_edit_context','saveat_change_reservation'))<>3 then raise exception 'Funzioni prenotazione mancanti';end if;
 for rec in select oid,proname from pg_proc where pronamespace='public'::regnamespace and proname in ('saveat_search','saveat_search_nearby') loop
 definition:=pg_get_functiondef(rec.oid);
 if position('public.saveat_can_discover()' in definition)=0 then
 original:=definition;definition:=replace(definition,'where l.status=''active''','where public.saveat_can_discover() and l.status=''active''');
 if definition=original then raise exception 'Ricerca inattesa per %',rec.proname;end if;execute definition;
 end if;
 end loop;
 if (select count(*) from pg_proc where pronamespace='public'::regnamespace and proname in ('saveat_search','saveat_search_nearby'))<>2 then raise exception 'Funzioni ricerca mancanti';end if;
end $patch$;
-- Logo e categoria altrui seguono la stessa regola, senza esporre il profilo completo.
create or replace function public.saveat_public_avatars(p_owner_ids uuid[]) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'avatar_path',p.avatar_path,'business_activity',case when p.account_type='business' then p.business_activity else null end)),'[]'::jsonb) from public.saveat_profiles p where p.id=any(p_owner_ids[1:100]) and (p.id=auth.uid() or public.saveat_can_discover()) and (p.id=auth.uid() or exists(select 1 from public.saveat_listings l where l.owner_id=p.id and ((l.status='active' and l.pickup_end>now()) or public.saveat_has_reservation(l.id))));
$$;
notify pgrst,'reload schema';
commit;
