-- Saveat 28 ottobre: punto pubblico separato dalla sede, memoria privata e distanze.
begin;
set local lock_timeout='5s';
alter table public.saveat_listings add column if not exists pickup_public_address text check(length(pickup_public_address) between 3 and 300),add column if not exists pickup_lat double precision check(pickup_lat between -90 and 90),add column if not exists pickup_lon double precision check(pickup_lon between -180 and 180);
create table if not exists public.saveat_pickup_memory(owner_id uuid not null references auth.users(id) on delete cascade,point_key text not null,municipality_code text not null,address text not null,latitude double precision not null,longitude double precision not null,updated_at timestamptz not null default clock_timestamp(),primary key(owner_id,point_key));
alter table public.saveat_pickup_memory enable row level security;
revoke all on public.saveat_pickup_memory from public,anon,authenticated;
grant select on public.saveat_pickup_memory to authenticated;
do $$begin if not exists(select 1 from pg_policies where schemaname='public' and tablename='saveat_pickup_memory' and policyname='saveat_pickup_memory_owner') then create policy saveat_pickup_memory_owner on public.saveat_pickup_memory for select to authenticated using(owner_id=(select auth.uid()));end if;end;$$;
create or replace function public.saveat_set_pickup_point(p_id uuid,p_listing jsonb) returns void language plpgsql security definer set search_path='' as $$
declare l public.saveat_listings;lat double precision;lon double precision;addr text;begin
select * into l from public.saveat_listings where id=p_id for update;
if auth.uid() is null or l.owner_id is distinct from auth.uid() then raise exception 'Punto di ritiro non accessibile';end if;
-- I client precedenti e gli indirizzi preesistenti non vengono resi pubblici automaticamente.
if not(p_listing ? 'pickup_public') then
 if l.pickup_public_address is not null and (l.pickup_public_address is distinct from trim(p_listing->>'address')) then update public.saveat_listings set pickup_public_address=null,pickup_lat=null,pickup_lon=null where id=p_id;end if;
 return;
end if;
if coalesce((p_listing->>'pickup_public')::boolean,false) is not true then raise exception 'Conferma il punto di ritiro pubblico';end if;
addr:=trim(p_listing->>'address');lat:=nullif(p_listing->>'pickup_lat','')::double precision;lon:=nullif(p_listing->>'pickup_lon','')::double precision;
if addr is null or length(addr) not between 3 and 300 or lat is null or lon is null or lat not between -90 and 90 or lon not between -180 and 180 then raise exception 'Indica indirizzo e posizione del punto di ritiro';end if;
update public.saveat_listings set pickup_public_address=addr,pickup_lat=lat,pickup_lon=lon where id=p_id;
insert into public.saveat_pickup_memory(owner_id,point_key,municipality_code,address,latitude,longitude) values(auth.uid(),l.municipality_code||chr(31)||lower(addr),l.municipality_code,addr,lat,lon) on conflict(owner_id,point_key) do update set address=excluded.address,latitude=excluded.latitude,longitude=excluded.longitude,updated_at=clock_timestamp();
end;$$;
revoke all on function public.saveat_set_pickup_point(uuid,jsonb) from public,anon,authenticated;
create or replace function public.saveat_pickup_suggestions() returns jsonb language sql stable security definer set search_path='' as $$
select coalesce(jsonb_agg(to_jsonb(q) order by q.updated_at desc),'[]'::jsonb) from (
select distinct on (x.municipality_code,lower(trim(x.address))) x.municipality_code,x.address,x.latitude,x.longitude,m.name as city_name,m.province,m.latitude as city_lat,m.longitude as city_lon,x.confirmed,x.updated_at from (
select municipality_code,address,latitude,longitude,true as confirmed,updated_at from public.saveat_pickup_memory where owner_id=auth.uid()
union all
select l.municipality_code,p.address,l.pickup_lat,l.pickup_lon,l.pickup_public_address is not null,l.created_at from public.saveat_listings l join public.saveat_pickup p on p.listing_id=l.id where l.owner_id=auth.uid()
) x join public.saveat_municipalities m on m.code=x.municipality_code where auth.uid() is not null order by x.municipality_code,lower(trim(x.address)),x.confirmed desc,x.updated_at desc limit 100
) q;
$$;
revoke all on function public.saveat_pickup_suggestions() from public,anon;
grant execute on function public.saveat_pickup_suggestions() to authenticated;
-- Modifiche strettamente mirate: preservano verifiche, lock, storico e privilegi.
do $patch$ declare d text;needle text;begin
 d:=pg_get_functiondef('public.saveat_create_listing(jsonb,jsonb)'::regprocedure);needle:='return v_id;';
 if position('saveat_set_pickup_point' in d)=0 then if position(needle in d)=0 then raise exception 'Creazione inattesa';end if;execute replace(d,needle,'perform public.saveat_set_pickup_point(v_id,p_listing); return v_id;');end if;
 d:=pg_get_functiondef('public.saveat_update_listing(uuid,jsonb,jsonb)'::regprocedure);needle:='select jsonb_build_object(''listing'',to_jsonb(x),';
 if position('saveat_set_pickup_point' in d)=0 then if position(needle in d)=0 then raise exception 'Aggiornamento inatteso';end if;execute replace(d,needle,'perform public.saveat_set_pickup_point(p_id,p_listing); '||needle);end if;
 d:=pg_get_functiondef('public.saveat_listing_changes(jsonb,jsonb)'::regprocedure);needle:='"payment_methods":"Metodi di pagamento"';
 if position('"pickup_lat":"Posizione ritiro (latitudine)"' in d)=0 then if position(needle in d)=0 then raise exception 'Avvisi inattesi';end if;execute replace(d,needle,needle||',"pickup_lat":"Posizione ritiro (latitudine)","pickup_lon":"Posizione ritiro (longitudine)"');end if;
