-- Buste rinominabili. Metadati aggiuntivi; storico, prezzi e RLS invariati.
begin;
set local lock_timeout='5s';
alter table public.saveat_items add column if not exists is_mixed_bag boolean;
alter table public.saveat_reservation_items add column if not exists is_mixed_bag boolean;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_create_listing(jsonb,jsonb)'::regprocedure),chr(13),'')) not in ('c43275d08500020ab571a099c83871aa','595ef5106f6ec798b441a999599f1fd8') then raise exception 'Definizione inattesa: saveat_create_listing';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_create_listing(p_listing jsonb, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_profile public.saveat_profiles; v_id uuid; v_item jsonb; v_price numeric; v_qty numeric; v_end timestamptz; v_start timestamptz;
begin
 if auth.uid() is null then raise exception 'Accedi per pubblicare'; end if;
 select * into v_profile from public.saveat_profiles where id=auth.uid();
 if v_profile.account_type is null then raise exception 'Completa il profilo'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 20 then raise exception 'Inserisci da 1 a 20 prodotti'; end if;
 v_start:=(p_listing->>'pickup_start')::timestamptz; v_end:=(p_listing->>'pickup_end')::timestamptz;
 if v_start is null or v_end is null or v_end<=now() or v_end<=v_start or v_end>now()+interval '30 days' then raise exception 'Fascia di ritiro non valida (massimo 30 giorni)'; end if;
 insert into public.saveat_listings(owner_id,seller_name,account_type,title,description,municipality_code,pickup_start,pickup_end)
 values(auth.uid(),case when v_profile.account_type='business' then v_profile.business_name else v_profile.display_name end,v_profile.account_type,
 trim(p_listing->>'title'),coalesce(p_listing->>'description',''),p_listing->>'municipality_code',v_start,v_end) returning id into v_id;
 insert into public.saveat_pickup(listing_id,address,contact,instructions) values(v_id,trim(p_listing->>'address'),trim(p_listing->>'contact'),coalesce(p_listing->>'instructions',''));
 for v_item in select value from jsonb_array_elements(p_items) loop
  v_price:=coalesce((v_item->>'price')::numeric,0); v_qty:=(v_item->>'quantity')::numeric;
  if v_qty is null or v_qty<=0 or v_qty<>round(v_qty,1) or v_price<>round(v_price,2) then raise exception 'Quantità o prezzo non validi'; end if;
  if v_item->>'unit' in ('pezzi','confezioni') and v_qty<>trunc(v_qty) then raise exception 'Usa quantità intere per pezzi e confezioni'; end if;
  if v_item->>'date_type'='use_by' and (v_item->>'label_date')::date < (v_end at time zone 'Europe/Rome')::date then raise exception 'Il ritiro deve avvenire entro la data di scadenza'; end if;
  if nullif(v_item->>'photo_path','') is not null and not exists(select 1 from storage.objects where bucket_id='saveat-photos' and name=v_item->>'photo_path' and split_part(name,'/',1)=auth.uid()::text) then raise exception 'Foto non valida'; end if;
  if (v_item->>'unit'='confezioni' and coalesce((v_item->>'is_mixed_bag')::boolean,trim(v_item->>'name') ~* '^busta\y')) and nullif(trim(v_item->>'description'),'') is null then raise exception 'Indica il contenuto indicativo della busta';end if;
 insert into public.saveat_items(listing_id,name,unit,quantity,available,price,label_date,date_type,allergens,photo_path,unit_weight_kg,container_provided,category,description,is_mixed_bag)
  values(v_id,trim(v_item->>'name'),v_item->>'unit',v_qty,v_qty,v_price,(nullif(v_item->>'label_date',''))::date,v_item->>'date_type',coalesce(v_item->>'allergens',''),nullif(v_item->>'photo_path',''),(nullif(v_item->>'unit_weight_kg',''))::numeric,case when v_item->>'unit'='confezioni' then true else coalesce((v_item->>'container_provided')::boolean,false) end,coalesce(v_item->>'category',''),coalesce(v_item->>'description',''),(v_item->>'unit'='confezioni' and coalesce((v_item->>'is_mixed_bag')::boolean,trim(v_item->>'name') ~* '^busta\y')));
 end loop;
 update public.saveat_listings set payment_methods=public.saveat_payment_methods(p_listing,exists(select 1 from public.saveat_items where listing_id=v_id and price>0)) where id=v_id; perform public.saveat_set_pickup_point(v_id,p_listing); return v_id;
