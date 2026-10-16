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

create temporary table saveat_role_test(k text primary key,v uuid);grant select,insert,update on saveat_role_test to authenticated;
do $$declare b uuid:=gen_random_uuid();b2 uuid:=gen_random_uuid();p uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();begin
insert into auth.users(id,email,raw_user_meta_data) values(b,'saveat-role-test-'||b||'@example.invalid','{}'),(b2,'saveat-role-test-'||b2||'@example.invalid','{}'),(p,'saveat-role-test-'||p||'@example.invalid','{}'),(p2,'saveat-role-test-'||p2||'@example.invalid','{}');
update public.saveat_profiles set display_name='Prova ruoli',account_type=case when id in(b,b2) then 'business' else 'private' end,business_name=case when id in(b,b2) then 'Esercente prova' else '' end where id in(b,b2,p,p2);
insert into saveat_role_test values('business',b),('business2',b2),('private',p),('private2',p2);end;$$;
set local role authenticated;
do $$declare actor record;lid uuid;uid uuid;bid uuid;pid uuid;otherbid uuid;res uuid;private_res uuid;payload jsonb;ctx jsonb;failed boolean;loc record;begin
for actor in select * from saveat_role_test where k in ('business','business2','private') loop
perform set_config('request.jwt.claim.sub',actor.v::text,true);
lid:=public.saveat_create_listing(jsonb_build_object('title','PROVA RUOLI TRANSITORIA '||actor.k,'municipality_code',(select code from public.saveat_municipalities where latitude is not null and longitude is not null limit 1),'pickup_start',now()-interval '1 hour','pickup_end',now()+interval '2 hours','address','Banco prova','contact','Contatto prova','payment_methods',jsonb_build_array('cash')),jsonb_build_array(jsonb_build_object('name','Mele prova ruoli','unit','pezzi','quantity',10,'price',1,'date_type','none')));
insert into saveat_role_test values(actor.k||'_listing',lid);
end loop;
select v into bid from saveat_role_test where k='business_listing';select v into pid from saveat_role_test where k='private_listing';select v into otherbid from saveat_role_test where k='business2_listing';
select v into uid from saveat_role_test where k='business';perform set_config('request.jwt.claim.sub',uid::text,true);
if public.saveat_can_collect() or public.saveat_can_discover() then raise exception 'FAIL business capabilities';end if;
if not exists(select 1 from public.saveat_listings where id=bid) or exists(select 1 from public.saveat_listings where id in(pid,otherbid)) then raise exception 'FAIL listing RLS';end if;
if not exists(select 1 from public.saveat_items where listing_id=bid) or exists(select 1 from public.saveat_items where listing_id in(pid,otherbid)) then raise exception 'FAIL items RLS';end if;
if public.saveat_search('PROVA RUOLI TRANSITORIA')<>'[]'::jsonb then raise exception 'FAIL business search';end if;
select m.latitude,m.longitude into loc from public.saveat_listings l join public.saveat_municipalities m on m.code=l.municipality_code where l.id=bid;
if public.saveat_search_nearby(loc.latitude,loc.longitude,20,'PROVA RUOLI TRANSITORIA')<>'[]'::jsonb then raise exception 'FAIL business nearby';end if;
failed:=false;begin perform public.saveat_reserve(pid,jsonb_build_array(jsonb_build_object('item_id',gen_random_uuid(),'quantity',1)),gen_random_uuid());exception when others then if sqlerrm='Gli account attività possono solo pubblicare eccedenze e gestire le consegne' then failed:=true;else raise;end if;end;if not failed then raise exception 'FAIL business reserve private';end if;
failed:=false;begin perform public.saveat_reserve(otherbid,jsonb_build_array(jsonb_build_object('item_id',gen_random_uuid(),'quantity',1)),gen_random_uuid());exception when others then if sqlerrm='Gli account attività possono solo pubblicare eccedenze e gestire le consegne' then failed:=true;else raise;end if;end;if not failed then raise exception 'FAIL B2B reserve';end if;
if jsonb_array_length(public.saveat_public_avatars(array[(select v from saveat_role_test where k='business'),(select v from saveat_role_test where k='business2'),(select v from saveat_role_test where k='private')]))<>1 then raise exception 'FAIL business public identities';end if;
select v into uid from saveat_role_test where k='private2';perform set_config('request.jwt.claim.sub',uid::text,true);
if not public.saveat_can_collect() or not public.saveat_can_discover() then raise exception 'FAIL private capabilities';end if;
if (select count(*) from public.saveat_listings where id in(bid,pid,otherbid))<>3 then raise exception 'FAIL private listing discovery';end if;
if jsonb_array_length(public.saveat_search('PROVA RUOLI TRANSITORIA'))<>3 then raise exception 'FAIL private search';end if;
res:=public.saveat_reserve(bid,(select jsonb_agg(jsonb_build_object('item_id',id,'quantity',2)) from public.saveat_items where listing_id=bid),gen_random_uuid());
private_res:=public.saveat_reserve(pid,(select jsonb_agg(jsonb_build_object('item_id',id,'quantity',1)) from public.saveat_items where listing_id=pid),gen_random_uuid());
insert into saveat_role_test values('reservation',res),('private_reservation',private_res);
ctx:=public.saveat_reservation_edit_context(res);select jsonb_agg(jsonb_build_object('snapshot_id',x->>'snapshot_id','quantity',3)) into payload from jsonb_array_elements(ctx->'items') x;perform public.saveat_change_reservation(res,payload,0,gen_random_uuid());
if (select available from public.saveat_items where listing_id=bid)<>7 then raise exception 'FAIL private edit regression';end if;
select v into uid from saveat_role_test where k='business';perform set_config('request.jwt.claim.sub',uid::text,true);
if not exists(select 1 from jsonb_array_elements(public.saveat_my_reservations()) x where x->>'id'=res::text) then raise exception 'FAIL owner deliveries';end if;
if not exists(select 1 from public.saveat_notifications where reservation_id=res and kind='reservation_received') then raise exception 'FAIL owner notification';end if;
perform public.saveat_transition(res,'collected');
if not exists(select 1 from jsonb_array_elements(public.saveat_my_report(current_date,current_date)) x where x->>'reservation_id'=res::text and x->>'role'='owner') then raise exception 'FAIL owner impact report';end if;
select v into uid from saveat_role_test where k='private2';perform set_config('request.jwt.claim.sub',uid::text,true);if not exists(select 1 from jsonb_array_elements(public.saveat_my_reservations()) x where x->>'id'=res::text and x->>'status'='collected') then raise exception 'FAIL completed receipt';end if;
end;$$;
reset role;
-- Simula solo nel test un vecchio ritiro aziendale: conserva ricevuta e annullamento.
update public.saveat_profiles set account_type='business',business_name='Esercente storico prova' where id=(select v from saveat_role_test where k='private2');
set local role authenticated;
do $$declare uid uuid;rid uuid;failed boolean;begin
select v into uid from saveat_role_test where k='private2';perform set_config('request.jwt.claim.sub',uid::text,true);select v into rid from saveat_role_test where k='private_reservation';
if not exists(select 1 from jsonb_array_elements(public.saveat_my_reservations()) x where x->>'id'=rid::text) then raise exception 'FAIL legacy preservation';end if;
failed:=false;begin perform public.saveat_reservation_edit_context(rid);exception when others then if sqlerrm='Gli account attività possono solo pubblicare eccedenze e gestire le consegne' then failed:=true;else raise;end if;end;if not failed then raise exception 'FAIL business edit context';end if;
failed:=false;begin perform public.saveat_change_reservation(rid,'[]',0,gen_random_uuid());exception when others then if sqlerrm='Gli account attività possono solo pubblicare eccedenze e gestire le consegne' then failed:=true;else raise;end if;end;if not failed then raise exception 'FAIL business edit';end if;
perform public.saveat_transition(rid,'cancelled');
end;$$;
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$begin
if not public.saveat_can_discover() then raise exception 'FAIL anonymous discovery';end if;
if jsonb_array_length(public.saveat_search('PROVA RUOLI TRANSITORIA'))<>3 then raise exception 'FAIL anonymous listings regression';end if;
if has_function_privilege(current_user,'public.saveat_reserve(uuid,jsonb,uuid)','execute') then raise exception 'FAIL anonymous reserve permissions';end if;
end;$$;
reset role;
select 'PASS: esercente pubblica e gestisce consegne, vede solo annunci/item propri, niente ricerca né prenotazioni privati o B2B; privati pubblicano e ritirano entrambi; modifica quantità, notifiche, completamento, impatto, storico e anonimo preservati' as test_result;
rollback;
