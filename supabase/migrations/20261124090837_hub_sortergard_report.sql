create table private.hub_sortergard_addresses (
 tenant_id uuid not null references public.hub_tenants(id),
 event_id uuid not null references public.hub_weighing_events(id),
 status text not null check(status in ('verified','likely','missing')),
 origin text not null default '',
 destination text not null default '',
 candidates jsonb not null default '[]',
 source text not null default '',
 reason text not null default '',
 confidence int not null default 0 check(confidence between 0 and 100),
 reviewed_by uuid,
 updated_at timestamptz not null default now(),
 primary key(tenant_id,event_id)
);
create table private.hub_sortergard_reports (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.hub_tenants(id),
 year int not null,
 version int not null,
 created_at timestamptz not null default now(),
 created_by uuid not null,
 created_by_label text not null,
 incomplete boolean not null,
 rows jsonb not null,
 unique(tenant_id,year,version)
);
alter table private.hub_sortergard_addresses enable row level security;
alter table private.hub_sortergard_reports enable row level security;
revoke all on private.hub_sortergard_addresses,private.hub_sortergard_reports from public,anon,authenticated;

create function private.hub_sortergard_data(p_tenant uuid,p_year int)
returns table(id uuid, trans_id text, day text, reg text, sender text, recipient text, material text, tonnes numeric,
 stock text, kind text, status text, origin text, destination text, source text, reason text, confidence int, candidates jsonb, raw jsonb)
language sql stable set search_path='' as $$
 select e.id,e.source_record_id,to_char(e.occurred_at at time zone 'Europe/Stockholm','YYYY-MM-DD'),e.vehicle_registration,
 e.raw_payload->>'Avsändare (Id)',e.raw_payload->>'Mottagare (Id)',coalesce(e.raw_payload->>'Artikel (Id)',e.material_name),
 e.net_weight_kg/1000,e.raw_payload->>'Lagerplats',
 case when e.source_metadata->>'external_delivery'='true' then 'Externleverans' else e.raw_payload->>'Leveranstyp' end,
 coalesce(a.status,'pending'),coalesce(a.origin,''),coalesce(a.destination,''),coalesce(a.source,''),coalesce(a.reason,''),
 coalesce(a.confidence,0),coalesce(a.candidates,'[]'),e.raw_payload
 from public.hub_weighing_events e left join private.hub_sortergard_addresses a on a.tenant_id=e.tenant_id and a.event_id=e.id
 where e.tenant_id=p_tenant and e.source_system='elleholms_sortergard_excel' and e.measurement_status<>'void'
 and e.occurred_at >= (make_date(p_year,1,1)::timestamp at time zone 'Europe/Stockholm')
 and e.occurred_at < (make_date(p_year+1,1,1)::timestamp at time zone 'Europe/Stockholm')
 order by e.occurred_at,e.source_record_id
$$;
revoke all on function private.hub_sortergard_data(uuid,int) from public,anon,authenticated;