end; $function$
;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_update_listing(uuid,jsonb,jsonb)'::regprocedure),chr(13),'')) not in ('2095a07520049f2ceb83a3e667b5905c','54dda7ece69311971a16ef801ce616e0') then raise exception 'Definizione inattesa: saveat_update_listing';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_update_listing(p_id uuid, p_listing jsonb, p_items jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l public.saveat_listings;p public.saveat_pickup;i public.saveat_items;j jsonb;s timestamptz;e timestamptz;q numeric;v_price numeric;committed numeric;photo text;factor numeric;dtype text;ldate date;before_state jsonb;after_state jsonb;changes text;
begin
 select * into l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or l.owner_id is distinct from auth.uid() then raise exception 'Puoi modificare solo i tuoi annunci';end if;
 select * into p from public.saveat_pickup where listing_id=p_id;
 select jsonb_build_object('listing',to_jsonb(l),'pickup',to_jsonb(p),'items',(select jsonb_agg(to_jsonb(x) order by x.id) from public.saveat_items x where x.listing_id=p_id)) into before_state;
 update public.saveat_listings set title=trim(p_listing->>'title'),description=coalesce(p_listing->>'description','') where id=p_id;
 if p_items is null then return;end if;
 if l.status='active' and l.pickup_end<=now() then
 update public.saveat_reservations set status='expired',updated_at=now() where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is null;
 end if;
 s:=(p_listing->>'pickup_start')::timestamptz;e:=(p_listing->>'pickup_end')::timestamptz;
 if s is null or e is null or e<=s or (l.status='active' and ((e is distinct from l.pickup_end or s is distinct from l.pickup_start) and (e<=now() or e>now()+interval '30 days'))) then raise exception 'Fascia di ritiro non valida (massimo 30 giorni)';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<>(select count(*) from public.saveat_items where listing_id=p_id) or exists(select 1 from jsonb_array_elements(p_items) x group by x->>'id' having count(*)>1) then raise exception 'Elenco alimenti non valido';end if;
 for j in select value from jsonb_array_elements(p_items) loop
 select * into i from public.saveat_items where id=(j->>'id')::uuid and listing_id=p_id for update;
 if not found then raise exception 'Alimento non accessibile';end if;
 factor:=1;
 if j->>'unit' is distinct from i.unit then
 if exists(select 1 from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id where ri.item_id=i.id and r.status in ('reserved','confirmed','collected')) then
 factor:=(j->>'unit_conversion')::numeric;
 if factor is null or factor<=0 or factor>1000000 then raise exception 'Indica a quante nuove unità corrisponde una vecchia unità';end if;
 end if;
 if exists(select 1 from public.saveat_reservation_items where item_id=i.id and inventory_quantity*factor<>round(inventory_quantity*factor,3)) then raise exception 'Conversione non valida: usa al massimo tre decimali nelle quantità convertite';end if;
 update public.saveat_reservation_items set inventory_quantity=inventory_quantity*factor where item_id=i.id;
 end if;
 select coalesce(sum(ri.inventory_quantity),0) into committed from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id where ri.item_id=i.id and r.status in ('collected','reserved','confirmed');
 q:=(j->>'quantity')::numeric;v_price:=(j->>'price')::numeric;
 if q is null or v_price is null or q<=0 or (q is distinct from i.quantity and q<>round(q,1)) or v_price<>round(v_price,2) or q<committed then raise exception 'Quantità non valida: conserva le quantità già prenotate o consegnate';end if;
 if j->>'unit' in ('pezzi','confezioni') and (q<>trunc(q) or exists(select 1 from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id where ri.item_id=i.id and r.status in ('reserved','confirmed','collected') and ri.inventory_quantity<>trunc(ri.inventory_quantity))) then raise exception 'Usa quantità intere per pezzi e confezioni';end if;
 dtype:=case when j ? 'date_type' then j->>'date_type' else i.date_type end;
 ldate:=case when j ? 'label_date' then nullif(j->>'label_date','')::date else i.label_date end;
 if dtype='none' then ldate:=null;end if;
 if dtype='use_by' and ldate<(e at time zone 'Europe/Rome')::date then raise exception 'Il ritiro deve avvenire entro la scadenza del cibo';end if;
 photo:=case when j ? 'photo_path' then nullif(j->>'photo_path','') else i.photo_path end;
 if photo is distinct from i.photo_path and photo is not null and (split_part(photo,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='saveat-photos' and name=photo)) then raise exception 'Foto non accessibile';end if;
 if (j->>'unit'='confezioni' and coalesce((j->>'is_mixed_bag')::boolean,i.is_mixed_bag,i.unit='confezioni' and trim(i.name) ~* '^busta\y')) and nullif(trim(coalesce(j->>'description',i.description)),'') is null then raise exception 'Indica il contenuto indicativo della busta';end if;
 update public.saveat_items set name=trim(j->>'name'),is_mixed_bag=(j->>'unit'='confezioni' and coalesce((j->>'is_mixed_bag')::boolean,i.is_mixed_bag,i.unit='confezioni' and trim(i.name) ~* '^busta\y')),description=case when j ? 'description' then coalesce(j->>'description','') else i.description end,unit=j->>'unit',quantity=q,available=q-committed,price=v_price,photo_path=photo,date_type=dtype,label_date=ldate,allergens=case when j ? 'allergens' then coalesce(j->>'allergens','') else i.allergens end,unit_weight_kg=case when j ? 'unit_weight_kg' then nullif(j->>'unit_weight_kg','')::numeric else i.unit_weight_kg end,container_provided=case when j->>'unit'='confezioni' then true when j ? 'container_provided' then coalesce((j->>'container_provided')::boolean,false) else i.container_provided end where id=i.id;
 end loop;
 update public.saveat_listings set municipality_code=p_listing->>'municipality_code',pickup_start=s,pickup_end=e,payment_methods=public.saveat_payment_methods(p_listing,exists(select 1 from public.saveat_items where listing_id=p_id and price>0),l.payment_methods) where id=p_id;
 update public.saveat_pickup set address=trim(p_listing->>'address'),contact=trim(p_listing->>'contact'),instructions=coalesce(p_listing->>'instructions','') where listing_id=p_id;
 perform public.saveat_set_pickup_point(p_id,p_listing); select jsonb_build_object('listing',to_jsonb(x),'pickup',(select to_jsonb(y) from public.saveat_pickup y where y.listing_id=p_id),'items',(select jsonb_agg(to_jsonb(z) order by z.id) from public.saveat_items z where z.listing_id=p_id)) into after_state from public.saveat_listings x where x.id=p_id;
 if l.account_type='business' then before_state:=jsonb_set(before_state,'{pickup,contact}',to_jsonb('Ritiro tramite Saveat: segui le istruzioni e mostra la prenotazione al punto di ritiro.'::text));after_state:=jsonb_set(after_state,'{pickup,contact}',to_jsonb('Ritiro tramite Saveat: segui le istruzioni e mostra la prenotazione al punto di ritiro.'::text));end if;
 changes:=public.saveat_listing_changes(before_state,after_state);
 if changes<>'' then
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message)
 select r.customer_id,r.id,'listing_changed','Annuncio aggiornato: controlla il tuo ritiro','Modifiche a «'||trim(p_listing->>'title')||'»:'||changes||E'\nIl prezzo della tua prenotazione resta quello concordato.' from public.saveat_reservations r where r.listing_id=p_id and r.status in ('reserved','confirmed')
 on conflict(reservation_id,kind) do update set title=excluded.title,message=excluded.message,created_at=now(),read_at=null;
 end if;
