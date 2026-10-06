-- Canonical project aliases are resolved in Hub, preserving source references.
create or replace function private.hub_kpi_project_reference_v1(p_tenant_id uuid,p_reference text)
returns text language sql stable security invoker set search_path='' as $fn$
 select coalesce(case when count(distinct k.object_id)=1 then max(nullif(o.data->>'project_number','')) end,nullif(trim(p_reference),''))
 from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
 where k.tenant_id=p_tenant_id and k.object_type='Project' and k.identity_type='next_project_number' and k.identity_value=trim(p_reference) and k.confidence=1;
$fn$;
revoke all on function private.hub_kpi_project_reference_v1(uuid,text) from public,anon;
grant execute on function private.hub_kpi_project_reference_v1(uuid,text) to authenticated;
-- Respect dated article-file project allocation. Tipping never credits a vehicle.
-- Explicit Tippavgift names in retained rule source evidence classify tipping income.
create or replace function public.hub_kpi_internal_transfers_v1(p_tenant_id uuid,p_from date,p_to date,p_months integer[] default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid period'; end if;
 if p_months is not null and (cardinality(p_months)=0 or exists(select 1 from unnest(p_months) m where m<1 or m>12 or m is null)) then raise exception 'Invalid months';end if;
 with raw_base as materialized (
  select x.*,coalesce(nullif(x.external_transaction_id,''),md5(jsonb_build_array(x.source_data->>'Ordernummer',x.source_data->>'Artikelnummer',x.occurred_on,upper(trim(x.source_data->>'RegNr')))::text)) legacy_key,
   private.hub_kpi_project_reference_v1(p_tenant_id,nullif(regexp_replace(trim(coalesce(nullif(x.source_data->>'Littranummer',''),x.source_data->>'Projekt')),'^(AO)?([^[:space:]]+).*$', '\2','i'),'')) receiver_reference
  from public.kpi_import_rows x where x.tenant_id=p_tenant_id and x.data_kind='revenue'
   and lower(trim(x.source_data->>'Kundnamn'))='elleholms maskin ab'
   and x.occurred_on between p_from and p_to and (p_months is null or extract(month from x.occurred_on)::integer=any(p_months))
 ), numbered as materialized (
  select x.*,row_number() over(partition by batch_id,legacy_key order by row_number,id) line_ordinal from raw_base x
 ), raw as materialized (
  select x.*,coalesce(old.source_key,nullif(x.external_transaction_id,''),'workify-line-v2:'||legacy_key||':'||line_ordinal) source_key,
   nullif(trim(source_data->>'RegNr'),'') is null and nullif(trim(source_data->>'Fordon'),'') is null project_fallback
  from numbered x left join lateral(
   select l.source_key from public.kpi_internal_transfer_ledger l where l.tenant_id=p_tenant_id
   and (l.snapshot->>'row_id'=x.id::text or (l.source_key=x.legacy_key
    and jsonb_build_array(l.snapshot->'amount',l.snapshot->'quantity',l.snapshot->>'comment',l.snapshot->>'littra')
     =jsonb_build_array(x.amount,x.quantity,x.source_data->>'ArtikelKommentar',x.source_data->>'Littranummer')))
   order by (l.snapshot->>'row_id'=x.id::text) desc limit 1
  )old on true
 ), linked as (
  select x.*,count(*) over(partition by source_key) duplicate_count,
   ar.revenue_category category,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' or project_fallback then 'project' else 'vehicle' end carrier_type,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' or project_fallback then case when ai.n=1 then ai.id end else case when vi.n=1 then vi.id end end carrier_id,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' then ar.project_reference else receiver_reference end carrier_reference,ac.name carrier_project_name,
   case when vi.n=1 then vi.id end vehicle_id,case when pi.n=1 then pi.id end receiver_id,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' or project_fallback then coalesce(case when not project_fallback then ar.cost_center end,case when ac.n=1 then ac.code end) else case when sc.n=1 then sc.code end end source_center,case when rc.n=1 then rc.code else '10' end receiver_center,
   rc.n<>1 receiver_defaulted,
   rc.name receiver_name
  from raw x
  left join lateral(select count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id from public.hub_identity_keys k
   join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
   where k.tenant_id=p_tenant_id and lower(o.object_type)='vehicle' and k.confidence=1
   and ((x.vehicle_object_id is not null and k.object_id=x.vehicle_object_id) or
   (x.vehicle_object_id is null and ((k.identity_type='registration_number' and upper(trim(k.identity_value))=upper(trim(x.source_data->>'RegNr'))) or (k.identity_type='workify_vehicle_label' and upper(trim(k.identity_value))=upper(trim(x.source_data->>'RegNr'))))))) vi on true
  left join lateral(select count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id from public.hub_identity_keys k
   join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
   where k.tenant_id=p_tenant_id and lower(o.object_type)='project' and k.confidence=1
   and k.identity_type='next_project_number' and k.identity_value=x.receiver_reference) pi on true
  left join lateral(select a.target_type,private.hub_kpi_project_reference_v1(p_tenant_id,a.project_reference) project_reference,a.cost_center,case when exists(select 1 from jsonb_array_elements(a.source_rows) e where trim(e->'values'->>'Namn') ilike 'Tippavgift%') then 'tipp_deponi' else a.revenue_category end revenue_category from public.kpi_workify_article_rules a where a.tenant_id=p_tenant_id and a.enabled
   and a.article_number=x.source_data->>'Artikelnummer' and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to)
   order by a.valid_from desc,a.id limit 1) ar on true
  left join lateral(select count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id from public.hub_identity_keys k
   join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
   where k.tenant_id=p_tenant_id and lower(o.object_type)='project' and k.confidence=1
   and k.identity_type='next_project_number' and k.identity_value=case when ar.target_type='project' or ar.revenue_category='tipp_deponi' then ar.project_reference else case when project_fallback then x.receiver_reference end end) ai on true
  left join lateral(select count(distinct c.cost_center) n,min(c.cost_center) code,min(c.project_name) name from public.kpi_project_classification_periods c
   where c.tenant_id=p_tenant_id and c.project_reference=case when ar.target_type='project' or ar.revenue_category='tipp_deponi' then ar.project_reference else case when project_fallback then x.receiver_reference end end
   and c.valid_from<=x.occurred_on and (c.valid_to is null or c.valid_to>=x.occurred_on)) ac on true
  left join lateral(select count(distinct c.cost_center) n,min(c.cost_center) code from public.kpi_project_classification_periods c
   where c.tenant_id=p_tenant_id and (upper(trim(x.source_data->>'RegNr'))=any(c.registrations) or (upper(trim(x.source_data->>'RegNr'))='LASTBIL' and c.project_reference='9009'))
   and c.valid_from<=x.occurred_on and (c.valid_to is null or c.valid_to>=x.occurred_on)) sc on true
  left join lateral(select count(distinct c.cost_center) n,min(c.cost_center) code,min(c.project_name) name from public.kpi_project_classification_periods c
   where c.tenant_id=p_tenant_id and c.project_reference=x.receiver_reference
   and c.valid_from<=x.occurred_on and (c.valid_to is null or c.valid_to>=x.occurred_on)) rc on true
 ), prepared as (
  select source_key,jsonb_build_object('source_key',source_key,'row_id',id,'occurred_on',occurred_on,'order',source_data->>'Ordernummer',
   'littra',source_data->>'Littranummer','project',receiver_reference,'receiver_name',receiver_name,
   'vehicle',case when upper(trim(source_data->>'RegNr'))='LASTBIL' then 'Inhyrda lastbilar' else upper(trim(source_data->>'RegNr')) end,'vehicle_id',vehicle_id,'receiver_id',receiver_id,
   'carrier_type',carrier_type,'carrier_id',carrier_id,'carrier_reference',case when carrier_type='project' then carrier_reference end,
   'carrier_name',case when carrier_type='project' then coalesce(carrier_project_name,carrier_reference) else case when upper(trim(source_data->>'RegNr'))='LASTBIL' then 'Inhyrda lastbilar' else upper(trim(source_data->>'RegNr')) end end,
   'source_center',source_center,'receiver_center',receiver_center,'category',coalesce(category,'unclassified'),
   'amount',amount,'quantity',quantity,'unit',source_data->>'Enhet','article',source_data->>'Artikelnummer',
   'description',description,'comment',source_data->>'ArtikelKommentar','receipt_url',nullif(source_data->>'FilUrl',''),
   'line_ordinal',line_ordinal,'duplicate_count',duplicate_count,'invoiced',source_data->>'Orderstatus'='Invoiced',
   'ready',(is_valid or (project_fallback and validation_errors<@'["Fordonsbeteckning saknar verifierad regnummerkoppling","Workify-artikeln ska till fordon: registreringsnummer behöver mappas"]'::jsonb)) and occurred_on is not null and amount is not null and carrier_id is not null
    and source_center is not null and receiver_center is not null and duplicate_count=1
    and source_data->>'Orderstatus'='Invoiced' and category in ('transport','material','tipp_deponi'),
   'review_reason',concat_ws('; ',case when not is_valid and not(project_fallback and validation_errors<@'["Fordonsbeteckning saknar verifierad regnummerkoppling","Workify-artikeln ska till fordon: registreringsnummer behöver mappas"]'::jsonb) then 'Ogiltig importrad' end,
    case when carrier_id is null then case when carrier_type='project' then 'Intäktsbärande lagerplats/projekt saknas eller är tvetydigt' else 'Canonical fordonskoppling saknas/är tvetydig' end end,
    case when source_center is null then 'Utförande kostnadsställe saknas' end,
    case when duplicate_count>1 then 'Samma källrad finns i flera importer – behöver granskas' end,
    case when source_data->>'Orderstatus' is distinct from 'Invoiced' then 'Inte fakturerad' end,
    case when category is null or category not in ('transport','material','tipp_deponi') then 'Artikelkategori behöver granskas' end,
    case when amount is null then 'Belopp saknas' end))
   || case when receiver_defaulted then jsonb_build_object('receiver_rule','Standardregel: 10 Entreprenad vid utebliven entydig KST-matchning') else '{}'::jsonb end
   || case when upper(trim(source_data->>'RegNr'))='LASTBIL' then jsonb_build_object('vehicle_reference',source_data->>'RegNr','vehicle_rule','Lastbil = Inhyrda lastbilar, bekräftad benämning') else '{}'::jsonb end payload
  from linked where not(coalesce(category,'')='ignored' and coalesce(amount=0,false))
 ), finalized as (
  select p.payload||jsonb_build_object('export_id',l.export_id,'booking_reference',l.booking_reference,
   'status',case when l.source_key is null then case when (p.payload->>'ready')::boolean then 'new' else 'review' end
    when (p.payload - 'row_id' - 'line_ordinal') is distinct from (l.snapshot - 'row_id' - 'line_ordinal') then 'changed'
    when l.posted_at is not null then 'posted' else 'exported' end) payload from prepared p
  left join public.kpi_internal_transfer_ledger l on l.tenant_id=p_tenant_id and l.source_key=p.source_key
 ) select jsonb_build_object('rows',coalesce(jsonb_agg(payload order by payload->>'occurred_on',payload->>'order'),'[]'::jsonb),'count',count(*)) into result from finalized;
 if (result->>'count')::integer>10000 then raise exception 'Select a smaller period; no rows truncated';end if;
 return result;
