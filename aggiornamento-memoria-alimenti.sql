-- Saveat 16/10/2026: memoria privata e metadati alimento. Solo migrazione incrementale.
begin;
set local lock_timeout='5s';
alter table public.saveat_items add column if not exists category text not null default '' check(length(category)<=80);
alter table public.saveat_items add column if not exists description text not null default '' check(length(description)<=1000);
-- Conserva integralmente la definizione remota e aggiunge soltanto i due metadati.
do $patch$
declare definition text; old_columns text := 'unit_weight_kg,container_provided)'; old_values text := 'coalesce((v_item->>''container_provided'')::boolean,false) end)';
begin
 definition:=pg_get_functiondef('public.saveat_create_listing(jsonb,jsonb)'::regprocedure);
 if position('container_provided,category,description)' in definition)=0 then
  if position(old_columns in definition)=0 or position(old_values in definition)=0 then raise exception 'Definizione creazione inattesa: nessuna modifica applicata'; end if;
  definition:=replace(definition,old_columns,'unit_weight_kg,container_provided,category,description)');
  definition:=replace(definition,old_values,'coalesce((v_item->>''container_provided'')::boolean,false) end,coalesce(v_item->>''category'',''''),coalesce(v_item->>''description'',''''))');
  execute definition;
 end if;
end $patch$;
create table if not exists public.saveat_food_memory (
 owner_id uuid not null references auth.users(id) on delete cascade,
 food_key text not null check(length(food_key)<=220),
 reusable jsonb not null check(jsonb_typeof(reusable)='object'),
 updated_at timestamptz not null default now(),
 primary key(owner_id,food_key)
);
alter table public.saveat_food_memory enable row level security;
revoke all on public.saveat_food_memory from public,anon,authenticated;
grant select on public.saveat_food_memory to authenticated;
do $policy$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='saveat_food_memory' and policyname='saveat_food_memory_owner') then
 create policy saveat_food_memory_owner on public.saveat_food_memory for select to authenticated using (owner_id=(select auth.uid()));
 end if;
end $policy$;
create or replace function public.saveat_publish_food(p_listing jsonb,p_items jsonb) returns uuid
language plpgsql security definer set search_path='' as $body$
declare v_listing_id uuid; item jsonb; defaults jsonb;
begin
 if auth.uid() is null then raise exception 'Accedi per pubblicare'; end if;
 -- La RPC originale verifica profilo, quantità, prezzi, foto, ritiro e pagamenti.
 v_listing_id:=public.saveat_create_listing(p_listing,p_items);
 select jsonb_build_object('description',l.description,'municipality_code',l.municipality_code,'city_name',m.name,'province',m.province,'address',p.address,'contact',p.contact,'instructions',p.instructions,'payment_methods',to_jsonb(l.payment_methods)) into defaults
 from public.saveat_listings l join public.saveat_pickup p on p.listing_id=l.id join public.saveat_municipalities m on m.code=l.municipality_code where l.id=v_listing_id;
 for item in select value from jsonb_array_elements(p_items) loop
  insert into public.saveat_food_memory(owner_id,food_key,reusable,updated_at)
  values(auth.uid(),lower(trim(coalesce(item->>'category','')))||chr(31)||lower(trim(item->>'name')),
   jsonb_build_object('category',coalesce(item->>'category',''),'name',trim(item->>'name'),'description',coalesce(item->>'description',''),'unit',item->>'unit','price',coalesce((item->>'price')::numeric,0),'offer',case when coalesce((item->>'price')::numeric,0)>0 then 'sell' else 'donate' end,'allergens',coalesce(item->>'allergens',''),'unit_weight_kg',item->'unit_weight_kg','container_provided',case when item->>'unit'='confezioni' then true else coalesce((item->>'container_provided')::boolean,false) end,'defaults',defaults),now())
  on conflict(owner_id,food_key) do update set reusable=excluded.reusable,updated_at=excluded.updated_at;
 end loop;
 return v_listing_id;
end $body$;
revoke all on function public.saveat_publish_food(jsonb,jsonb) from public,anon;
grant execute on function public.saveat_publish_food(jsonb,jsonb) to authenticated;
-- Elenco privato: prima memoria aggiornata, poi storico del solo titolare. Nessuna quantità/data/foto restituita.
create or replace function public.saveat_food_suggestions() returns jsonb
language sql stable security definer set search_path='' as $body$
 select coalesce(jsonb_agg(x.reusable order by x.priority,x.updated_at desc),'[]'::jsonb) from (
 select reusable,0 as priority,updated_at from public.saveat_food_memory where owner_id=auth.uid()
 union all
 (select jsonb_build_object('name',i.name,'category',i.category,'description',i.description,'unit',i.unit,'price',i.price,'offer',case when i.price>0 then 'sell' else 'donate' end,'allergens',i.allergens,'unit_weight_kg',i.unit_weight_kg,'container_provided',i.container_provided,'defaults',jsonb_build_object('description',l.description,'municipality_code',l.municipality_code,'city_name',m.name,'province',m.province,'address',p.address,'contact',p.contact,'instructions',p.instructions,'payment_methods',to_jsonb(l.payment_methods))),1,l.created_at
 from public.saveat_listings l join public.saveat_items i on i.listing_id=l.id join public.saveat_municipalities m on m.code=l.municipality_code left join public.saveat_pickup p on p.listing_id=l.id
 where l.owner_id=auth.uid() order by l.created_at desc,i.id limit 500)
 ) x where auth.uid() is not null;
$body$;
revoke all on function public.saveat_food_suggestions() from public,anon;
grant execute on function public.saveat_food_suggestions() to authenticated;
notify pgrst,'reload schema';
commit;