end;$function$
;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_reserve(uuid,jsonb,uuid)'::regprocedure),chr(13),'')) not in ('9473306e695a0b0d1eea0994d32f855a','2a111ee9305b8cb5b2db361dca67b9cb') then raise exception 'Definizione inattesa: saveat_reserve';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_reserve(p_listing_id uuid, p_items jsonb, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_listing public.saveat_listings; v_id uuid; v_item public.saveat_items; v_request jsonb; v_qty numeric;
begin

 if not public.saveat_can_collect() then raise exception 'Gli account attività possono solo pubblicare eccedenze e gestire le consegne';end if;
 if auth.uid() is null then raise exception 'Accedi per prenotare'; end if;
 if p_request_id is null or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 20 then raise exception 'Prenotazione non valida'; end if;
 -- Lock per annuncio: controlli, disponibilità e inserimenti nella stessa transazione.
 select * into v_listing from public.saveat_listings where id=p_listing_id for update;
 if not found then raise exception 'Annuncio non trovato'; end if;
 select id into v_id from public.saveat_reservations where customer_id=auth.uid() and request_id=p_request_id;
 if v_id is not null then
  if not exists(select 1 from public.saveat_reservations where id=v_id and listing_id=p_listing_id) then raise exception 'Richiesta già utilizzata'; end if;
  return v_id;
 end if;
 if v_listing.owner_id=auth.uid() then raise exception 'Non puoi prenotare il tuo annuncio'; end if;
 if v_listing.status<>'active' or v_listing.pickup_end<=now() then raise exception 'Annuncio non più disponibile'; end if;
 if exists(select 1 from jsonb_array_elements(p_items) a group by a->>'item_id' having count(*)>1) then raise exception 'Prodotto duplicato'; end if;
 if exists(select 1 from public.saveat_reservations where listing_id=p_listing_id and customer_id=auth.uid() and status in ('reserved','confirmed')) then raise exception 'Hai già una prenotazione attiva per questo annuncio'; end if;
 insert into public.saveat_reservations(listing_id,customer_id,request_id,status) values(p_listing_id,auth.uid(),p_request_id,'confirmed') returning id into v_id;
 for v_request in select value from jsonb_array_elements(p_items) loop
  select * into v_item from public.saveat_items where id=(v_request->>'item_id')::uuid and listing_id=p_listing_id for update;
  if not found then raise exception 'Prodotto non trovato'; end if;
  v_qty:=(v_request->>'quantity')::numeric;
  if v_qty is null or v_qty<=0 or v_qty<>round(v_qty,1) or v_qty>v_item.available then raise exception 'Quantità non disponibile'; end if;
  if v_item.unit in ('pezzi','confezioni') and v_qty<>trunc(v_qty) then raise exception 'Usa quantità intere'; end if;
  update public.saveat_items set available=available-v_qty where id=v_item.id;
  insert into public.saveat_reservation_items(reservation_id,item_id,name,unit,quantity,price,is_mixed_bag) values(v_id,v_item.id,v_item.name,v_item.unit,v_qty,v_item.price,coalesce(v_item.is_mixed_bag,v_item.unit='confezioni' and trim(v_item.name) ~* '^busta\y'));
 end loop;
 perform public.saveat_notify_reservation(v_id);
 return v_id;