end $$;
revoke all on function public.hub_kpi_internal_transfers_v1(uuid,date,date,integer[]) from public,anon;
grant execute on function public.hub_kpi_internal_transfers_v1(uuid,date,date,integer[]) to authenticated;

-- New files reuse dated article knowledge and confirmed project recipients.
create or replace function public.hub_kpi_resolve_workify_import_v1(p_tenant_id uuid,p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $fn$
declare resolved integer; valid integer; invalid integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 perform 1 from public.kpi_import_batches where tenant_id=p_tenant_id and id=p_batch_id and data_kind='revenue' for update;
 if not found then raise exception 'Intäktsimporten saknas';end if;
 with candidates as materialized(
  select r.id,a.revenue_category,a.target_type<>'project' project_fallback,
   case when a.target_type='project' then private.hub_kpi_project_reference_v1(p_tenant_id,a.project_reference)
    when nullif(trim(r.source_data->>'RegNr'),'') is null and nullif(trim(r.source_data->>'Fordon'),'') is null
    then private.hub_kpi_project_reference_v1(p_tenant_id,nullif(regexp_replace(trim(coalesce(nullif(r.source_data->>'Littranummer',''),r.source_data->>'Projekt')),'^(AO)?([^[:space:]]+).*$', '\2','i'),'')) end recipient
  from public.kpi_import_rows r join lateral(select a.* from public.kpi_workify_article_rules a where a.tenant_id=r.tenant_id and a.enabled and a.article_number=r.source_data->>'Artikelnummer' and r.occurred_on between a.valid_from and coalesce(a.valid_to,'infinity'::date) order by a.valid_from desc,a.id limit 1)a on true
  where r.tenant_id=p_tenant_id and r.batch_id=p_batch_id and r.occurred_on is not null and r.amount is not null
 ), verified as (
  select c.* from candidates c join public.kpi_import_rows r on r.id=c.id where
   (c.revenue_category='ignored' and r.amount=0) or
   (exists(select 1 from public.hub_identity_keys k where k.tenant_id=p_tenant_id and k.object_type='Project' and k.identity_type='next_project_number' and k.identity_value=c.recipient and k.confidence=1)
    and exists(select 1 from public.kpi_project_classification_periods p where p.tenant_id=p_tenant_id and p.project_reference=c.recipient and r.occurred_on between p.valid_from and coalesce(p.valid_to,'infinity'::date)))
 ), cleaned as (
  select v.*,coalesce((select jsonb_agg(error) from jsonb_array_elements_text(r.validation_errors) error
   where error not in ('Fordonsbeteckning saknar verifierad regnummerkoppling','Workify-artikeln ska till fordon: registreringsnummer behöver mappas') and error not like 'Ej mappad Workify-artikel:%'),'[]'::jsonb) errors
  from verified v join public.kpi_import_rows r on r.id=v.id
 )
 update public.kpi_import_rows r set project_reference=v.recipient,vehicle_registration=null,vehicle_object_id=null,
  validation_errors=v.errors,is_valid=jsonb_array_length(v.errors)=0,
  allocation=coalesce(r.allocation,'{}')||jsonb_build_object('target',case when v.revenue_category='ignored' then 'ignored' else 'project' end,'project_carrier_reference',v.recipient,'project_carrier_fallback',v.project_fallback,'resolution','confirmed_article_or_next_project','reviewed_by',auth.uid(),'reviewed_at',now())
 from cleaned v where r.id=v.id and r.tenant_id=p_tenant_id;
 get diagnostics resolved=row_count;
 select count(*)filter(where is_valid),count(*)filter(where not is_valid) into valid,invalid from public.kpi_import_rows where tenant_id=p_tenant_id and batch_id=p_batch_id;
 update public.kpi_import_batches set valid_row_count=valid,invalid_row_count=invalid,status=case when invalid=0 then 'completed' else 'needs_review' end where tenant_id=p_tenant_id and id=p_batch_id;
 return jsonb_build_object('resolved',resolved,'validRows',valid,'invalidRows',invalid,'status',case when invalid=0 then 'completed' else 'needs_review' end);
end $fn$;
revoke all on function public.hub_kpi_resolve_workify_import_v1(uuid,uuid) from public,anon;
grant execute on function public.hub_kpi_resolve_workify_import_v1(uuid,uuid) to authenticated;

-- Apply stored project carriers in the two existing financial readers only.
do $patch$
declare signature text; definition text; old_text text; new_text text;
begin
 foreach signature in array array['private.hub_kpi_financial_facts_v1(uuid,date,date)','private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])'] loop
  definition:=pg_get_functiondef(signature::regprocedure);
  old_text:=$old$case when x.data_kind='revenue' then case when ov.order_name is not null then null when ar.target_type='project' then nullif(trim(ar.project_reference),'') else null end$old$;
  new_text:=$new$case when x.data_kind='revenue' then case when nullif(x.allocation->>'project_carrier_reference','') is not null then x.allocation->>'project_carrier_reference' when ov.order_name is not null then null when ar.target_type='project' then private.hub_kpi_project_reference_v1(p_tenant_id,ar.project_reference) else null end$new$;
  if strpos(definition,old_text)=0 then raise exception 'Financial reader changed; review patch: %',signature;end if;
  definition:=replace(definition,old_text,new_text);
  definition:=replace(definition,$old$and (ov.order_name is not null or ar.target_type='vehicle')$old$,$new$and nullif(x.allocation->>'project_carrier_reference','') is null and (ov.order_name is not null or ar.target_type='vehicle')$new$);
  definition:=replace(definition,$old$where x.tenant_id=p_tenant_id and x.is_valid and x.data_kind in ('revenue','cost')$old$,$new$where x.tenant_id=p_tenant_id and x.is_valid and coalesce(ar.revenue_category,'')<>'ignored' and x.data_kind in ('revenue','cost')$new$);
  definition:=replace(definition,$old$|| jsonb_build_object('_humla_cost_center',$old$,$new$|| jsonb_build_object('_humla_project_fallback',x.allocation->'project_carrier_fallback') || jsonb_build_object('_humla_cost_center',$new$);
  definition:=replace(definition,$old$case when f.k='cost' and f.raw->>'_humla_include_in_vehicle_result'='false' then null$old$,$new$case when f.raw->>'_humla_project_fallback'='true' then null when f.k='cost' and f.raw->>'_humla_include_in_vehicle_result'='false' then null$new$);
  execute definition;
 end loop;
end $patch$;
