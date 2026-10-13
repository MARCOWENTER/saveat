begin;
alter table public.saveat_notifications drop constraint if exists saveat_notifications_kind_check;
alter table public.saveat_notifications add constraint saveat_notifications_kind_check check(kind in ('owner_unavailable','listing_changed','customer_cancelled'));
create or replace function public.saveat_change_value(k text,v jsonb) returns text language plpgsql stable set search_path='' as $$
declare t text;n text;begin
 if v is null or v='null'::jsonb or v='""'::jsonb then return 'non indicato';end if;
 t:=v#>>'{}';
 if k in ('pickup_start','pickup_end') then return to_char(t::timestamptz at time zone 'Europe/Rome','DD/MM/YYYY HH24:MI');end if;
 if k='municipality_code' then select name||' ('||province||')' into n from public.saveat_municipalities where code=t;return coalesce(n,t);end if;
 if k='payment_methods' then select string_agg(case x when 'cash' then 'Contanti' when 'card' then 'Carta/POS' when 'satispay' then 'Satispay' else x end,', ' order by x) into n from jsonb_array_elements_text(v) x;return coalesce(n,'nessuno');end if;
 if k='container_provided' then return case when t='true' then 'fornito' else 'da portare' end;end if;
 if k='date_type' then return case t when 'none' then 'senza data' when 'use_by' then 'da consumare entro' when 'best_before' then 'preferibilmente entro' else t end;end if;
 if k='photo_path' then return 'presente';end if;
 if k='price' then return t||' €';end if;
 return t;end;$$;
create or replace function public.saveat_listing_changes(b jsonb,a jsonb) returns text language plpgsql stable set search_path='' as $$
declare section text;k text;label text;result text:='';olditem jsonb;newitem jsonb;fields jsonb;begin
 for section,fields in select * from (values ('listing','{"title":"Titolo","description":"Descrizione","municipality_code":"Comune","pickup_start":"Inizio ritiro","pickup_end":"Fine ritiro","payment_methods":"Metodi di pagamento"}'::jsonb),('pickup','{"address":"Indirizzo","contact":"Contatto","instructions":"Istruzioni"}'::jsonb)) x loop
 for k,label in select key,value from jsonb_each_text(fields) loop
 if b->section->k is distinct from a->section->k then result:=result||E'\n• '||label||': '||public.saveat_change_value(k,b->section->k)||' → '||public.saveat_change_value(k,a->section->k);end if;end loop;end loop;
 for newitem in select value from jsonb_array_elements(a->'items') loop
 select value into olditem from jsonb_array_elements(b->'items') where value->>'id'=newitem->>'id';
 for k,label in select key,value from jsonb_each_text('{"name":"Nome","unit":"Unità","quantity":"Quantità totale","price":"Prezzo unitario","date_type":"Tipo di scadenza","label_date":"Data in etichetta","allergens":"Allergeni","unit_weight_kg":"Peso unitario (kg)","container_provided":"Contenitore","photo_path":"Foto"}'::jsonb) loop
 if olditem->k is distinct from newitem->k then result:=result||E'\n• '||coalesce(olditem->>'name',newitem->>'name')||' — '||label||': '||case when k='photo_path' and olditem->>k is not null and newitem->>k is not null then 'foto sostituita' else public.saveat_change_value(k,olditem->k)||' → '||public.saveat_change_value(k,newitem->k) end;end if;end loop;end loop;return result;end;$$;
revoke all on function public.saveat_change_value(text,jsonb),public.saveat_listing_changes(jsonb,jsonb) from public,anon,authenticated;
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
 changes:=public.saveat_listing_changes(before_state,after_state);
 if changes<>'' then
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message)
 select r.customer_id,r.id,'listing_changed','Annuncio aggiornato: controlla il tuo ritiro','Modifiche a «'||trim(p_listing->>'title')||'»:'||changes||E'\nIl prezzo della tua prenotazione resta quello concordato.' from public.saveat_reservations r where r.listing_id=p_id and r.status in ('reserved','confirmed')
 on conflict(reservation_id,kind) do update set title=excluded.title,message=excluded.message,created_at=now(),read_at=null;
 end if;
end;$$;
create or replace function public.saveat_notify_unavailable() returns trigger language plpgsql security definer set search_path='' as $$
declare recipient uuid;v_title text;v_name text;foods text;v_kind text;v_heading text;v_message text;v_id uuid;begin
 if new.status<>'cancelled' or old.status not in ('reserved','confirmed') then return new;end if;
 select title,owner_id into v_title,recipient from public.saveat_listings where id=new.listing_id;
 select display_name into v_name from public.saveat_profiles where id=new.customer_id;
 select string_agg(name||': '||quantity::text||' '||unit,E'\n' order by name) into foods from public.saveat_reservation_items where reservation_id=new.id;
 if new.cancellation_reason='customer_cancelled' then v_kind:='customer_cancelled';v_heading:='Prenotazione annullata';v_message:=coalesce(v_name,'Il cliente')||' ha annullato la prenotazione di «'||v_title||'». Gli alimenti tornano disponibili.';
 elsif new.cancellation_reason='owner_unavailable' then recipient:=new.customer_id;v_kind:='owner_unavailable';v_heading:='Ritiro annullato: cibo non disponibile';v_message:='Chi pubblica ha annullato la prenotazione di «'||v_title||'». Non recarti al punto di incontro.';
 else return new;end if;
 v_message:=v_message||E'\nAlimenti annullati:\n'||coalesce(foods,'')||E'\nPrenotazione: '||new.id::text;
 insert into public.saveat_notifications(user_id,reservation_id,kind,title,message) values(recipient,new.id,v_kind,v_heading,v_message) on conflict(reservation_id,kind) do nothing returning id into v_id;
 if v_id is not null then insert into public.saveat_notification_outbox(id,user_id,recipient_email,subject,message) select v_id,recipient,u.email,'Saveat — '||v_heading,v_message from auth.users u where u.id=recipient;end if;return new;end;$$;

commit;