end; $function$
;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_publish_food(jsonb,jsonb)'::regprocedure),chr(13),'')) not in ('6fddd2ab50236c793afa23e433f71f8b','fe904fc18d1628af9cf09f4e75eb6326') then raise exception 'Definizione inattesa: saveat_publish_food';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_publish_food(p_listing jsonb, p_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_listing_id uuid;item jsonb;defaults jsonb;
begin
 if auth.uid() is null then raise exception 'Accedi per pubblicare';end if;
 v_listing_id:=public.saveat_create_listing(p_listing,p_items);
 select jsonb_build_object('description',l.description,'municipality_code',l.municipality_code,'city_name',m.name,'province',m.province,'address',p.address,'contact',p.contact,'instructions',p.instructions,'payment_methods',to_jsonb(l.payment_methods)) into defaults from public.saveat_listings l join public.saveat_pickup p on p.listing_id=l.id join public.saveat_municipalities m on m.code=l.municipality_code where l.id=v_listing_id;
 for item in select value from jsonb_array_elements(p_items) loop
 insert into public.saveat_food_memory(owner_id,food_key,reusable,updated_at) values(auth.uid(),lower(trim(coalesce(item->>'category','')))||chr(31)||lower(trim(item->>'name')),jsonb_build_object('is_mixed_bag',(item->>'unit'='confezioni' and coalesce((item->>'is_mixed_bag')::boolean,trim(item->>'name') ~* '^busta\y')),'category',coalesce(item->>'category',''),'name',trim(item->>'name'),'description',coalesce(item->>'description',''),'unit',item->>'unit','price',coalesce((item->>'price')::numeric,0),'offer',case when coalesce((item->>'price')::numeric,0)>0 then 'sell' else 'donate' end,'allergens',coalesce(item->>'allergens',''),'unit_weight_kg',item->'unit_weight_kg','container_provided',case when item->>'unit'='confezioni' then true else coalesce((item->>'container_provided')::boolean,false) end,'defaults',defaults),now()) on conflict(owner_id,food_key) do update set reusable=excluded.reusable,updated_at=excluded.updated_at;
 end loop;return v_listing_id;end $function$
