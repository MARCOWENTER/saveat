-- Saveat: targeted additive migration, 15 October 2026. Do not rerun supabase.sql.
begin;
set local lock_timeout='5s';
create or replace function public.saveat_guard_business_contact() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.saveat_listings where id=new.listing_id and account_type='business') then new.contact:='Ritiro tramite Saveat: segui le istruzioni e mostra la prenotazione al punto di ritiro.';end if;
 return new;
end;$$;
revoke all on function public.saveat_guard_business_contact() from public,anon,authenticated;
drop trigger if exists saveat_business_contact on public.saveat_pickup;
create trigger saveat_business_contact before insert or update of contact on public.saveat_pickup for each row execute function public.saveat_guard_business_contact();
-- Keep historical data. Owners can still read their raw record; customers get a safe RPC projection.
drop policy if exists saveat_pickup_read on public.saveat_pickup;
create policy saveat_pickup_read on public.saveat_pickup for select to authenticated using(public.saveat_owns_listing(listing_id) or exists(
 select 1 from public.saveat_reservations r join public.saveat_listings l on l.id=r.listing_id where r.listing_id=saveat_pickup.listing_id and l.account_type='private' and r.customer_id=(select auth.uid()) and r.status in ('reserved','confirmed') and l.pickup_end>now()));

alter table public.saveat_reservations add column if not exists completed_at timestamptz;
alter table public.saveat_reservations add column if not exists completion_time_estimated boolean not null default false;
update public.saveat_reservations set completed_at=updated_at,completion_time_estimated=true where status='collected' and completed_at is null;
create index if not exists saveat_reservation_completed_date on public.saveat_reservations(completed_at) where status='collected';
create or replace function public.saveat_stamp_completion() returns trigger language plpgsql set search_path='' as $$
begin if new.status='collected' and old.status is distinct from 'collected' then new.completed_at:=now();new.completion_time_estimated:=false;end if;return new;end;$$;
revoke all on function public.saveat_stamp_completion() from public,anon,authenticated;
drop trigger if exists saveat_completed_at on public.saveat_reservations;
create trigger saveat_completed_at before update of status on public.saveat_reservations for each row execute function public.saveat_stamp_completion();

create table if not exists public.saveat_guidance(
 id uuid primary key default gen_random_uuid(),reservation_id uuid not null references public.saveat_reservations(id),sender_id uuid not null references public.saveat_profiles(id),code text not null check(code in ('pickup_location','food_information','running_late','instructions_updated','pickup_confirmed','pickup_deadline')),created_at timestamptz not null default now(),unique(reservation_id,sender_id,code));
alter table public.saveat_guidance enable row level security;
revoke all on public.saveat_guidance from public,anon,authenticated;
-- Messages are read through the participant-checked reservation RPC only.
create or replace function public.saveat_guidance_text(p_code text) returns text language sql immutable set search_path='' as $$
 select case p_code when 'pickup_location' then 'Non trovo il punto di ritiro: controlla e chiarisci le istruzioni in Saveat.'
