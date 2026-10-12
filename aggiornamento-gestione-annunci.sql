begin;
create or replace function public.saveat_update_listing(p_id uuid,p_listing jsonb,p_items jsonb default null) returns void language plpgsql security definer set search_path='' as $$
declare l public.saveat_listings;p public.saveat_pickup;i public.saveat_items;j jsonb;locked boolean;ended boolean;s timestamptz;e timestamptz;q numeric;v_price numeric;
begin
 select * into l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or l.owner_id is distinct from auth.uid() then raise exception 'Puoi modificare solo i tuoi annunci';end if;
 select * into p from public.saveat_pickup where listing_id=p_id;
 ended:=l.status<>'active' or l.pickup_end<=now();
 locked:=exists(select 1 from public.saveat_reservations where listing_id=p_id and (status='collected' or (status in ('reserved','confirmed') and (customer_collected_at is not null or l.pickup_end>now()))));
 update public.saveat_listings set title=trim(p_listing->>'title'),description=coalesce(p_listing->>'description','') where id=p_id;
 if p_items is null then return;end if;
 if ended then raise exception 'Annuncio terminato: puoi modificare titolo e descrizione';end if;
 s:=(p_listing->>'pickup_start')::timestamptz;e:=(p_listing->>'pickup_end')::timestamptz;
 if locked and (s is distinct from l.pickup_start or e is distinct from l.pickup_end or p_listing->>'municipality_code' is distinct from l.municipality_code or p_listing->>'address' is distinct from p.address or p_listing->>'contact' is distinct from p.contact or coalesce(p_listing->>'instructions','') is distinct from p.instructions) then raise exception 'Ci sono ritiri prenotati: luogo, orari e contatto non si possono cambiare. Per indisponibilità annulla l’annuncio';end if;
 if s is null or e is null or e<=now() or e<=s or e>now()+interval '30 days' then raise exception 'Fascia di ritiro non valida (massimo30 giorni)';end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)<>(select count(*) from public.saveat_items where listing_id=p_id) or exists(select 1 from jsonb_array_elements(p_items) x group by x->>'id' having count(*)>1) then raise exception 'Elenco alimenti non valido';end if;
 for j in select value from jsonb_array_elements(p_items) loop
 select * into i from public.saveat_items where id=(j->>'id')::uuid and listing_id=p_id for update;
 if not found then raise exception 'Alimento non accessibile';end if;
 q:=(j->>'quantity')::numeric;v_price:=(j->>'price')::numeric;
 if q is null or v_price is null or q<=0 or q<>round(q,3) or v_price<>round(v_price,2) or q<i.quantity-i.available then raise exception 'Quantità non valida: conserva le unità già prenotate o ritirate';end if;
 if j->>'unit' in ('pezzi','confezioni') and q<>trunc(q) then raise exception 'Usa quantità intere';end if;
 if exists(select 1 from public.saveat_reservation_items where item_id=i.id) and (trim(j->>'name') is distinct from i.name or j->>'unit' is distinct from i.unit or v_price is distinct from i.price) then raise exception 'Alimento già prenotato: nome, unità e prezzo non si possono cambiare';end if;
 if i.date_type='use_by' and i.label_date<(e at time zone 'Europe/Rome')::date then raise exception 'Il ritiro deve avvenire entro la scadenza del cibo';end if;
 update public.saveat_items set name=trim(j->>'name'),unit=j->>'unit',quantity=q,available=i.available+q-i.quantity,price=v_price where id=i.id;
 end loop;
 update public.saveat_listings set municipality_code=p_listing->>'municipality_code',pickup_start=s,pickup_end=e where id=p_id;
 update public.saveat_pickup set address=trim(p_listing->>'address'),contact=trim(p_listing->>'contact'),instructions=coalesce(p_listing->>'instructions','') where listing_id=p_id;
