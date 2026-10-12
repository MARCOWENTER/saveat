begin;
-- Le indicazioni dei vecchi annunci/ritiri restano non specificate.
alter table public.saveat_items add column if not exists container_provided boolean;
alter table public.saveat_reservation_items add column if not exists container_provided boolean;
create or replace function public.saveat_snapshot_container() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select i.container_provided into new.container_provided from public.saveat_items i where i.id=new.item_id;
 if not found then raise exception 'Alimento non accessibile';end if;
 return new;
end;$$;
revoke all on function public.saveat_snapshot_container() from public,anon,authenticated;
drop trigger if exists saveat_snapshot_container on public.saveat_reservation_items;
create trigger saveat_snapshot_container before insert on public.saveat_reservation_items for each row execute function public.saveat_snapshot_container();
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
  if v_qty is null or v_qty<=0 or v_qty<>round(v_qty,3) or v_price<>round(v_price,2) then raise exception 'Quantità o prezzo non validi'; end if;
  if v_item->>'unit' in ('pezzi','confezioni') and v_qty<>trunc(v_qty) then raise exception 'Usa quantità intere per pezzi e confezioni'; end if;
  if v_item->>'date_type'='use_by' and (v_item->>'label_date')::date < (v_end at time zone 'Europe/Rome')::date then raise exception 'Il ritiro deve avvenire entro la data di scadenza'; end if;
  if nullif(v_item->>'photo_path','') is not null and not exists(select 1 from storage.objects where bucket_id='saveat-photos' and name=v_item->>'photo_path' and split_part(name,'/',1)=auth.uid()::text) then raise exception 'Foto non valida'; end if;
  insert into public.saveat_items(listing_id,name,unit,quantity,available,price,label_date,date_type,allergens,photo_path,unit_weight_kg,container_provided)
  values(v_id,trim(v_item->>'name'),v_item->>'unit',v_qty,v_qty,v_price,(nullif(v_item->>'label_date',''))::date,v_item->>'date_type',coalesce(v_item->>'allergens',''),nullif(v_item->>'photo_path',''),(nullif(v_item->>'unit_weight_kg',''))::numeric,case when v_item->>'unit'='confezioni' then true else coalesce((v_item->>'container_provided')::boolean,false) end);
 end loop;
 return v_id;
end; $$;
create or replace function public.saveat_update_listing(p_id uuid,p_listing jsonb,p_items jsonb default null) returns void language plpgsql security definer set search_path='' as $$
declare l public.saveat_listings;p public.saveat_pickup;i public.saveat_items;j jsonb;locked boolean;s timestamptz;e timestamptz;q numeric;v_price numeric;committed numeric;photo text;
begin
 select * into l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or l.owner_id is distinct from auth.uid() then raise exception 'Puoi modificare solo i tuoi annunci';end if;
 select * into p from public.saveat_pickup where listing_id=p_id;
 update public.saveat_listings set title=trim(p_listing->>'title'),description=coalesce(p_listing->>'description','') where id=p_id;
 if p_items is null then return;end if;
 if l.status<>'active' then raise exception 'Annuncio annullato: puoi modificare titolo e descrizione';end if;
 if l.pickup_end<=now() then
 update public.saveat_reservations set status='expired',updated_at=now() where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is null;
 end if;
 locked:=exists(select 1 from public.saveat_reservations where listing_id=p_id and status in ('reserved','confirmed'));
 s:=(p_listing->>'pickup_start')::timestamptz;e:=(p_listing->>'pickup_end')::timestamptz;
 if locked and (s is distinct from l.pickup_start or e is distinct from l.pickup_end or p_listing->>'municipality_code' is distinct from l.municipality_code or p_listing->>'address' is distinct from p.address or p_listing->>'contact' is distinct from p.contact or coalesce(p_listing->>'instructions','') is distinct from p.instructions) then raise exception 'Conferma i ritiri segnalati prima di cambiare la fascia. Con prenotazioni attive luogo e orari restano protetti';end if;
 if s is null or e is null or e<=now() or e<=s or e>now()+interval '30 days' then raise exception 'Imposta un nuovo termine di ritiro valido (massimo 30 giorni)';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<>(select count(*) from public.saveat_items where listing_id=p_id) or exists(select 1 from jsonb_array_elements(p_items) x group by x->>'id' having count(*)>1) then raise exception 'Elenco alimenti non valido';end if;
 for j in select value from jsonb_array_elements(p_items) loop
 select * into i from public.saveat_items where id=(j->>'id')::uuid and listing_id=p_id for update;
 if not found then raise exception 'Alimento non accessibile';end if;
 select coalesce(sum(ri.quantity),0) into committed from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id where ri.item_id=i.id and (r.status='collected' or r.status in ('reserved','confirmed'));
 q:=(j->>'quantity')::numeric;v_price:=(j->>'price')::numeric;
 if q is null or v_price is null or q<=0 or q<>round(q,3) or v_price<>round(v_price,2) or q<committed then raise exception 'Quantità non valida: conserva le unità già prenotate o ritirate';end if;
 if j->>'unit' in ('pezzi','confezioni') and q<>trunc(q) then raise exception 'Usa quantità intere';end if;
 if exists(select 1 from public.saveat_reservation_items where item_id=i.id) and (trim(j->>'name') is distinct from i.name or j->>'unit' is distinct from i.unit) then raise exception 'Alimento già prenotato: nome e unità non si possono cambiare';end if;
 if i.date_type='use_by' and i.label_date<(e at time zone 'Europe/Rome')::date then raise exception 'Il ritiro deve avvenire entro la scadenza del cibo';end if;
 photo:=case when j ? 'photo_path' then nullif(j->>'photo_path','') else i.photo_path end;
 if photo is distinct from i.photo_path and photo is not null and (split_part(photo,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='saveat-photos' and name=photo)) then raise exception 'Foto non accessibile';end if;
 update public.saveat_items set name=trim(j->>'name'),unit=j->>'unit',quantity=q,available=q-committed,price=v_price,photo_path=photo,unit_weight_kg=case when j ? 'unit_weight_kg' then (nullif(j->>'unit_weight_kg',''))::numeric else i.unit_weight_kg end,container_provided=case when j->>'unit'='confezioni' then true when j ? 'container_provided' then coalesce((j->>'container_provided')::boolean,false) else i.container_provided end where id=i.id;
 end loop;
 update public.saveat_listings set municipality_code=p_listing->>'municipality_code',pickup_start=s,pickup_end=e where id=p_id;
 update public.saveat_pickup set address=trim(p_listing->>'address'),contact=trim(p_listing->>'contact'),instructions=coalesce(p_listing->>'instructions','') where listing_id=p_id;
end;$$;
commit;