create function private.hub_sortergard_match(p_tenant uuid,p_year int,p_pending boolean)
returns jsonb language sql volatile set search_path='' as $$
 with all_rows as materialized (select * from private.hub_sortergard_data(p_tenant,p_year)),
 events as materialized (
  select d.*,lower(btrim(raw->>'Ordernr')) ord,lower(btrim(raw->>'Referens')) ref,
         lower(btrim(regexp_replace(material,'\s*\([^()]+\)\s*$',''))) mat
  from all_rows d
  where status<>'verified' and (not p_pending or status='pending')
 ), work as materialized (
  select distinct lower(btrim(source_data->>'Ordernummer')) ord,
    lower(btrim(source_data->>'ErReferens')) ref,
    lower(btrim(source_data->>'Projekt')) project,
    upper(regexp_replace(coalesce(nullif(source_data->>'RegNr',''),source_data->>'Fordon'),'[^[:alnum:]]','','g')) reg,
    left(coalesce(nullif(source_data->>'Artikeldatum',''),source_data->>'PlaneradStart'),10) as day,
    lower(btrim(source_data->>'Artikelnamn')) mat, source_data->>'Kundnamn' customer,
    case when lower(source_data->>'Enhet') in ('ton','t') and replace(source_data->>'Kvantitet',',','.') ~ '^[0-9]{1,7}(\.[0-9]{1,6})?$'
      then replace(source_data->>'Kvantitet',',','.')::numeric end tonnes,
    btrim(source_data->>'Platser') address
  from private.hub_workify_row_observations
  where tenant_id=p_tenant and nullif(btrim(source_data->>'Platser'),'') is not null
   and char_length(source_data->>'Platser')<=240 and source_data->>'Platser' !~ 'https?://|[;\n\r]'
   and source_data->>'Platser' ~ '[[:alpha:]].*[0-9]+.*,.*[0-9]{3} ?[0-9]{2} +[[:alpha:]]'
 ), projects as materialized (
  select distinct lower(btrim(coalesce(nullif(n.payload->>'projectno',''),k.identity_value))) project,
   lower(btrim(n.payload->>'orderno')) ord,n.payload->>'name' name,
   concat_ws(', ',nullif(btrim(n.payload->>'workplaceaddress1'),''),nullif(btrim(n.payload->>'workplaceaddress2'),''),
    nullif(btrim(concat_ws(' ',n.payload->>'workplacezipcode',n.payload->>'workplacecity')),'')) address
  from public.hub_next_entities n
  left join public.hub_identity_keys k on k.tenant_id=n.tenant_id and k.object_type='Project' and k.identity_type='next_project_number'
   and k.identity_value=n.payload->>'projectno'
  where n.tenant_id=p_tenant and n.entity_type='project' and nullif(btrim(n.payload->>'workplaceaddress1'),'') is not null
 ), candidates as (
  select e.id,w.address,'Workify' source,w.ord reference,
   case when e.ord=w.ord then 94 when e.ref=w.ord or e.ref=w.ref then 85 else 72 end score,
   case when e.ord=w.ord then 'Samma ordernummer' when e.ref=w.ord or e.ref=w.ref then 'Samma referens'
        else 'Samma registrering, datum, material och vikt' end reason
  from events e join work w on (nullif(e.ord,'')=w.ord or nullif(e.ref,'')=w.ord or nullif(e.ref,'')=nullif(w.ref,'')
    or (nullif(e.reg,'')=w.reg and e.day=w.day and e.mat=w.mat and abs(e.tonnes-w.tonnes)<=0.05
      and 1=(select count(*) from all_rows d where d.day=e.day and d.reg=e.reg and d.material=e.material and abs(d.tonnes-e.tonnes)<=0.05)))
  where e.kind in ('Inleverans','Utleverans')
  union all
  select e.id,p.address,'Next',p.project,
    case when e.ord in(p.project,p.ord) then 91 else 83 end,
    case when e.ord in(p.project,p.ord) then 'Samma projekt- eller ordernummer' else 'Referens motsvarar projektnummer' end
  from events e join projects p on nullif(e.ord,'') in(p.project,p.ord) or nullif(e.ref,'')=p.project
  where e.kind in ('Inleverans','Utleverans')
  union all
  select e.id,case when e.kind='Inleverans' then a.origin else a.destination end,'Verifierad historik',d.source_record_id,90,
    'Samma order, leveranstyp och material som en verifierad vägning'
  from events e join public.hub_weighing_events d on d.tenant_id=p_tenant and d.source_system='elleholms_sortergard_excel'
    and nullif(e.ord,'')=lower(btrim(d.raw_payload->>'Ordernr')) and e.kind=d.raw_payload->>'Leveranstyp'
    and e.material=d.raw_payload->>'Artikel (Id)' and abs((e.day::date-(d.occurred_at at time zone 'Europe/Stockholm')::date))<=90
    and coalesce(e.sender,'')=coalesce(d.raw_payload->>'Avsändare (Id)','') and coalesce(e.recipient,'')=coalesce(d.raw_payload->>'Mottagare (Id)','')
  join private.hub_sortergard_addresses a on a.tenant_id=p_tenant and d.id=a.event_id and a.status='verified'
  where e.kind in ('Inleverans','Utleverans')
 ), dedup as (
  select distinct on(id,lower(address)) id,address,source,reference,score,reason from candidates
  where nullif(btrim(address),'') is not null order by id,lower(address),score desc,source,reference
 ), ranked as (
  select *,row_number() over(partition by id order by score desc,address) rank from dedup
 ), results as (
  select id,jsonb_agg(jsonb_build_object('address',address,'source',source,'reference',reference,'score',score,'reason',reason) order by rank) options
  from ranked where rank<=8 group by id
 ), writes as (
  insert into private.hub_sortergard_addresses(tenant_id,event_id,status,candidates,origin,destination,source,reason,confidence)
  select p_tenant,e.id,case when r.options is null then 'missing' else 'likely' end,coalesce(r.options,'[]'),
   case when e.kind='Inleverans' then coalesce(r.options->0->>'address','') else '' end,
   case when e.kind='Utleverans' then coalesce(r.options->0->>'address','') else '' end,
   coalesce(r.options->0->>'source',''),
   case when r.options is null then 'Ingen tillräckligt underbyggd adress'
    when jsonb_array_length(r.options)>1 then 'Flera adresser behöver jämföras. '||(r.options->0->>'reason')
    else r.options->0->>'reason' end,
   coalesce((r.options->0->>'score')::int,0)
  from events e left join results r on r.id=e.id
  on conflict (tenant_id,event_id) do update set status=excluded.status,candidates=excluded.candidates,origin=excluded.origin,
   destination=excluded.destination,source=excluded.source,reason=excluded.reason,confidence=excluded.confidence,updated_at=now()
   where hub_sortergard_addresses.status<>'verified'
  returning status
 ) select jsonb_build_object('likely',count(*) filter(where status='likely'),'missing',count(*) filter(where status='missing'),'processed',count(*)) from writes