end;$$;
revoke all on function public.saveat_update_listing(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.saveat_update_listing(uuid,jsonb,jsonb) to authenticated;

alter table public.saveat_reservations add column if not exists listing_snapshot jsonb not null default '{}'::jsonb;
alter table public.saveat_reservations alter column listing_id drop not null;
alter table public.saveat_reservations drop constraint if exists saveat_reservations_listing_id_fkey;
alter table public.saveat_reservations add constraint saveat_reservations_listing_id_fkey foreign key(listing_id) references public.saveat_listings(id) on delete set null;
alter table public.saveat_reservation_items add column if not exists snapshot_id uuid not null default gen_random_uuid();
alter table public.saveat_reservation_items drop constraint if exists saveat_reservation_items_pkey;
alter table public.saveat_reservation_items add primary key(snapshot_id);
alter table public.saveat_reservation_items alter column item_id drop not null;
create unique index if not exists saveat_reservation_item_unique on public.saveat_reservation_items(reservation_id,item_id);
alter table public.saveat_reservation_items drop constraint if exists saveat_reservation_items_item_id_fkey;
alter table public.saveat_reservation_items add constraint saveat_reservation_items_item_id_fkey foreign key(item_id) references public.saveat_items(id) on delete set null;
create or replace function public.saveat_delete_listing(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare l public.saveat_listings;
begin
 select * into l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or l.owner_id is distinct from auth.uid() then raise exception 'Puoi eliminare solo i tuoi annunci';end if;
 if exists(select 1 from public.saveat_reservations where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is not null) then raise exception 'Conferma prima i ritiri già segnalati dai clienti';end if;
 perform public.saveat_close_listing(p_id);
 update public.saveat_reservations set listing_snapshot=jsonb_build_object('title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,'pickup_start',l.pickup_start,'pickup_end',l.pickup_end) where listing_id=p_id;
 delete from public.saveat_pickup where listing_id=p_id;
 delete from public.saveat_items where listing_id=p_id;
 delete from public.saveat_listings where id=p_id;
end;$$;
revoke all on function public.saveat_delete_listing(uuid) from public,anon,authenticated;
grant execute on function public.saveat_delete_listing(uuid) to authenticated;
create or replace function public.saveat_my_reservations() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',r.id,'cancellation_reason',r.cancellation_reason,'status',case when r.status in ('reserved','confirmed') and r.customer_collected_at is null and l.pickup_end<=now() then 'expired' else r.status end,
 'customer_name',case when l.owner_id=auth.uid() then coalesce(nullif(trim(c.display_name),''),'Utente Saveat') else null end,'customer_collected_at',r.customer_collected_at,'listing_status',l.status,'listing_deleted',l.id is null,'listing_id',l.id,'title',coalesce(l.title,r.listing_snapshot->>'title'),'owner_id',coalesce(l.owner_id,(r.listing_snapshot->>'owner_id')::uuid),'seller_name',coalesce(l.seller_name,r.listing_snapshot->>'seller_name'),
 'pickup_start',coalesce(l.pickup_start,(r.listing_snapshot->>'pickup_start')::timestamptz),'pickup_end',coalesce(l.pickup_end,(r.listing_snapshot->>'pickup_end')::timestamptz),'created_at',r.created_at,
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r left join public.saveat_listings l on l.id=r.listing_id join public.saveat_profiles c on c.id=r.customer_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$$;



alter table public.saveat_reservations alter column status set default 'confirmed';
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
  if v_qty is null or v_qty<=0 or v_qty<>round(v_qty,3) or v_qty>v_item.available then raise exception 'Quantità non disponibile'; end if;
  if v_item.unit in ('pezzi','confezioni') and v_qty<>trunc(v_qty) then raise exception 'Usa quantità intere'; end if;
  update public.saveat_items set available=available-v_qty where id=v_item.id;
  insert into public.saveat_reservation_items values(v_id,v_item.id,v_item.name,v_item.unit,v_qty,v_item.price);
 end loop;
 return v_id;
end; $$;


update public.saveat_reservations r set status='confirmed',updated_at=now() where r.status='reserved' and exists(select 1 from public.saveat_listings l where l.id=r.listing_id and (l.pickup_end>now() or r.customer_collected_at is not null));

commit;