when 'food_information' then 'Ho bisogno di chiarimenti su contenuto o allergeni: aggiorna i dettagli in Saveat prima del ritiro.'
when 'running_late' then 'Segnalo un ritardo. La fascia di ritiro resta quella indicata finché non ricevo conferma.'
when 'instructions_updated' then 'Ho controllato e aggiornato le istruzioni o i dettagli: rileggi la prenotazione in Saveat.'
when 'pickup_confirmed' then 'Confermo il ritiro nella fascia indicata nella prenotazione.'
when 'pickup_deadline' then 'Non posso garantire il ritiro oltre il termine indicato. Gestisci la prenotazione prima di partire.' else null end;
$$;
revoke all on function public.saveat_guidance_text(text) from public,anon,authenticated;
-- Internal helper, only called by SECURITY DEFINER functions.
alter table public.saveat_notifications drop constraint if exists saveat_notifications_kind_check;
alter table public.saveat_notifications add constraint saveat_notifications_kind_check check(kind in ('owner_unavailable','listing_changed','customer_cancelled','reservation_received','guide_customer_pickup_location','guide_customer_food_information','guide_customer_running_late','guide_owner_instructions_updated','guide_owner_pickup_confirmed','guide_owner_pickup_deadline'));
create or replace function public.saveat_send_guidance(p_reservation_id uuid,p_code text) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.saveat_reservations;l public.saveat_listings;g uuid;recipient uuid;v_kind text;v_message text;v_listing uuid;
begin
 if auth.uid() is null then raise exception 'Accedi per continuare';end if;
 select listing_id into v_listing from public.saveat_reservations where id=p_reservation_id;
 select * into l from public.saveat_listings where id=v_listing for update;
 select * into r from public.saveat_reservations where id=p_reservation_id for update;
 if r.id is null or (r.customer_id is distinct from auth.uid() and l.owner_id is distinct from auth.uid()) then raise exception 'Prenotazione non accessibile';end if;
 if r.status not in ('reserved','confirmed') or l.id is null or l.status<>'active' or l.pickup_end<=now() then raise exception 'Comunicazioni disponibili solo per un ritiro attivo';end if;
 if r.customer_id=auth.uid() then
 if p_code is null or p_code not in ('pickup_location','food_information','running_late') then raise exception 'Messaggio non ammesso per chi ritira';end if;
 recipient:=l.owner_id;v_kind:='guide_customer_'||p_code;
 else
 if p_code is null or p_code not in ('instructions_updated','pickup_confirmed','pickup_deadline') then raise exception 'Messaggio non ammesso per chi pubblica';end if;
 recipient:=r.customer_id;v_kind:='guide_owner_'||p_code;
 end if;
 select id into g from public.saveat_guidance where reservation_id=r.id and sender_id=auth.uid() and code=p_code;
 if g is not null then return g;end if;
 insert into public.saveat_guidance(reservation_id,sender_id,code) values(r.id,auth.uid(),p_code) returning id into g;
 v_message:='Prenotazione '||left(r.id::text,8)||' · «'||l.title||'»: '||public.saveat_guidance_text(p_code);
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message) values(recipient,r.id,v_kind,'Messaggio sul ritiro',v_message);
 return g;
end;$$;
revoke all on function public.saveat_send_guidance(uuid,text) from public,anon,authenticated;
grant execute on function public.saveat_send_guidance(uuid,text) to authenticated;

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
 'items',(select coalesce(jsonb_agg(to_jsonb(ri)||jsonb_build_object('current_item',case when r.status in ('reserved','confirmed') then (select jsonb_build_object('name',ci.name,'unit',ci.unit,'date_type',ci.date_type,'label_date',ci.label_date,'allergens',ci.allergens,'container_provided',ci.container_provided) from public.saveat_items ci where ci.id=ri.item_id) else null end)),'[]'::jsonb) from public.saveat_reservation_items ri where ri.reservation_id=r.id),
 'pickup',case when l.owner_id=auth.uid() or (r.customer_id=auth.uid() and r.status in ('reserved','confirmed') and l.pickup_end>now()) then (select to_jsonb(p)||jsonb_build_object('contact',case when l.account_type='business' then 'Ritiro tramite Saveat: segui le istruzioni e mostra la prenotazione al punto di ritiro.' else p.contact end) from public.saveat_pickup p where p.listing_id=l.id) else null end
 ) order by r.created_at desc),'[]'::jsonb)
 from public.saveat_reservations r left join public.saveat_listings l on l.id=r.listing_id join public.saveat_profiles c on c.id=r.customer_id
 where auth.uid() is not null and (r.customer_id=auth.uid() or l.owner_id=auth.uid());