$$;
revoke all on function private.hub_sortergard_match(uuid,int,boolean) from public,anon,authenticated;

create function private.hub_sortergard_report(p_tenant uuid,p_year int,p_action text,p_args jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare items jsonb; entry record; mode text; supplied text; supplied_origin text; supplied_destination text;
 snapshot jsonb; report_version int; report_id uuid; affected int:=0;
begin
 if auth.uid() is null or public.hub_has_permission(p_tenant,'kpi.manage') is not true then
  raise exception 'Behörighet saknas' using errcode='42501';
 end if;
 if p_year not between 2026 and 2100 then raise exception 'Ogiltigt rapportår'; end if;
 if p_action='read' then
  return (select coalesce(jsonb_agg(to_jsonb(d)),'[]') from private.hub_sortergard_data(p_tenant,p_year) d);
 elsif p_action='match' then
  return private.hub_sortergard_match(p_tenant,p_year,coalesce((p_args->>'pending')::boolean,false));
 elsif p_action='review' then
  items:=p_args->'items'; mode:=p_args->>'mode';
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 150 or mode not in ('approve','manual') then
   raise exception 'Kontrollera urvalet';
  end if;
  for entry in
   select d.*,(i->>'candidate')::int candidate,(i->>'confidence')::int expected_confidence,
    i->>'expectedAddress' expected_address
   from jsonb_array_elements(items) i join private.hub_sortergard_data(p_tenant,p_year) d on d.id=(i->>'id')::uuid
  loop
   if mode='approve' then
    if entry.status<>'likely' then raise exception 'Förslaget behöver räknas om'; end if;
    supplied:=entry.candidates->coalesce(entry.candidate,0)->>'address';
    if supplied is null or supplied is distinct from entry.expected_address then raise exception 'Adressförslaget har ändrats'; end if;
    supplied_origin:=case when entry.kind='Inleverans' then supplied else '' end;
    supplied_destination:=case when entry.kind='Utleverans' then supplied else '' end;
   else
    supplied_origin:=case when entry.kind in('Inleverans','Externleverans') then coalesce(btrim(p_args->>'origin'),'') else '' end;
    supplied_destination:=case when entry.kind in('Utleverans','Externleverans') then coalesce(btrim(p_args->>'destination'),'') else '' end;
   end if;
   if length(supplied_origin)>240 or length(supplied_destination)>240 or
      (case entry.kind when 'Inleverans' then supplied_origin='' when 'Utleverans' then supplied_destination=''
       when 'Externleverans' then supplied_origin='' or supplied_destination='' else true end) then
    raise exception 'Fyll i adress för leveranstypen';
   end if;
   insert into private.hub_sortergard_addresses(tenant_id,event_id,status,origin,destination,candidates,source,reason,confidence,reviewed_by)
   values(p_tenant,entry.id,'verified',supplied_origin,supplied_destination,entry.candidates,
     case when mode='approve' then entry.candidates->coalesce(entry.candidate,0)->>'source' else 'Manuell granskning' end,
     'Verifierad och låst av användare',100,auth.uid())
   on conflict(tenant_id,event_id) do update set status='verified',origin=excluded.origin,destination=excluded.destination,
    source=excluded.source,reason=excluded.reason,confidence=100,reviewed_by=auth.uid(),updated_at=now()
    where mode='manual' or (hub_sortergard_addresses.status='likely'
      and hub_sortergard_addresses.candidates->coalesce(entry.candidate,0)->>'address'=supplied);
   if not found then raise exception 'Adressförslaget har ändrats'; end if;
   affected:=affected+1;
  end loop;
  if affected<>jsonb_array_length(items) then raise exception 'Alla vägningar kunde inte granskas'; end if;
  return jsonb_build_object('reviewed',affected);
 elsif p_action='archive' then
  return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select id,year,version,created_at,created_by_label,incomplete from private.hub_sortergard_reports
   where tenant_id=p_tenant and year=p_year order by version desc)x);
 elsif p_action='version' then
  return (select to_jsonb(r) - 'tenant_id' - 'created_by' from private.hub_sortergard_reports r
   where tenant_id=p_tenant and year=p_year and r.id=(p_args->>'id')::uuid);
 elsif p_action='finalize' then
  perform pg_advisory_xact_lock(hashtextextended('sortergard:'||p_tenant::text||':'||p_year,0));
  select coalesce(jsonb_agg(to_jsonb(d)),'[]') into snapshot from private.hub_sortergard_data(p_tenant,p_year) d;
  if jsonb_array_length(snapshot)=0 then raise exception 'Inga vägningar att färdigställa'; end if;
  select coalesce(max(version),0)+1 into report_version from private.hub_sortergard_reports where tenant_id=p_tenant and year=p_year;
  insert into private.hub_sortergard_reports(tenant_id,year,version,created_by,created_by_label,incomplete,rows)
  values(p_tenant,p_year,report_version,auth.uid(),coalesce(auth.jwt()->>'email',auth.uid()::text),
   exists(select 1 from jsonb_array_elements(snapshot) v where v->>'status'<>'verified'),snapshot)
  returning id into report_id;
  return jsonb_build_object('id',report_id,'version',report_version);
 elsif p_action='search' then
  supplied:=btrim(p_args->>'query');
  if length(supplied) not between 2 and 100 then return '[]'::jsonb; end if;
  if p_args->>'source'='Next' then
   return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
    select distinct payload->>'projectno' reference,payload->>'name' name,
     concat_ws(', ',nullif(btrim(payload->>'workplaceaddress1'),''),nullif(btrim(payload->>'workplaceaddress2'),''),
       nullif(btrim(concat_ws(' ',payload->>'workplacezipcode',payload->>'workplacecity')),'')) address
    from public.hub_next_entities where tenant_id=p_tenant and entity_type='project'
     and strpos(lower(concat_ws(' ',payload->>'projectno',payload->>'name')),lower(supplied))>0
     and nullif(btrim(payload->>'workplaceaddress1'),'') is not null
    order by 1,2 limit 20)x);
  elsif p_args->>'source'='Workify' then
   return (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (
    select distinct source_data->>'Ordernummer' reference,source_data->>'Rubrik' name,btrim(source_data->>'Platser') address
    from private.hub_workify_row_observations where tenant_id=p_tenant
     and strpos(lower(concat_ws(' ',source_data->>'Ordernummer',source_data->>'Projekt',source_data->>'Rubrik')),lower(supplied))>0
     and source_data->>'Platser' ~ '[[:alpha:]].*[0-9]+.*,.*[0-9]{3} ?[0-9]{2} +[[:alpha:]]'
     and char_length(source_data->>'Platser')<=240 and source_data->>'Platser' !~ 'https?://|[;\n\r]'
    order by 1,2 limit 20)x);
  end if;
 end if;
 raise exception 'Okänd åtgärd';
end
$$;
create function public.hub_sortergard_report(p_tenant uuid,p_year int,p_action text,p_args jsonb default '{}')
returns jsonb language sql security invoker set search_path='' as $$
 select private.hub_sortergard_report(p_tenant,p_year,p_action,p_args)
$$;
revoke all on function private.hub_sortergard_report(uuid,int,text,jsonb),public.hub_sortergard_report(uuid,int,text,jsonb) from public,anon,authenticated;
grant execute on function private.hub_sortergard_report(uuid,int,text,jsonb),public.hub_sortergard_report(uuid,int,text,jsonb) to authenticated;
