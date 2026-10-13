begin;
alter table public.saveat_listings add column if not exists payment_methods text[];
alter table public.saveat_reservation_items add column if not exists inventory_quantity numeric;
update public.saveat_reservation_items set inventory_quantity=quantity where inventory_quantity is null;
alter table public.saveat_reservation_items alter column inventory_quantity set not null;
alter table public.saveat_reservation_items drop constraint if exists saveat_inventory_quantity_check;
alter table public.saveat_reservation_items add constraint saveat_inventory_quantity_check check(inventory_quantity>0 and inventory_quantity=round(inventory_quantity,3));
create or replace function public.saveat_snapshot_inventory() returns trigger language plpgsql security definer set search_path='' as $$
begin new.inventory_quantity:=new.quantity;return new;end;$$;
revoke all on function public.saveat_snapshot_inventory() from public,anon,authenticated;
drop trigger if exists saveat_snapshot_inventory on public.saveat_reservation_items;
create trigger saveat_snapshot_inventory before insert on public.saveat_reservation_items for each row execute function public.saveat_snapshot_inventory();
create or replace function public.saveat_payment_methods(p_listing jsonb,p_selling boolean,p_current text[] default null) returns text[] language plpgsql set search_path='' as $$
declare methods text[];
begin
 if not (p_listing ? 'payment_methods') then return p_current;end if;
 if jsonb_typeof(p_listing->'payment_methods')<>'array' then raise exception 'Metodi di pagamento non validi';end if;
 select array_agg(distinct value) into methods from jsonb_array_elements_text(p_listing->'payment_methods');
 if exists(select 1 from unnest(methods) m where m not in ('cash','card','satispay')) then raise exception 'Metodo di pagamento non valido';end if;
 if p_selling and coalesce(cardinality(methods),0)=0 then raise exception 'Seleziona almeno un metodo di pagamento';end if;
 return coalesce(methods,array[]::text[]);
end;$$;
revoke all on function public.saveat_payment_methods(jsonb,boolean,text[]) from public,anon,authenticated;
alter table public.saveat_notifications drop constraint if exists saveat_notifications_kind_check;
alter table public.saveat_notifications add constraint saveat_notifications_kind_check check(kind in ('owner_unavailable','listing_changed'));
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
 update public.saveat_listings set payment_methods=public.saveat_payment_methods(p_listing,exists(select 1 from public.saveat_items where listing_id=v_id and price>0)) where id=v_id; return v_id;
