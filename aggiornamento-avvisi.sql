begin;
alter table public.saveat_reservations add column if not exists cancellation_reason text check(cancellation_reason in ('owner_unavailable','customer_cancelled'));
create table if not exists public.saveat_notifications(
 id uuid primary key default gen_random_uuid(),user_id uuid not null references public.saveat_profiles(id),reservation_id uuid not null references public.saveat_reservations(id),kind text not null check(kind='owner_unavailable'),title text not null,message text not null,created_at timestamptz not null default now(),read_at timestamptz,unique(reservation_id,kind));
alter table public.saveat_notifications enable row level security;
revoke all on public.saveat_notifications from anon,authenticated;
grant select on public.saveat_notifications to authenticated;
drop policy if exists saveat_notification_read on public.saveat_notifications;
create policy saveat_notification_read on public.saveat_notifications for select to authenticated using(user_id=(select auth.uid()));
create table if not exists public.saveat_notification_outbox(
 id uuid primary key references public.saveat_notifications(id),user_id uuid not null references public.saveat_profiles(id),recipient_email text,subject text not null,message text not null,created_at timestamptz not null default now(),email_sent_at timestamptz,push_sent_at timestamptz,attempts integer not null default 0,last_error text,locked_until timestamptz);
alter table public.saveat_notification_outbox enable row level security;
revoke all on public.saveat_notification_outbox from public,anon,authenticated;
create or replace function public.saveat_notify_unavailable() returns trigger language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_title text;v_message text;
begin
 if new.status='cancelled' and new.cancellation_reason='owner_unavailable' and old.status in ('reserved','confirmed') then
  select title into v_title from public.saveat_listings where id=new.listing_id;
  v_message:='Il cibo di «'||v_title||'» non è più disponibile. Chi pubblica ha annullato il ritiro. Non recarti al punto di incontro.';
  insert into public.saveat_notifications(user_id,reservation_id,kind,title,message) values(new.customer_id,new.id,'owner_unavailable','Ritiro annullato: cibo non disponibile',v_message) on conflict(reservation_id,kind) do nothing returning id into v_id;
  if v_id is not null then insert into public.saveat_notification_outbox(id,user_id,recipient_email,subject,message) select v_id,new.customer_id,u.email,'Saveat — ritiro annullato',v_message from auth.users u where u.id=new.customer_id;end if;
 end if;return new;
end;$$;
revoke all on function public.saveat_notify_unavailable() from public,anon,authenticated;
drop trigger if exists saveat_unavailable on public.saveat_reservations;
create trigger saveat_unavailable after update of status on public.saveat_reservations for each row execute function public.saveat_notify_unavailable();
create or replace function public.saveat_read_notification(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Accedi per continuare';end if;
 update public.saveat_notifications set read_at=coalesce(read_at,now()) where id=p_id and user_id=auth.uid();
 if not found then raise exception 'Avviso non accessibile';end if;
end;$$;
revoke all on function public.saveat_read_notification(uuid) from public,anon,authenticated;
grant execute on function public.saveat_read_notification(uuid) to authenticated;
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
  select ri.item_id,sum(ri.quantity) qty from public.saveat_reservation_items ri join public.saveat_reservations r on r.id=ri.reservation_id
  where r.listing_id=p_id and r.status in ('reserved','confirmed') and r.customer_collected_at is null group by ri.item_id
 ) q where i.id=q.item_id;
 update public.saveat_reservations set status='cancelled',cancellation_reason='owner_unavailable',updated_at=now() where listing_id=p_id and status in ('reserved','confirmed') and customer_collected_at is null;
 update public.saveat_listings set status='closed' where id=p_id;
end; $$;

create or replace function public.saveat_my_reservations() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',r.id,'cancellation_reason',r.cancellation_reason,'status',case when r.status in ('reserved','confirmed') and r.customer_collected_at is null and l.pickup_end<=now() then 'expired' else r.status end,
 'customer_name',case when l.owner_id=auth.uid() then coalesce(nullif(trim(c.display_name),''),'Utente Saveat') else null end,'customer_collected_at',r.customer_collected_at,'listing_id',l.id,'title',l.title,'owner_id',l.owner_id,'seller_name',l.seller_name,
 'pickup_start',l.pickup_start,'pickup_end',l.pickup_end,'created_at',r.created_at,
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r join public.saveat_listings l on l.id=r.listing_id join public.saveat_profiles c on c.id=r.customer_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$$;

commit;