$function$;
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
 update public.saveat_items set name=trim(j->>'name'),unit=j->>'unit',quantity=q,available=q-committed,price=v_price,photo_path=photo,date_type=dtype,label_date=ldate,allergens=case when j ? 'allergens' then coalesce(j->>'allergens','') else i.allergens end,unit_weight_kg=case when j ? 'unit_weight_kg' then nullif(j->>'unit_weight_kg','')::numeric else i.unit_weight_kg end,container_provided=case when j->>'unit'='confezioni' then true when j ? 'container_provided' then coalesce((j->>'container_provided')::boolean,false) else i.container_provided end where id=i.id;
 end loop;
 update public.saveat_listings set municipality_code=p_listing->>'municipality_code',pickup_start=s,pickup_end=e,payment_methods=public.saveat_payment_methods(p_listing,exists(select 1 from public.saveat_items where listing_id=p_id and price>0),l.payment_methods) where id=p_id;
 update public.saveat_pickup set address=trim(p_listing->>'address'),contact=trim(p_listing->>'contact'),instructions=coalesce(p_listing->>'instructions','') where listing_id=p_id;
 select jsonb_build_object('listing',to_jsonb(x),'pickup',(select to_jsonb(y) from public.saveat_pickup y where y.listing_id=p_id),'items',(select jsonb_agg(to_jsonb(z) order by z.id) from public.saveat_items z where z.listing_id=p_id)) into after_state from public.saveat_listings x where x.id=p_id;
 if l.account_type='business' then before_state:=jsonb_set(before_state,'{pickup,contact}',to_jsonb('Ritiro tramite Saveat: segui le istruzioni e mostra la prenotazione al punto di ritiro.'::text));after_state:=jsonb_set(after_state,'{pickup,contact}',to_jsonb('Ritiro tramite Saveat: segui le istruzioni e mostra la prenotazione al punto di ritiro.'::text));end if;
 changes:=public.saveat_listing_changes(before_state,after_state);
 if changes<>'' then
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message)
 select r.customer_id,r.id,'listing_changed','Annuncio aggiornato: controlla il tuo ritiro','Modifiche a «'||trim(p_listing->>'title')||'»:'||changes||E'\nIl prezzo della tua prenotazione resta quello concordato.' from public.saveat_reservations r where r.listing_id=p_id and r.status in ('reserved','confirmed')
 on conflict(reservation_id,kind) do update set title=excluded.title,message=excluded.message,created_at=now(),read_at=null;
 end if;
end;$function$;

create or replace function public.saveat_my_report(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null then raise exception 'Accedi per vedere il resoconto';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>365 then raise exception 'Scegli un periodo fino a 366 giorni';end if;
 select coalesce(jsonb_agg(jsonb_build_object('reservation_id',r.id,'completed_at',r.completed_at,'completion_time_estimated',r.completion_time_estimated,'role',case when coalesce(l.owner_id,(r.listing_snapshot->>'owner_id')::uuid)=auth.uid() then 'owner' else 'customer' end,'title',coalesce(l.title,r.listing_snapshot->>'title'),'name',ri.name,'quantity',ri.quantity,'unit',ri.unit,'price',ri.price,'total',ri.quantity*ri.price,'saved_kg',ri.quantity*coalesce(ri.saved_unit_kg,case when ri.unit in ('kg','litri') then 1 else 0.5 end),'weight_source',coalesce(ri.weight_source,'stima_standard')) order by r.completed_at,r.id,ri.name),'[]'::jsonb) into result
 from public.saveat_reservations r left join public.saveat_listings l on l.id=r.listing_id join public.saveat_reservation_items ri on ri.reservation_id=r.id
 where r.status='collected' and r.completed_at>=(p_from::timestamp at time zone 'Europe/Rome') and r.completed_at<((p_to+1)::timestamp at time zone 'Europe/Rome') and (r.customer_id=auth.uid() or coalesce(l.owner_id,(r.listing_snapshot->>'owner_id')::uuid)=auth.uid());
 return result;
end;$$;
revoke all on function public.saveat_my_report(date,date) from public,anon,authenticated;
grant execute on function public.saveat_my_report(date,date) to authenticated;
notify pgrst,'reload schema';
commit;
