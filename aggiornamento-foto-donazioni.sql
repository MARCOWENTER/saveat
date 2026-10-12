begin;
-- Conserva le condizioni del ritiro anche quando il residuo viene rimesso online.
update public.saveat_reservations r set listing_snapshot=jsonb_build_object('title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,'pickup_start',l.pickup_start,'pickup_end',l.pickup_end) from public.saveat_listings l where l.id=r.listing_id and (r.listing_snapshot is null or r.listing_snapshot='{}'::jsonb);
create or replace function public.saveat_snapshot_reservation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select jsonb_build_object('title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,'pickup_start',l.pickup_start,'pickup_end',l.pickup_end) into new.listing_snapshot from public.saveat_listings l where l.id=new.listing_id;
 return new;
end;$$;
revoke all on function public.saveat_snapshot_reservation() from public,anon,authenticated;
drop trigger if exists saveat_snapshot_reservation on public.saveat_reservations;
create trigger saveat_snapshot_reservation before insert on public.saveat_reservations for each row execute function public.saveat_snapshot_reservation();
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
 update public.saveat_items set name=trim(j->>'name'),unit=j->>'unit',quantity=q,available=q-committed,price=v_price,photo_path=photo where id=i.id;
 end loop;
 update public.saveat_listings set municipality_code=p_listing->>'municipality_code',pickup_start=s,pickup_end=e where id=p_id;
 update public.saveat_pickup set address=trim(p_listing->>'address'),contact=trim(p_listing->>'contact'),instructions=coalesce(p_listing->>'instructions','') where listing_id=p_id;
end;$$;
revoke all on function public.saveat_update_listing(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.saveat_update_listing(uuid,jsonb,jsonb) to authenticated;
create or replace function public.saveat_delete_listing(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare l public.saveat_listings;
begin
 select * into l from public.saveat_listings where id=p_id for update;
 if auth.uid() is null or l.owner_id is distinct from auth.uid() then raise exception 'Puoi eliminare solo i tuoi annunci';end if;
 if exists(select 1 from public.saveat_reservations where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is not null) then raise exception 'Conferma prima i ritiri già segnalati dai clienti';end if;
 perform public.saveat_close_listing(p_id);
 update public.saveat_reservations set listing_snapshot=coalesce(nullif(listing_snapshot,'{}'::jsonb),jsonb_build_object('title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,'pickup_start',l.pickup_start,'pickup_end',l.pickup_end)) where listing_id=p_id;
 delete from public.saveat_pickup where listing_id=p_id;
 delete from public.saveat_items where listing_id=p_id;
 delete from public.saveat_listings where id=p_id;
end;$$;
revoke all on function public.saveat_delete_listing(uuid) from public,anon,authenticated;
grant execute on function public.saveat_delete_listing(uuid) to authenticated;
create or replace function public.saveat_my_reservations() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',r.id,'cancellation_reason',r.cancellation_reason,'status',case when r.status in ('reserved','confirmed') and r.customer_collected_at is null and coalesce((r.listing_snapshot->>'pickup_end')::timestamptz,l.pickup_end)<=now() then 'expired' else r.status end,
 'customer_name',case when l.owner_id=auth.uid() then coalesce(nullif(trim(c.display_name),''),'Utente Saveat') else null end,'customer_collected_at',r.customer_collected_at,'listing_status',l.status,'listing_deleted',l.id is null,'listing_id',l.id,'title',coalesce(l.title,r.listing_snapshot->>'title'),'owner_id',coalesce(l.owner_id,(r.listing_snapshot->>'owner_id')::uuid),'seller_name',coalesce(l.seller_name,r.listing_snapshot->>'seller_name'),
 'pickup_start',coalesce((r.listing_snapshot->>'pickup_start')::timestamptz,l.pickup_start),'pickup_end',coalesce((r.listing_snapshot->>'pickup_end')::timestamptz,l.pickup_end),'created_at',r.created_at,
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r left join public.saveat_listings l on l.id=r.listing_id join public.saveat_profiles c on c.id=r.customer_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$$;



commit;
