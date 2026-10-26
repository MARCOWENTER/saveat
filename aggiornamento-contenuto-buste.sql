-- Saveat: modifica del contenuto indicativo, patch mirata alle funzioni esistenti.
-- Nessuna modifica a tabelle, RLS, disponibilità o prezzi delle prenotazioni.
begin;
set local lock_timeout='5s';
do $patch$
declare d text; needle text;
begin
 d:=pg_get_functiondef('public.saveat_update_listing(uuid,jsonb,jsonb)'::regprocedure);
 needle:='set name=trim(j->>''name''),unit=j->>''unit'',quantity=q';
 if position('description=case when j ? ''description''' in d)=0 then
  if position(needle in d)=0 then raise exception 'Definizione aggiornamento inattesa: nessuna modifica';end if;
  d:=replace(d,needle,'set name=trim(j->>''name''),description=case when j ? ''description'' then coalesce(j->>''description'','''') else i.description end,unit=j->>''unit'',quantity=q');
  execute d;
 end if;
 d:=pg_get_functiondef('public.saveat_listing_changes(jsonb,jsonb)'::regprocedure);
 needle:='"name":"Nome","unit":"Unità"';
 if position('"description":"Contenuto / descrizione"' in d)=0 then
  if position(needle in d)=0 then raise exception 'Definizione avvisi inattesa: nessuna modifica';end if;
  d:=replace(d,needle,'"name":"Nome","description":"Contenuto / descrizione","unit":"Unità"');
  execute d;
 end if;
end $patch$;
notify pgrst,'reload schema';
commit;
