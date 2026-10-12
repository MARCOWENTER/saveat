begin;
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
  insert into public.saveat_items(listing_id,name,unit,quantity,available,price,label_date,date_type,allergens,photo_path)
  values(v_id,trim(v_item->>'name'),v_item->>'unit',v_qty,v_qty,v_price,(nullif(v_item->>'label_date',''))::date,v_item->>'date_type',coalesce(v_item->>'allergens',''),nullif(v_item->>'photo_path',''));
 end loop;
 return v_id;
end; $$;
commit;
