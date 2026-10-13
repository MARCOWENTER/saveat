begin;
alter table public.saveat_notifications drop constraint if exists saveat_notifications_kind_check;
alter table public.saveat_notifications add constraint saveat_notifications_kind_check check(kind in ('owner_unavailable','listing_changed','customer_cancelled','reservation_received'));
create or replace function public.saveat_notify_reservation(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare r public.saveat_reservations;l public.saveat_listings;v_name text;foods text;total numeric;v_id uuid;msg text;heading text;begin
 select * into r from public.saveat_reservations where id=p_id;
 if r.customer_id is distinct from auth.uid() then raise exception 'Prenotazione non accessibile';end if;
 select * into l from public.saveat_listings where id=r.listing_id;
 select display_name into v_name from public.saveat_profiles where id=r.customer_id;
 select string_agg(name||': '||trim(trailing '.' from trim(trailing '0' from quantity::text))||' '||unit,E'\n' order by name),sum(quantity*price) into foods,total from public.saveat_reservation_items where reservation_id=p_id;
 heading:=case when total>0 then 'Nuova prenotazione di acquisto' else 'Nuova prenotazione di donazione' end;
 msg:=coalesce(v_name,'Un utente Saveat')||' ha prenotato «'||l.title||'».'||E'\nAlimenti prenotati:\n'||foods||E'\n'||case when total>0 then 'Totale da pagare al ritiro: '||to_char(total,'FM999999999990.00')||' €' else 'Donazione gratuita' end||E'\nCodice prenotazione: '||left(r.id::text,8);
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message) values(l.owner_id,p_id,'reservation_received',heading,msg) on conflict(reservation_id,kind) do nothing returning id into v_id;
 if v_id is not null then insert into public.saveat_notification_outbox(id,user_id,recipient_email,subject,message) select v_id,l.owner_id,u.email,'Saveat — '||heading,msg from auth.users u where u.id=l.owner_id;end if;end;$$;
revoke all on function public.saveat_notify_reservation(uuid) from public,anon,authenticated;
create or replace function public.saveat_reserve(p_listing_id uuid,p_items jsonb,p_request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_listing public.saveat_listings; v_id uuid; v_item public.saveat_items; v_request jsonb; v_qty numeric;
begin
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
  insert into public.saveat_reservation_items values(v_id,v_item.id,v_item.name,v_item.unit,v_qty,v_item.price);
 end loop;
 perform public.saveat_notify_reservation(v_id);
 return v_id;
end; $$;
create or replace function public.saveat_create_listing(p_listing jsonb,p_items jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
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
  insert into public.saveat_items(listing_id,name,unit,quantity,available,price,label_date,date_type,allergens,photo_path,unit_weight_kg,container_provided)
  values(v_id,trim(v_item->>'name'),v_item->>'unit',v_qty,v_qty,v_price,(nullif(v_item->>'label_date',''))::date,v_item->>'date_type',coalesce(v_item->>'allergens',''),nullif(v_item->>'photo_path',''),(nullif(v_item->>'unit_weight_kg',''))::numeric,case when v_item->>'unit'='confezioni' then true else coalesce((v_item->>'container_provided')::boolean,false) end);
 end loop;
 update public.saveat_listings set payment_methods=public.saveat_payment_methods(p_listing,exists(select 1 from public.saveat_items where listing_id=v_id and price>0)) where id=v_id; return v_id;
end; $$;
create or replace function public.saveat_update_listing(p_id uuid,p_listing jsonb,p_items jsonb default null) returns void language plpgsql security definer set search_path='' as $$
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
 update public.saveat_items set name=trim(j->>'name'),unit=j->>'unit',quantity=q,available=q-committed,price=v_price,photo_path=photo,date_type=dtype,label_date=ldate,allergens=case when j ? 'allergens' then coalesce(j->>'allergens','') else i.allergens end,unit_weight_kg=case when j ? 'unit_weight_kg' then nullif(j->>'unit_weight_kg','')::numeric else i.unit_weight_kg end,container_provided=case when j->>'unit'='confezioni' then true when j ? 'container_provided' then coalesce((j->>'container_provided')::boolean,false) else i.container_provided end where id=i.id;
 end loop;
 update public.saveat_listings set municipality_code=p_listing->>'municipality_code',pickup_start=s,pickup_end=e,payment_methods=public.saveat_payment_methods(p_listing,exists(select 1 from public.saveat_items where listing_id=p_id and price>0),l.payment_methods) where id=p_id;
 update public.saveat_pickup set address=trim(p_listing->>'address'),contact=trim(p_listing->>'contact'),instructions=coalesce(p_listing->>'instructions','') where listing_id=p_id;
 select jsonb_build_object('listing',to_jsonb(x),'pickup',(select to_jsonb(y) from public.saveat_pickup y where y.listing_id=p_id),'items',(select jsonb_agg(to_jsonb(z) order by z.id) from public.saveat_items z where z.listing_id=p_id)) into after_state from public.saveat_listings x where x.id=p_id;
 changes:=public.saveat_listing_changes(before_state,after_state);
 if changes<>'' then
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message)
 select r.customer_id,r.id,'listing_changed','Annuncio aggiornato: controlla il tuo ritiro','Modifiche a «'||trim(p_listing->>'title')||'»:'||changes||E'\nIl prezzo della tua prenotazione resta quello concordato.' from public.saveat_reservations r where r.listing_id=p_id and r.status in ('reserved','confirmed')
 on conflict(reservation_id,kind) do update set title=excluded.title,message=excluded.message,created_at=now(),read_at=null;
 end if;
end;$$;
commit;