end; $$;
create or replace function public.saveat_snapshot_reservation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select jsonb_build_object('title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,'description',l.description,'pickup_start',l.pickup_start,'pickup_end',l.pickup_end,'payment_methods',l.payment_methods) into new.listing_snapshot from public.saveat_listings l where l.id=new.listing_id;
 return new;
end;$$;
create or replace function public.saveat_transition(p_id uuid,p_status text) returns text
language plpgsql security definer set search_path='' as $$
declare v_r public.saveat_reservations; v_l public.saveat_listings; v_listing_id uuid;
begin
 if auth.uid() is null then raise exception 'Accedi per continuare'; end if;
 select listing_id into v_listing_id from public.saveat_reservations where id=p_id;
 select * into v_l from public.saveat_listings where id=v_listing_id for update;
 select * into v_r from public.saveat_reservations where id=p_id for update;
 if v_r.id is null or (v_r.customer_id<>auth.uid() and v_l.owner_id<>auth.uid()) then raise exception 'Prenotazione non accessibile'; end if;
 if v_r.status in ('reserved','confirmed') and v_r.customer_collected_at is null and v_l.pickup_end<=now() then
  update public.saveat_reservations set status='expired',updated_at=now() where id=p_id;
  return 'expired';
 end if;
 if v_r.status=p_status then return p_status; end if;
 if v_r.status not in ('reserved','confirmed') then raise exception 'Prenotazione già conclusa'; end if;
 if p_status='confirmed' then
  if v_l.owner_id<>auth.uid() or v_r.status<>'reserved' then raise exception 'Solo chi pubblica può confermare'; end if;
 elsif p_status='collected' then
  if v_l.owner_id<>auth.uid() or now()<v_l.pickup_start then raise exception 'Il ritiro va confermato da chi pubblica durante la fascia di ritiro'; end if;
 elsif p_status='cancelled' then
  if v_r.customer_collected_at is not null then raise exception 'Ritiro già segnalato: chi pubblica deve confermarlo'; end if;
  update public.saveat_items i set available=i.available+ri.inventory_quantity from public.saveat_reservation_items ri where ri.reservation_id=p_id and ri.item_id=i.id;
 else raise exception 'Transizione non ammessa';
 end if;
 update public.saveat_reservations set status=p_status,cancellation_reason=case when p_status='cancelled' then case when v_l.owner_id=auth.uid() then 'owner_unavailable' else 'customer_cancelled' end else cancellation_reason end,updated_at=now() where id=p_id;
 return p_status;
end; $$;
create or replace function public.saveat_close_listing(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_l public.saveat_listings;
begin
 select * into v_l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or v_l.owner_id is distinct from auth.uid() then raise exception 'Annuncio non accessibile'; end if;
 -- Cancella le prenotazioni attive e ripristina una sola volta le quantità.
 update public.saveat_items i set available=i.available+q.qty from (
  select ri.item_id,sum(ri.inventory_quantity) qty from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id
  where r.listing_id=p_id and r.status in ('reserved','confirmed') and r.customer_collected_at is null group by ri.item_id
 ) q where i.id=q.item_id;
 update public.saveat_reservations set status='cancelled',cancellation_reason='owner_unavailable',updated_at=now() where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is null;
 update public.saveat_listings set status='closed' where id=p_id;
end; $$;
create or replace function public.saveat_update_listing(p_id uuid,p_listing jsonb,p_items jsonb default null) returns void language plpgsql security definer set search_path='' as $$
declare l public.saveat_listings;p public.saveat_pickup;i public.saveat_items;j jsonb;s timestamptz;e timestamptz;q numeric;v_price numeric;committed numeric;photo text;factor numeric;dtype text;ldate date;before_state jsonb;after_state jsonb;
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
 if q is null or v_price is null or q<=0 or q<>round(q,3) or v_price<>round(v_price,2) or q<committed then raise exception 'Quantità non valida: conserva le quantità già prenotate o consegnate';end if;
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
 if before_state is distinct from after_state then
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message)
 select r.customer_id,r.id,'listing_changed','Annuncio aggiornato: controlla il tuo ritiro','Chi pubblica ha corretto «'||trim(p_listing->>'title')||'». Controlla descrizione, alimenti, luogo, orari e metodi di pagamento prima del ritiro. Il prezzo della tua prenotazione resta quello concordato.' from public.saveat_reservations r where r.listing_id=p_id and r.status in ('reserved','confirmed')
 on conflict(reservation_id,kind) do update set title=excluded.title,message=excluded.message,created_at=now(),read_at=null;
 end if;
end;$$;

create or replace function public.saveat_my_reservations() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',r.id,'cancellation_reason',r.cancellation_reason,'status',case when r.status in ('reserved','confirmed') and r.customer_collected_at is null and l.pickup_end<=now() then 'expired' else r.status end,
 'customer_name',case when l.owner_id=auth.uid() then coalesce(nullif(trim(c.display_name),''),'Utente Saveat') else null end,'customer_collected_at',r.customer_collected_at,'listing_status',l.status,'listing_deleted',l.id is null,'listing_id',l.id,'title',coalesce(l.title,r.listing_snapshot->>'title'),'description',coalesce(l.description,r.listing_snapshot->>'description'),'owner_id',coalesce(l.owner_id,(r.listing_snapshot->>'owner_id')::uuid),'seller_name',coalesce(l.seller_name,r.listing_snapshot->>'seller_name'),
 'pickup_start',case when r.status in ('reserved','confirmed') then l.pickup_start else coalesce((r.listing_snapshot->>'pickup_start')::timestamptz,l.pickup_start) end,'pickup_end',case when r.status in ('reserved','confirmed') then l.pickup_end else coalesce((r.listing_snapshot->>'pickup_end')::timestamptz,l.pickup_end) end,'payment_methods',case when r.status in ('reserved','confirmed') then to_jsonb(l.payment_methods) else r.listing_snapshot->'payment_methods' end,'created_at',r.created_at,
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)||jsonb_build_object('current_item',case when r.status in ('reserved','confirmed') then (select jsonb_build_object('name',ci.name,'unit',ci.unit,'date_type',ci.date_type,'label_date',ci.label_date,'allergens',ci.allergens,'container_provided',ci.container_provided) from public.saveat_items ci where ci.id=ri.item_id) else null end)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r left join public.saveat_listings l on l.id=r.listing_id join public.saveat_profiles c on c.id=r.customer_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$$;
commit;
