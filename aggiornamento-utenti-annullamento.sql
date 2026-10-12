begin;
create or replace function public.saveat_close_listing(p_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_l public.saveat_listings;
begin
 select * into v_l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or v_l.owner_id is distinct from auth.uid() then raise exception 'Annuncio non accessibile'; end if;
 -- Cancella le prenotazioni attive e ripristina una sola volta le quantità.
 update public.saveat_items i set available=i.available+q.qty from (
  select ri.item_id,sum(ri.quantity) qty from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id
  where r.listing_id=p_id and r.status in ('reserved','confirmed') and r.customer_collected_at is null group by ri.item_id
 ) q where i.id=q.item_id;
 update public.saveat_reservations set status=case when v_l.pickup_end<=now() then 'expired' else 'cancelled' end,updated_at=now() where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is null;
 update public.saveat_listings set status='closed' where id=p_id;
end; $$;

create or replace function public.saveat_my_reservations() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',r.id,'status',case when r.status in ('reserved','confirmed') and r.customer_collected_at is null and l.pickup_end<=now() then 'expired' else r.status end,
 'customer_name',case when l.owner_id=auth.uid() then coalesce(nullif(trim(c.display_name),''),'Utente Saveat') else null end,'customer_collected_at',r.customer_collected_at,'listing_id',l.id,'title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,
 'pickup_start',l.pickup_start,'pickup_end',l.pickup_end,'created_at',r.created_at,
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r join public.saveat_listings l on l.id=r.listing_id join public.saveat_profiles c on c.id=r.customer_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$$;
commit;
