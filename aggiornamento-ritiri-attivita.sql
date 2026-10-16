-- Saveat: variazione quantità e categoria attività. Migrazione incrementale.
begin;
set local lock_timeout='5s';
alter table public.saveat_reservations add column if not exists quantity_revision integer not null default 0;
alter table public.saveat_profiles add column if not exists business_activity text check(business_activity in ('supermarket','restaurant','greengrocer','farm','bakery','pastry','deli','butcher','fishmonger','bar','hotel','food_shop','other'));
create table if not exists public.saveat_reservation_changes(
 id uuid primary key default gen_random_uuid(),reservation_id uuid not null references public.saveat_reservations(id) on delete cascade,customer_id uuid not null,request_id uuid not null,payload jsonb not null,before_items jsonb not null,after_items jsonb not null,created_at timestamptz not null default now(),unique(customer_id,request_id));
alter table public.saveat_reservation_changes enable row level security;
revoke all on public.saveat_reservation_changes from public,anon,authenticated;
grant select on public.saveat_reservation_changes to authenticated;
do $p$ begin if not exists(select 1 from pg_policies where schemaname='public' and tablename='saveat_reservation_changes' and policyname='saveat_changes_participants') then create policy saveat_changes_participants on public.saveat_reservation_changes for select to authenticated using(exists(select 1 from public.saveat_reservations r left join public.saveat_listings l on l.id=r.listing_id where r.id=reservation_id and (r.customer_id=(select auth.uid()) or l.owner_id=(select auth.uid()))));end if;end $p$;
-- Conserva tutti i tipi di avviso già ammessi e aggiunge la variazione.
do $c$ declare d text;begin select pg_get_constraintdef(oid) into d from pg_constraint where conrelid='public.saveat_notifications'::regclass and conname='saveat_notifications_kind_check';if d is null then raise exception 'Vincolo avvisi mancante';end if;if position('reservation_changed' in d)=0 then execute 'alter table public.saveat_notifications drop constraint saveat_notifications_kind_check';execute 'alter table public.saveat_notifications add constraint saveat_notifications_kind_check '||replace(d,'ARRAY[','ARRAY[''reservation_changed''::text,');end if;end $c$;
create or replace function public.saveat_reservation_edit_context(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.saveat_reservations;l public.saveat_listings;result jsonb;begin
 select * into r from public.saveat_reservations where id=p_id;
 if auth.uid() is null or r.customer_id is distinct from auth.uid() then raise exception 'Puoi modificare solo i tuoi ritiri';end if;
 select * into l from public.saveat_listings where id=r.listing_id;
 if r.status not in ('reserved','confirmed') or r.customer_collected_at is not null or l.id is null or l.status<>'active' or l.pickup_end<=now() then raise exception 'Ritiro non più modificabile';end if;
 select jsonb_build_object('id',r.id,'revision',r.quantity_revision,'items',coalesce(jsonb_agg(jsonb_build_object('snapshot_id',ri.snapshot_id,'name',ri.name,'unit',ri.unit,'quantity',ri.quantity,'price',ri.price,'maximum',greatest(ri.quantity,floor((ri.quantity+ci.available*ri.quantity/nullif(ri.inventory_quantity,0))*case when ri.unit in ('pezzi','confezioni') then 1 else 10 end)/case when ri.unit in ('pezzi','confezioni') then 1 else 10 end),'current_unit',ci.unit) order by ri.snapshot_id),'[]'::jsonb)) into result from public.saveat_reservation_items ri join public.saveat_items ci on ci.id=ri.item_id where ri.reservation_id=p_id;
 return result;
end;$$;
create or replace function public.saveat_change_reservation(p_id uuid,p_items jsonb,p_revision integer,p_request_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare r public.saveat_reservations;l public.saveat_listings;ri public.saveat_reservation_items;ci public.saveat_items;j jsonb;q numeric;inv numeric;delta numeric;old_rows jsonb;new_rows jsonb;prior public.saveat_reservation_changes;change_id uuid;msg text:='';total numeric;previous_total numeric;name_customer text;notice_id uuid;changed boolean:=false;begin
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
 changed:=true;msg:=msg||E'\n'||ri.name||': '||ri.quantity::text||' → '||q::text||' '||ri.unit;
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
end;$$;
revoke all on function public.saveat_reservation_edit_context(uuid),public.saveat_change_reservation(uuid,jsonb,integer,uuid) from public,anon,authenticated;
grant execute on function public.saveat_reservation_edit_context(uuid),public.saveat_change_reservation(uuid,jsonb,integer,uuid) to authenticated;
create or replace function public.saveat_save_profile_activity(p_name text,p_type text,p_business text,p_city text,p_radius integer,p_vat text,p_address text,p_activity text) returns void language plpgsql security definer set search_path='' as $$
begin
 if p_type='business' and (p_activity is null or p_activity not in ('supermarket','restaurant','greengrocer','farm','bakery','pastry','deli','butcher','fishmonger','bar','hotel','food_shop','other')) then raise exception 'Scegli il tipo di attività';end if;
 perform public.saveat_save_profile(p_name,p_type,p_business,p_city,p_radius,p_vat,p_address);
 update public.saveat_profiles set business_activity=case when p_type='business' then p_activity else null end where id=auth.uid();
end;$$;
revoke all on function public.saveat_save_profile_activity(text,text,text,text,integer,text,text,text) from public,anon;
grant execute on function public.saveat_save_profile_activity(text,text,text,text,integer,text,text,text) to authenticated;
create or replace function public.saveat_public_avatars(p_owner_ids uuid[]) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'avatar_path',p.avatar_path,'business_activity',case when p.account_type='business' then p.business_activity else null end)),'[]'::jsonb) from public.saveat_profiles p where p.id=any(p_owner_ids[1:100]) and (p.id=auth.uid() or exists(select 1 from public.saveat_listings l where l.owner_id=p.id and ((l.status='active' and l.pickup_end>now()) or public.saveat_has_reservation(l.id))));
$$;
notify pgrst,'reload schema';
commit;