end $patch$;
create or replace function public.saveat_format_quantity(n numeric) returns text language sql immutable set search_path='' as $$ select replace(regexp_replace(regexp_replace(n::text,'(\.[0-9]*?)0+$','\1'),'\.$',''),'.',',');$$;
revoke all on function public.saveat_format_quantity(numeric) from public;
grant execute on function public.saveat_format_quantity(numeric) to authenticated;
do $patch$ declare d text;needle text;begin
d:=pg_get_functiondef('public.saveat_change_reservation(uuid,jsonb,integer,uuid)'::regprocedure);needle:='ri.quantity::text||'' → ''||q::text';
if position('saveat_format_quantity(ri.quantity)' in d)=0 then if position(needle in d)=0 then raise exception 'Formato variazione inatteso';end if;execute replace(d,needle,'public.saveat_format_quantity(ri.quantity)||'' → ''||public.saveat_format_quantity(q)');end if;
end $patch$;
create or replace function public.saveat_search_filtered(p_lat double precision,p_lon double precision,p_radius integer,p_query text default '',p_page integer default 0,p_size integer default 20,p_category text default '',p_offer text default 'all') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;category_filter text:=coalesce(trim(p_category),'');offer_filter text:=coalesce(p_offer,'all');
begin
 if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_radius is null or p_radius not between 1 and 200 then raise exception 'Zona di ricerca non valida'; end if;
 if offer_filter not in ('all','free','paid') then raise exception 'Scegli una modalità valida';end if;
 if category_filter<>'' and category_filter not in ('Pane e prodotti da forno','Frutta e verdura','Pasticceria e dolci','Gastronomia e piatti pronti','Latticini e formaggi','Carne e salumi','Pesce','Prodotti confezionati','Bevande','Altri alimenti') then raise exception 'Scegli una categoria valida';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.distance_km,q.created_at desc,q.id),'[]'::jsonb) into result from (
 select l.*,public.saveat_distance_km(p_lat,p_lon,coalesce(l.pickup_lat,m.latitude),coalesce(l.pickup_lon,m.longitude)) distance_km,
 (select coalesce(jsonb_agg(to_jsonb(i) order by i.name),'[]'::jsonb) from public.saveat_items i where i.listing_id=l.id) saveat_items,
 jsonb_build_object('name',m.name,'province',m.province) saveat_municipalities
 from public.saveat_listings l join public.saveat_municipalities m on m.code=l.municipality_code
 where public.saveat_can_discover() and l.status='active' and l.pickup_end>now() and coalesce(l.pickup_lat,m.latitude) is not null and coalesce(l.pickup_lon,m.longitude) is not null
 and public.saveat_distance_km(p_lat,p_lon,coalesce(l.pickup_lat,m.latitude),coalesce(l.pickup_lon,m.longitude))<=p_radius
 and exists(select 1 from public.saveat_items i where i.listing_id=l.id and i.available>0
 and (category_filter='' or i.category=category_filter)
 and (offer_filter='all' or (offer_filter='free' and i.price=0) or (offer_filter='paid' and i.price>0))
 and (coalesce(trim(p_query),'')='' or l.title ilike '%'||left(p_query,100)||'%' or i.name ilike '%'||left(p_query,100)||'%'))
 order by distance_km,l.created_at desc,l.id limit least(greatest(coalesce(p_size,20),1),50) offset greatest(coalesce(p_page,0),0)*least(greatest(coalesce(p_size,20),1),50)
 ) q;
 return result;
end; $$;

do $patch$ declare d text;begin d:=pg_get_functiondef('public.saveat_search_nearby(double precision,double precision,integer,text,integer,integer)'::regprocedure);if position('coalesce(l.pickup_lat,m.latitude)' in d)=0 then if position('p_lat,p_lon,m.latitude,m.longitude' in d)=0 then raise exception 'Ricerca inattesa';end if;d:=replace(d,'p_lat,p_lon,m.latitude,m.longitude','p_lat,p_lon,coalesce(l.pickup_lat,m.latitude),coalesce(l.pickup_lon,m.longitude)');d:=replace(d,'m.latitude is not null and m.longitude is not null','coalesce(l.pickup_lat,m.latitude) is not null and coalesce(l.pickup_lon,m.longitude) is not null');execute d;end if;end $patch$;
notify pgrst,'reload schema';
commit;
