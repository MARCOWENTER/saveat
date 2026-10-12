begin;
alter table public.saveat_reservations add column if not exists customer_collected_at timestamptz;
create or replace function public.saveat_report_collection(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_r public.saveat_reservations; v_l public.saveat_listings; v_listing_id uuid;
begin
 if auth.uid() is null then raise exception 'Accedi per continuare'; end if;
 select listing_id into v_listing_id from public.saveat_reservations where id=p_id;
 select * into v_l from public.saveat_listings where id=v_listing_id for update;
 select * into v_r from public.saveat_reservations where id=p_id for update;
 if v_r.id is null or v_r.customer_id is distinct from auth.uid() then raise exception 'Solo chi prenota può segnalare il ritiro'; end if;
 if v_r.status not in ('reserved','confirmed') then raise exception 'Prenotazione già conclusa'; end if;
 if v_r.customer_collected_at is not null then return; end if;
 if now()<v_l.pickup_start or now()>=v_l.pickup_end then raise exception 'Segnala il ritiro durante la fascia prevista'; end if;
 update public.saveat_reservations set customer_collected_at=now(),updated_at=now() where id=p_id;
end; $$;

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
  update public.saveat_items i set available=i.available+ri.quantity from public.saveat_reservation_items ri where ri.reservation_id=p_id and ri.item_id=i.id;
 else raise exception 'Transizione non ammessa';
 end if;
 update public.saveat_reservations set status=p_status,updated_at=now() where id=p_id;
 return p_status;
end; $$;

create or replace function public.saveat_close_listing(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_l public.saveat_listings;
begin
 select * into v_l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or v_l.owner_id is distinct from auth.uid() then raise exception 'Annuncio non accessibile'; end if;
 if exists(select 1 from public.saveat_reservations where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is not null) then raise exception 'Conferma prima i ritiri segnalati'; end if;
 if exists(select 1 from public.saveat_reservations where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is not null) then raise exception 'Conferma prima i ritiri segnalati'; end if;
 -- Cancella le prenotazioni attive e ripristina una sola volta le quantità.
 update public.saveat_items i set available=i.available+q.qty from (
  select ri.item_id,sum(ri.quantity) qty from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id
  where r.listing_id=p_id and r.status in ('reserved','confirmed') group by ri.item_id
 ) q where i.id=q.item_id;
 update public.saveat_reservations set status=case when v_l.pickup_end<=now() then 'expired' else 'cancelled' end,updated_at=now() where listing_id=p_id and status in ('reserved','confirmed');
 update public.saveat_listings set status='closed' where id=p_id;
end; $$;

create or replace function public.saveat_my_reservations() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',r.id,'status',case when r.status in ('reserved','confirmed') and r.customer_collected_at is null and l.pickup_end<=now() then 'expired' else r.status end,
 'customer_collected_at',r.customer_collected_at,'listing_id',l.id,'title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,
 'pickup_start',l.pickup_start,'pickup_end',l.pickup_end,'created_at',r.created_at,
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r join public.saveat_listings l on l.id=r.listing_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$$;
revoke all on function public.saveat_report_collection(uuid) from public,anon;
grant execute on function public.saveat_report_collection(uuid) to authenticated;
commit;