;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_food_suggestions()'::regprocedure),chr(13),'')) not in ('5a65c11d8c3bd2559ad80043cbd5b531','34da395f49b808e053d96156a51b4033') then raise exception 'Definizione inattesa: saveat_food_suggestions';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_food_suggestions()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(x.reusable order by x.priority,x.updated_at desc),'[]'::jsonb) from(
 select reusable,0 as priority,updated_at from public.saveat_food_memory where owner_id=auth.uid()
 union all
 (select jsonb_build_object('is_mixed_bag',i.is_mixed_bag,'name',i.name,'category',i.category,'description',i.description,'unit',i.unit,'price',i.price,'offer',case when i.price>0 then 'sell' else 'donate' end,'allergens',i.allergens,'unit_weight_kg',i.unit_weight_kg,'container_provided',i.container_provided,'defaults',jsonb_build_object('description',l.description,'municipality_code',l.municipality_code,'city_name',m.name,'province',m.province,'address',p.address,'contact',p.contact,'instructions',p.instructions,'payment_methods',to_jsonb(l.payment_methods))),1,l.created_at from public.saveat_listings l join public.saveat_items i on i.listing_id=l.id join public.saveat_municipalities m on m.code=l.municipality_code left join public.saveat_pickup p on p.listing_id=l.id where l.owner_id=auth.uid() order by l.created_at desc,i.id limit 500)) x where auth.uid() is not null;
$function$
;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_reservation_edit_context(uuid)'::regprocedure),chr(13),'')) not in ('da87f8f0cf8d0c3297f9e09dc442208d','aca5fdd6a74eb10fac7fa8da250420a9') then raise exception 'Definizione inattesa: saveat_reservation_edit_context';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_reservation_edit_context(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.saveat_reservations;l public.saveat_listings;result jsonb;begin

 if not public.saveat_can_collect() then raise exception 'Gli account attività possono solo pubblicare eccedenze e gestire le consegne';end if;
 select * into r from public.saveat_reservations where id=p_id;
 if auth.uid() is null or r.customer_id is distinct from auth.uid() then raise exception 'Puoi modificare solo i tuoi ritiri';end if;
 select * into l from public.saveat_listings where id=r.listing_id;
 if r.status not in ('reserved','confirmed') or r.customer_collected_at is not null or l.id is null or l.status<>'active' or l.pickup_end<=now() then raise exception 'Ritiro non più modificabile';end if;
 select jsonb_build_object('id',r.id,'revision',r.quantity_revision,'items',coalesce(jsonb_agg(jsonb_build_object('is_mixed_bag',ri.is_mixed_bag,'snapshot_id',ri.snapshot_id,'name',ri.name,'unit',ri.unit,'quantity',ri.quantity,'price',ri.price,'maximum',greatest(ri.quantity,floor((ri.quantity+ci.available*ri.quantity/nullif(ri.inventory_quantity,0))*case when ri.unit in ('pezzi','confezioni') then 1 else 10 end)/case when ri.unit in ('pezzi','confezioni') then 1 else 10 end),'current_unit',ci.unit) order by ri.snapshot_id),'[]'::jsonb)) into result from public.saveat_reservation_items ri join public.saveat_items ci on ci.id=ri.item_id where ri.reservation_id=p_id;
 return result;
