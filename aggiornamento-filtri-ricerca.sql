-- Saveat: ricerca con filtri, aggiunta non distruttiva.
begin;
set local lock_timeout='5s';
create or replace function public.saveat_search_filtered(p_lat double precision,p_lon double precision,p_radius integer,p_query text default '',p_page integer default 0,p_size integer default 20,p_category text default '',p_offer text default 'all') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;category_filter text:=coalesce(trim(p_category),'');offer_filter text:=coalesce(p_offer,'all');
begin
 if p_lat is null or p_lon is null or p_lat not between -90 and 90 or p_lon not between -180 and 180 or p_radius is null or p_radius not between 1 and 200 then raise exception 'Zona di ricerca non valida'; end if;
 if offer_filter not in ('all','free','paid') then raise exception 'Scegli una modalità valida';end if;
 if category_filter<>'' and category_filter not in ('Pane e prodotti da forno','Frutta e verdura','Pasticceria e dolci','Gastronomia e piatti pronti','Latticini e formaggi','Carne e salumi','Pesce','Prodotti confezionati','Bevande','Altri alimenti') then raise exception 'Scegli una categoria valida';end if;
 select coalesce(jsonb_agg(to_jsonb(q) order by q.distance_km,q.created_at desc,q.id),'[]'::jsonb) into result from (
 select l.*,public.saveat_distance_km(p_lat,p_lon,m.latitude,m.longitude) distance_km,
 (select coalesce(jsonb_agg(to_jsonb(i) order by i.name),'[]'::jsonb) from public.saveat_items i where i.listing_id=l.id) saveat_items,
 jsonb_build_object('name',m.name,'province',m.province) saveat_municipalities
 from public.saveat_listings l join public.saveat_municipalities m on m.code=l.municipality_code
 where public.saveat_can_discover() and l.status='active' and l.pickup_end>now() and m.latitude is not null and m.longitude is not null
 and public.saveat_distance_km(p_lat,p_lon,m.latitude,m.longitude)<=p_radius
 and exists(select 1 from public.saveat_items i where i.listing_id=l.id and i.available>0
 and (category_filter='' or i.category=category_filter)
 and (offer_filter='all' or (offer_filter='free' and i.price=0) or (offer_filter='paid' and i.price>0))
 and (coalesce(trim(p_query),'')='' or l.title ilike '%'||left(p_query,100)||'%' or i.name ilike '%'||left(p_query,100)||'%'))
 order by distance_km,l.created_at desc,l.id limit least(greatest(coalesce(p_size,20),1),50) offset greatest(coalesce(p_page,0),0)*least(greatest(coalesce(p_size,20),1),50)
 ) q;
 return result;
end; $$;
revoke all on function public.saveat_search_filtered(double precision,double precision,integer,text,integer,integer,text,text) from public;
grant execute on function public.saveat_search_filtered(double precision,double precision,integer,text,integer,integer,text,text) to anon,authenticated;
notify pgrst,'reload schema';
commit;