end;$function$
;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_my_reservations()'::regprocedure),chr(13),'')) not in ('4ba00cb55416702cf372d9ca94b0bf6f','d0d98e892e8389ece4701097937aeb97') then raise exception 'Definizione inattesa: saveat_my_reservations';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_my_reservations()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(jsonb_build_object(
 'account_type',coalesce(l.account_type,r.listing_snapshot->>'account_type'),'completed_at',r.completed_at,'completion_time_estimated',r.completion_time_estimated,
 'guidance',(select coalesce(jsonb_agg(jsonb_build_object('code',g.code,'message',public.saveat_guidance_text(g.code),'sender_role',case when g.sender_id=r.customer_id then 'customer' else 'owner' end,'created_at',g.created_at) order by g.created_at),'[]'::jsonb) from public.saveat_guidance g where g.reservation_id=r.id),
 'id',r.id,'cancellation_reason',r.cancellation_reason,'status',case when r.status in ('reserved','confirmed') and r.customer_collected_at is null and l.pickup_end<=now() then 'expired' else r.status end,
 'customer_name',case when l.owner_id=auth.uid() then coalesce(nullif(trim(c.display_name),''),'Utente Saveat') else null end,'customer_collected_at',r.customer_collected_at,'listing_status',l.status,'listing_deleted',l.id is null,'listing_id',l.id,'title',coalesce(l.title,r.listing_snapshot->>'title'),'description',coalesce(l.description,r.listing_snapshot->>'description'),'owner_id',coalesce(l.owner_id,(r.listing_snapshot->>'owner_id')::uuid),'seller_name',coalesce(l.seller_name,r.listing_snapshot->>'seller_name'),
 'pickup_start',case when r.status in ('reserved','confirmed') then l.pickup_start else coalesce((r.listing_snapshot->>'pickup_start')::timestamptz,l.pickup_start) end,'pickup_end',case when r.status in ('reserved','confirmed') then l.pickup_end else coalesce((r.listing_snapshot->>'pickup_end')::timestamptz,l.pickup_end) end,'payment_methods',case when r.status in ('reserved','confirmed') then to_jsonb(l.payment_methods) else r.listing_snapshot->'payment_methods' end,'created_at',r.created_at,
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)||jsonb_build_object('current_item',case when r.status in ('reserved','confirmed') then (select jsonb_build_object('is_mixed_bag',ci.is_mixed_bag,'name',ci.name,'unit',ci.unit,'date_type',ci.date_type,'label_date',ci.label_date,'allergens',ci.allergens,'container_provided',ci.container_provided) from public.saveat_items ci where ci.id=ri.item_id) else null end)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p)||jsonb_build_object('contact',case when l.account_type='business' then 'Ritiro tramite Saveat: segui le istruzioni e mostra la prenotazione al punto di ritiro.' else p.contact end) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r left join public.saveat_listings l on l.id=r.listing_id join public.saveat_profiles c on c.id=r.customer_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$function$
;
do $guard$ begin if md5(replace(pg_get_functiondef('public.saveat_change_reservation(uuid,jsonb,integer,uuid)'::regprocedure),chr(13),'')) not in ('3eca77e6ad55ee0a0bfe24d522ea3fe1','22a6f03690f3a2e5f14febec66faf455') then raise exception 'Definizione inattesa: saveat_change_reservation';end if;end $guard$;
CREATE OR REPLACE FUNCTION public.saveat_change_reservation(p_id uuid, p_items jsonb, p_revision integer, p_request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.saveat_reservations;l public.saveat_listings;ri public.saveat_reservation_items;ci public.saveat_items;j jsonb;q numeric;inv numeric;delta numeric;old_rows jsonb;new_rows jsonb;prior public.saveat_reservation_changes;change_id uuid;msg text:='';total numeric;previous_total numeric;name_customer text;notice_id uuid;changed boolean:=false;begin

 if not public.saveat_can_collect() then raise exception 'Gli account attività possono solo pubblicare eccedenze e gestire le consegne';end if;
 if auth.uid() is null then raise exception 'Accedi per modificare il ritiro';end if;
 select * into r from public.saveat_reservations where id=p_id;
 if r.customer_id is distinct from auth.uid() then raise exception 'Puoi modificare solo i tuoi ritiri';end if;
 select * into l from public.saveat_listings where id=r.listing_id for update;
 select * into r from public.saveat_reservations where id=p_id for update;
 if p_request_id is null or p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items) not between 1 and 20 then raise exception 'Modifica non valida';end if;
 select * into prior from public.saveat_reservation_changes where customer_id=auth.uid() and request_id=p_request_id;
 if found then if prior.reservation_id<>p_id or prior.payload<>p_items then raise exception 'Richiesta già utilizzata';end if;return prior.id;end if;
 if r.status not in ('reserved','confirmed') or r.customer_collected_at is not null or l.id is null or l.status<>'active' or l.pickup_end<=now() then raise exception 'Ritiro non più modificabile';end if;
 if p_revision is distinct from r.quantity_revision then raise exception 'Il ritiro è cambiato: riapri Modifica quantità';end if;
 if jsonb_array_length(p_items)<>(select count(*) from public.saveat_reservation_items where reservation_id=p_id) or exists(select 1 from jsonb_array_elements(p_items) x group by x->>'snapshot_id' having count(*)>1) or exists(select 1 from jsonb_array_elements(p_items) x where not exists(select 1 from public.saveat_reservation_items z where z.reservation_id=p_id and z.snapshot_id=(x->>'snapshot_id')::uuid)) then raise exception 'Elenco alimenti non valido';end if;
 select jsonb_agg(to_jsonb(x) order by x.snapshot_id),sum(x.quantity*x.price) into old_rows,previous_total from public.saveat_reservation_items x where x.reservation_id=p_id;
 for ri in select * from public.saveat_reservation_items where reservation_id=p_id order by snapshot_id for update loop
 select value into j from jsonb_array_elements(p_items) where value->>'snapshot_id'=ri.snapshot_id::text;
 q:=(j->>'quantity')::numeric;
 if q is null or q::text in ('NaN','Infinity','-Infinity') or q<0 or (q<>ri.quantity and q<>round(q,1)) or (ri.unit in ('pezzi','confezioni') and q<>trunc(q)) then raise exception 'Quantità non valida';end if;
 select * into ci from public.saveat_items where id=ri.item_id and listing_id=l.id for update;
 if not found or ri.quantity<=0 or ri.inventory_quantity<=0 then raise exception 'Alimento non più modificabile';end if;
 inv:=q*ri.inventory_quantity/ri.quantity;delta:=inv-ri.inventory_quantity;
 if inv<>round(inv,3) or (ci.unit in ('pezzi','confezioni') and inv<>trunc(inv)) then raise exception 'La nuova quantità non corrisponde alle unità attuali dell’annuncio';end if;
 if delta>ci.available then raise exception 'Disponibilità cambiata: riapri Modifica quantità';end if;
 if q<>ri.quantity then
 changed:=true;msg:=msg||E'\n'||ri.name||': '||public.saveat_format_quantity(ri.quantity)||' → '||public.saveat_format_quantity(q)||' '||case when coalesce(ri.is_mixed_bag,ri.unit='confezioni' and trim(ri.name) ~* '^busta\y') then case when q=1 then 'busta' else 'buste' end else ri.unit end;
 update public.saveat_items set available=available-delta where id=ci.id;
 if q=0 then delete from public.saveat_reservation_items where snapshot_id=ri.snapshot_id;else update public.saveat_reservation_items set quantity=q,inventory_quantity=inv where snapshot_id=ri.snapshot_id;end if;
 end if;
 end loop;
 if not exists(select 1 from public.saveat_reservation_items where reservation_id=p_id) then raise exception 'Per togliere tutti gli alimenti usa Annulla prenotazione';end if;
 if not changed then raise exception 'Non hai modificato le quantità';end if;
 select jsonb_agg(to_jsonb(x) order by x.snapshot_id),sum(x.quantity*x.price) into new_rows,total from public.saveat_reservation_items x where x.reservation_id=p_id;
 insert into public.saveat_reservation_changes(reservation_id,customer_id,request_id,payload,before_items,after_items) values(p_id,auth.uid(),p_request_id,p_items,old_rows,new_rows) returning id into change_id;
 update public.saveat_reservations set quantity_revision=quantity_revision+1,updated_at=now() where id=p_id;
 select display_name into name_customer from public.saveat_profiles where id=auth.uid();
 msg:=coalesce(name_customer,'Un utente Saveat')||' ha modificato il ritiro «'||l.title||'».'||msg||E'\nTotale: '||to_char(previous_total,'FM999999999990.00')||' € → '||to_char(total,'FM999999999990.00')||E' €\nPrezzi unitari concordati invariati.\nCodice prenotazione: '||left(p_id::text,8);
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message) values(l.owner_id,p_id,'reservation_changed','Quantità del ritiro modificate',msg) on conflict(reservation_id,kind) do update set message=excluded.message,title=excluded.title,created_at=now(),read_at=null returning id into notice_id;
 -- Aggiorna la coda esistente con l’ultima variazione; il retry non arriva qui.
 insert into public.saveat_notification_outbox(id,user_id,recipient_email,subject,message) select notice_id,l.owner_id,u.email,'Saveat — Quantità del ritiro modificate',msg from auth.users u where u.id=l.owner_id on conflict(id) do update set subject=excluded.subject,message=excluded.message,created_at=now(),email_sent_at=null,push_sent_at=null,attempts=0,last_error=null,locked_until=null;
 return change_id;
end;$function$
;
notify pgrst,'reload schema';
commit;
