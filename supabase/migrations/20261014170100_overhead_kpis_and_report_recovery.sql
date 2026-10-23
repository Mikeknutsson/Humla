-- Consolidated final schema for period evidence and compact billable hours.
create table if not exists private.hub_overhead_months_v1(tenant_id uuid not null,month_start date not null,cost_center text not null,management_cost numeric not null check(management_cost>=0),other_overhead numeric not null check(other_overhead>=0),evidence text not null check(length(trim(evidence)) between 3 and 1000),updated_by uuid not null,updated_at timestamptz not null default now(),primary key(tenant_id,month_start,cost_center),check(month_start=date_trunc('month',month_start)::date));
create table if not exists private.hub_overhead_month_events_v1(id bigint generated always as identity primary key,tenant_id uuid not null,month_start date not null,cost_center text not null,before_value jsonb,after_value jsonb not null,actor uuid not null,created_at timestamptz not null default now());
create table if not exists private.hub_kpi_billable_hours_v1(generation_id uuid not null,tenant_id uuid not null,fiscal_year integer not null,source_row_id text not null,occurred_on date not null,cost_center text,business_group text,unit_id uuid,vehicle text,project text,hours numeric,fact_id text not null,primary key(generation_id,tenant_id,fact_id));
create index if not exists hub_kpi_billable_hours_scope_idx on private.hub_kpi_billable_hours_v1(tenant_id,generation_id,fiscal_year,cost_center,occurred_on);
create table if not exists private.hub_kpi_overview_cache_v1(tenant_id uuid not null,generation_id uuid not null,revision integer not null,fiscal_year integer not null,months integer[] not null,center text not null,filters jsonb not null,report jsonb not null,created_at timestamptz not null default now(),primary key(tenant_id,generation_id,revision,fiscal_year,months,center,filters));
alter table private.hub_overhead_months_v1 enable row level security;
alter table private.hub_overhead_month_events_v1 enable row level security;
alter table private.hub_kpi_billable_hours_v1 enable row level security;
alter table private.hub_kpi_overview_cache_v1 enable row level security;
revoke all on private.hub_overhead_months_v1,private.hub_overhead_month_events_v1,private.hub_kpi_billable_hours_v1,private.hub_kpi_overview_cache_v1 from public,anon,authenticated;
CREATE OR REPLACE FUNCTION private.hub_kpi_overhead_projection_v1(p_tenant uuid, p_year integer, p_months integer[], p_filters jsonb, p_report jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare result jsonb:=p_report;o jsonb;rev numeric;section text;metrics jsonb;
begin
 if jsonb_typeof(result->'metrics')='object' then rev:=(result#>>'{metrics,revenue}')::numeric;
 elsif jsonb_typeof(result->'metrics')='array' then select (m->>'value')::numeric into rev from jsonb_array_elements(result->'metrics')m where m->>'key'='revenue' limit 1;end if;
 if result?'metrics' then
  o:=public.hub_overhead_period_v1(p_tenant,p_year,p_months,p_filters,rev);
  result:=result||jsonb_build_object('overhead',o);
  if jsonb_typeof(result->'metrics')='array' then
   select jsonb_agg(jsonb_build_object('key',x.key,'label',x.label,'unit',x.unit,'value',o->x.field,'status',case when o->x.field='null'::jsonb then 'missing' else 'source' end,'basis',o->>'basis')) into metrics
   from (values('overhead','Overhead totalt','kr','total_overhead'),('management','Arbetsledning','kr','management_cost'),
    ('overhead_revenue','Overhead / omsättning','%','overhead_revenue_pct'),('management_revenue','Arbetsledning / omsättning','%','management_revenue_pct'),
    ('overhead_billable_hour','Overhead / debiterbar timme','kr/h','overhead_per_billable_hour'))x(key,label,unit,field);
   result:=jsonb_set(result,'{metrics}',result->'metrics'||metrics);
  end if;
 end if;
 foreach section in array array['month','ytd'] loop
  if jsonb_typeof(result->section)='object' then
   result:=jsonb_set(result,array[section],private.hub_kpi_overhead_projection_v1(p_tenant,p_year,
    case when section='ytd' then array(select value::int from jsonb_array_elements_text(result#>'{period,ytd_months}')) else p_months end,p_filters,result->section));
  end if;
 end loop;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION private.hub_kpi_prepared_overview_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_cost_center text DEFAULT NULL::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '30s'
 SET jit TO 'off'
AS $function$
declare internal_data jsonb; current_data jsonb; previous_data jsonb; filters jsonb; months integer[]; options jsonb; unclassified jsonb; previous_filters jsonb; comparison_available boolean;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501'; end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 select coalesce(jsonb_agg(jsonb_build_object('code',code,'name',name) order by code),'[]') into options from (select cost_center code,min(cost_center_name) name from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=private.hub_kpi_active_report_generation_v1(p_tenant_id)) where tenant_id=p_tenant_id group by cost_center union all select 'unclassified','Ej klassificerat') x;
 if p_cost_center is not null and exists(select 1 from unnest(string_to_array(p_cost_center,',')) requested(code) where not exists(select 1 from jsonb_array_elements(options) o where o->>'code'=requested.code)) then raise exception 'Okänt kostnadsställe'; end if;
 filters:=p_filters-'fiscal_year'-'selected_months'-'cost_center';
 if p_cost_center is not null then filters:=filters||jsonb_build_object('cost_center',p_cost_center);end if;
 current_data:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_fiscal_year,months,filters);
 previous_filters:=filters;
 if filters?'date_from' then previous_filters:=jsonb_set(previous_filters,'{date_from}',to_jsonb(((filters->>'date_from')::date-interval '1 year')::date));end if;
 if filters?'date_to' then previous_filters:=jsonb_set(previous_filters,'{date_to}',to_jsonb(((filters->>'date_to')::date-interval '1 year')::date));end if;
 previous_data:=private.hub_kpi_prepared_comparison_v1(p_tenant_id,p_fiscal_year-1,months,previous_filters);
 comparison_available:=jsonb_array_length(previous_data#>'{coverage,revenue_months}')=cardinality(months) and jsonb_array_length(previous_data#>'{coverage,cost_months}')=cardinality(months) and jsonb_array_length(current_data#>'{coverage,revenue_months}')=cardinality(months) and jsonb_array_length(current_data#>'{coverage,cost_months}')=cardinality(months);

 internal_data:=jsonb_build_object('status','deferred','total',null,'material',null,'tipp_deponi',null,'transport',null,'rows',null,'review_rows',null,'review_amount',null,'basis','Internt underlag hämtas separat så att ekonomirapporten kan öppnas direkt.');
 internal_data:=internal_data||jsonb_build_object('revenue_basis',(current_data#>>'{metrics,revenue}')::numeric,
 'total_percent',round((internal_data->>'total')::numeric/nullif((current_data#>>'{metrics,revenue}')::numeric,0)*100,2),
 'material_percent',round((internal_data->>'material')::numeric/nullif((current_data#>>'{metrics,revenue}')::numeric,0)*100,2),
 'tipp_deponi_percent',round((internal_data->>'tipp_deponi')::numeric/nullif((current_data#>>'{metrics,revenue}')::numeric,0)*100,2));
 return current_data||jsonb_build_object('internal_summary',internal_data,'driver_attendance',jsonb_build_object('status','missing_absence_data','attendance_percent',null,'sick_percent',null,'vab_percent',null,'vacation_percent',null,'other_absence_percent',null,'basis','TransPA-kopplingen har arbetad tid men saknar frånvaroaktiviteter och verifierad schematid. Frånvaroprocent kan inte beräknas.'),'sync',private.hub_kpi_report_status_v1(p_tenant_id),'previous',previous_data,'comparison_available',comparison_available,'cost_centers',options,'cost_center_scope',p_cost_center,'classification_valid_from',(select min(valid_from) from (select id,tenant_id,project_reference,project_name,cost_center,cost_center_name,business_group,registrations,valid_from,valid_to,source,created_at from private.hub_kpi_prepared_kpi_project_classification_periods where generation_id=private.hub_kpi_active_report_generation_v1(p_tenant_id)) where tenant_id=p_tenant_id),'metrics',current_data->'metrics'||jsonb_build_object('revenue_change_pct',case when comparison_available then round(((current_data#>>'{metrics,revenue}')::numeric/(nullif((previous_data#>>'{metrics,revenue}')::numeric,0))-1)*100,2) else null end));
end $function$
;
CREATE OR REPLACE FUNCTION private.hub_material_approved_cost_scopes_v1(p_tenant uuid)
 RETURNS TABLE(project text, valid_from date, cost_center text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 return query select unnest(u.projects),s.valid_from,s.project_cost_center from private.hub_kpi_material_separation_settings s
 join public.kpi_units u on u.id=s.material_unit_id and u.tenant_id=s.tenant_id
 where s.tenant_id=p_tenant and s.enabled and u.enabled and nullif(s.project_cost_scope_reference,'') is not null and nullif(s.project_cost_center,'') is not null;
end $function$
;
CREATE OR REPLACE FUNCTION private.hub_prepare_billable_hours_v1(p_tenant uuid, p_generation uuid, p_year integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required'using errcode='42501';end if;
 insert into private.hub_kpi_billable_hours_v1
 select f.generation_id,f.tenant_id,f.fiscal_year,split_part(f.fact_id,':',1),f.occurred_on,f.cost_center,f.business_group,f.unit_id,f.vehicle,f.project,
 case when (f.original->>'Summa') ~ '^-' then -abs(q.hours) else q.hours end,f.fact_id
 from private.hub_kpi_prepared_facts f
 cross join lateral(select case when trim(replace(f.original->>'Kvantitet',',','.')) ~ '^-?[0-9]+([.][0-9]+)?$' then trim(replace(f.original->>'Kvantitet',',','.'))::numeric end hours)q
 where f.tenant_id=p_tenant and f.generation_id=p_generation and (p_year is null or f.fiscal_year=p_year)
 and f.source='Workify' and f.kind='revenue' and f.amount<>0 and lower(trim(f.original->>'Enhet')) in('tim','timme','timmar','h','hour','hours')
 and lower(coalesce(f.original->>'Kundnamn','')) not like '%elleholms%maskin%'
 on conflict(generation_id,tenant_id,fact_id)do nothing;
end $function$
;
CREATE OR REPLACE FUNCTION public.hub_kpi_internal_summary_v1(p_tenant uuid, p_year integer, p_months integer[], p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare result jsonb;revenue numeric;
begin
 result:=private.hub_kpi_internal_overview_v1(p_tenant,p_year,private.hub_kpi_month_scope_v1(p_year,p_months),p_filters);
 revenue:=(private.hub_kpi_prepared_comparison_v1(p_tenant,p_year,p_months,p_filters)#>>'{metrics,revenue}')::numeric;
 return result||jsonb_build_object('revenue_basis',revenue,'total_percent',round((result->>'total')::numeric/nullif(revenue,0)*100,2),'material_percent',round((result->>'material')::numeric/nullif(revenue,0)*100,2),'tipp_deponi_percent',round((result->>'tipp_deponi')::numeric/nullif(revenue,0)*100,2));
end $function$
;
CREATE OR REPLACE FUNCTION public.hub_kpi_internal_transfers_v1(p_tenant_id uuid, p_from date, p_to date, p_months integer[] DEFAULT NULL::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET statement_timeout TO '45s'
 SET work_mem TO '64MB'
 SET jit TO 'off'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid period'; end if;
 if p_months is not null and (cardinality(p_months)=0 or exists(select 1 from unnest(p_months) m where m<1 or m>12 or m is null)) then raise exception 'Invalid months';end if;
 with ledger as materialized(select * from public.kpi_internal_transfer_ledger where tenant_id=p_tenant_id),
 project_keys as materialized(
 select k.identity_value,count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id
 from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
 where k.tenant_id=p_tenant_id and lower(o.object_type)='project' and k.confidence=1 and k.identity_type='next_project_number'
 group by k.identity_value
 ), vehicle_keys as materialized (
 select k.object_id,k.identity_type,upper(trim(k.identity_value)) normalized_value
 from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
 where k.tenant_id=p_tenant_id and lower(o.object_type)='vehicle' and k.confidence=1
 ), cost_scopes as materialized(select * from private.hub_material_approved_cost_scopes_v1(p_tenant_id)), classification as materialized (
 select * from public.kpi_project_classification_periods where tenant_id=p_tenant_id
 ), project_references as materialized (
  select k.identity_value,
   coalesce(case when count(distinct k.object_id)=1 then max(nullif(o.data->>'project_number','')) end,nullif(trim(k.identity_value),'')) reference
  from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
  where k.tenant_id=p_tenant_id and k.object_type='Project' and k.identity_type='next_project_number' and k.confidence=1
  group by k.identity_value
 ), article_rules as materialized (
  select a.id,a.article_number,a.valid_from,a.valid_to,a.target_type,a.cost_center,
   coalesce(ref.reference,nullif(trim(a.project_reference),'')) project_reference,
   case when exists(select 1 from jsonb_array_elements(a.source_rows) e where trim(e->'values'->>'Namn') ilike 'Tippavgift%') then 'tipp_deponi' else a.revenue_category end revenue_category
  from public.kpi_workify_article_rules a
  left join project_references ref on ref.identity_value=trim(a.project_reference)
  where a.tenant_id=p_tenant_id and a.enabled
 ), raw_base as materialized (
  select x.*,coalesce(nullif(x.external_transaction_id,''),md5(jsonb_build_array(x.source_data->>'Ordernummer',x.source_data->>'Artikelnummer',x.occurred_on,upper(trim(x.source_data->>'RegNr')))::text)) legacy_key,
   coalesce(ref.reference,nullif(regexp_replace(trim(coalesce(nullif(x.source_data->>'Littranummer',''),x.source_data->>'Projekt')),'^(AO)?([^[:space:]]+).*$', '\2','i'),'')) receiver_reference
  from public.kpi_import_rows x left join project_references ref on ref.identity_value=nullif(regexp_replace(trim(coalesce(nullif(x.source_data->>'Littranummer',''),x.source_data->>'Projekt')),'^(AO)?([^[:space:]]+).*$', '\2','i'),'') where x.tenant_id=p_tenant_id and x.data_kind='revenue'
   and lower(trim(x.source_data->>'Kundnamn'))='elleholms maskin ab'
   and private.hub_kpi_import_row_in_scope_v2(x.id,x.data_kind,x.occurred_on,x.amount,x.is_valid,x.validation_errors,x.source_data)
   and x.occurred_on between p_from and p_to and (p_months is null or extract(month from x.occurred_on)::integer=any(p_months))
 ), numbered as materialized (
  select x.*,row_number() over(partition by batch_id,legacy_key order by row_number,id) line_ordinal from raw_base x
 ), raw as materialized (
  select x.*,coalesce(old.source_key,nullif(x.external_transaction_id,''),'workify-line-v2:'||legacy_key||':'||line_ordinal) source_key,
   nullif(trim(source_data->>'RegNr'),'') is null and nullif(trim(source_data->>'Fordon'),'') is null project_fallback
  from numbered x left join lateral(
   select l.source_key from ledger l where l.tenant_id=p_tenant_id
   and (l.snapshot->>'row_id'=x.id::text or (l.source_key=x.legacy_key
    and jsonb_build_array(l.snapshot->'amount',l.snapshot->'quantity',l.snapshot->>'comment',l.snapshot->>'littra')
     =jsonb_build_array(x.amount,x.quantity,x.source_data->>'ArtikelKommentar',x.source_data->>'Littranummer')))
   order by (l.snapshot->>'row_id'=x.id::text) desc limit 1
  )old on true
 ), source_centers as materialized (
 select x.occurred_on,x.vehicle_label,count(distinct c.cost_center) n,min(c.cost_center) code
 from (select distinct occurred_on,upper(trim(source_data->>'RegNr')) vehicle_label from raw) x
 left join classification c on (x.vehicle_label=any(c.registrations) or (x.vehicle_label='LASTBIL' and c.project_reference='9009'))
 and c.valid_from<=x.occurred_on and (c.valid_to is null or c.valid_to>=x.occurred_on)
 group by x.occurred_on,x.vehicle_label
 ), linked as (
  select x.*,count(*) over(partition by source_key) duplicate_count,
   ar.revenue_category category,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' or project_fallback then 'project' else 'vehicle' end carrier_type,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' or project_fallback then case when ai.n=1 then ai.id end else case when vi.n=1 then vi.id end end carrier_id,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' then ar.project_reference else receiver_reference end carrier_reference,ac.name carrier_project_name,
   case when vi.n=1 then vi.id end vehicle_id,case when pi.n=1 then pi.id end receiver_id,
   case when ar.target_type='project' or ar.revenue_category='tipp_deponi' or project_fallback then coalesce(case when not project_fallback then ar.cost_center end,case when ac.n=1 then ac.code end) else case when sc.n=1 then sc.code end end source_center,coalesce(cost_scope.project_cost_center,case when rc.n=1 then rc.code else '10' end) receiver_center,
   (cost_scope.project_cost_center is null and rc.n<>1) receiver_defaulted,
   rc.name receiver_name
  from raw x
  left join lateral(select s.cost_center project_cost_center from cost_scopes s where s.project=x.receiver_reference and s.valid_from<=x.occurred_on order by s.valid_from desc limit 1)cost_scope on true
  left join lateral(select count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id from vehicle_keys k where true
   and ((x.vehicle_object_id is not null and k.object_id=x.vehicle_object_id) or
   (x.vehicle_object_id is null and ((k.identity_type='registration_number' and k.normalized_value=upper(trim(x.source_data->>'RegNr'))) or (k.identity_type='workify_vehicle_label' and k.normalized_value=upper(trim(x.source_data->>'RegNr'))))))) vi on true
  left join project_keys pi on pi.identity_value=x.receiver_reference
  left join lateral(select a.target_type,a.project_reference,a.cost_center,a.revenue_category from article_rules a
   where a.article_number=x.source_data->>'Artikelnummer' and x.occurred_on>=a.valid_from and (a.valid_to is null or x.occurred_on<=a.valid_to)
   order by a.valid_from desc,a.id limit 1) ar on true
  left join project_keys ai on ai.identity_value=case when ar.target_type='project' or ar.revenue_category='tipp_deponi' then ar.project_reference else case when project_fallback then x.receiver_reference end end
  left join lateral(select count(distinct c.cost_center) n,min(c.cost_center) code,min(c.project_name) name from classification c
   where c.tenant_id=p_tenant_id and c.project_reference=case when ar.target_type='project' or ar.revenue_category='tipp_deponi' then ar.project_reference else case when project_fallback then x.receiver_reference end end
   and c.valid_from<=x.occurred_on and (c.valid_to is null or c.valid_to>=x.occurred_on)) ac on true
  left join source_centers sc on sc.occurred_on=x.occurred_on and sc.vehicle_label is not distinct from upper(trim(x.source_data->>'RegNr'))
  left join lateral(select count(distinct c.cost_center) n,min(c.cost_center) code,min(c.project_name) name from classification c
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
  from linked where amount<>0 and not(coalesce(category,'')='ignored' and coalesce(amount=0,false))
 ), finalized as (
  select p.payload||jsonb_build_object('export_id',l.export_id,'booking_reference',l.booking_reference,
   'status',case when l.source_key is null then case when (p.payload->>'ready')::boolean then 'new' else 'review' end
    when (p.payload - 'row_id' - 'line_ordinal') is distinct from (l.snapshot - 'row_id' - 'line_ordinal') then 'changed'
    when l.posted_at is not null then 'posted' else 'exported' end) payload from prepared p
  left join ledger l on l.tenant_id=p_tenant_id and l.source_key=p.source_key
 ) select jsonb_build_object('rows',coalesce(jsonb_agg(payload order by payload->>'occurred_on',payload->>'order'),'[]'::jsonb),'count',count(*)) into result from finalized;
 if (result->>'count')::integer>10000 then raise exception 'Select a smaller period; no rows truncated';end if;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION public.hub_kpi_monthly_transport_report_v1(p_tenant_id uuid, p_fiscal_year integer, p_month integer, p_cost_center text DEFAULT '30'::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare generation uuid;revision integer;report jsonb;center text:=coalesce(nullif(trim(p_cost_center),''),'');
 date_from date;date_to date;control numeric;workify numeric;control_ref text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 perform private.hub_kpi_month_scope_v1(p_fiscal_year,array[p_month]);
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>2000 or exists(select 1 from jsonb_object_keys(p_filters)k where k not in('group','unit','vehicle','project'))then raise exception 'Unsupported monthly report filter';end if;
 if length(center)>100 then raise exception 'Invalid cost center';end if;
 select active_generation,correction_revision into generation,revision from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then raise exception 'Prepared report required';end if;
 select c.report into report from private.hub_kpi_monthly_report_cache c where c.tenant_id=p_tenant_id and c.generation_id=generation and c.correction_revision=revision and c.fiscal_year=p_fiscal_year and c.month=p_month and c.cost_center=center and c.filters=p_filters;
 if found then return private.hub_kpi_overhead_projection_v1(p_tenant_id,p_fiscal_year,array[p_month],p_filters||case when center='' then '{}'::jsonb else jsonb_build_object('cost_center',center)end,private.hub_kpi_mapped_units_projection_v1(p_tenant_id,report));end if;
 if not pg_try_advisory_xact_lock(hashtextextended(concat_ws(':','monthly-report',p_tenant_id,generation,revision,p_fiscal_year,p_month,center,p_filters::text),0))then raise exception 'Månadsrapporten förbereds redan. Försök igen om en stund.'using errcode='55P03';end if;
 report:=private.hub_kpi_monthly_transport_report_base_v1(p_tenant_id,p_fiscal_year,p_month,nullif(center,''),p_filters);
 date_from:=(report#>>'{period,from}')::date;date_to:=(report#>>'{period,to}')::date;
 if p_filters='{}'::jsonb then
  select amount,reference into control,control_ref from private.hub_workify_period_controls where tenant_id=p_tenant_id and period_from=date_from and period_to=date_to and cost_center=center and currency='SEK' limit 1;
  if control is not null then
   select coalesce(sum(amount),0)into workify from private.hub_kpi_prepared_facts where tenant_id=p_tenant_id and generation_id=generation and fiscal_year=p_fiscal_year and occurred_on between date_from and date_to and cost_center=center and source='Workify' and kind='revenue';
   report:=report||jsonb_build_object('reconciliation',jsonb_build_object('status',case when abs(workify-control)>0.005 then 'needs_review' else 'matches_control' end,'workify_in_kpi',workify,'reported_workify',control,'difference',workify-control,'reference',control_ref,'basis','Uppgivet Workify-belopp jämförs med publicerat underlag; differensen ändrar inte intäkten automatiskt.'));
   if abs(workify-control)>0.005 then
    report:=jsonb_set(report,'{month,metrics,0,status}','"partial"'::jsonb);
    report:=jsonb_set(report,'{month,metrics,1,status}','"partial"'::jsonb);
    report:=jsonb_set(report,'{ytd,metrics,0,status}','"partial"'::jsonb);
    report:=jsonb_set(report,'{ytd,metrics,1,status}','"partial"'::jsonb);
   end if;
  end if;
 end if;
 report:=report||jsonb_build_object('correction_revision',revision);
 insert into private.hub_kpi_monthly_report_cache(tenant_id,generation_id,correction_revision,fiscal_year,month,cost_center,filters,report)
 values(p_tenant_id,generation,revision,p_fiscal_year,p_month,center,p_filters,report)on conflict do nothing;
 return private.hub_kpi_overhead_projection_v1(p_tenant_id,p_fiscal_year,array[p_month],p_filters||case when center='' then '{}'::jsonb else jsonb_build_object('cost_center',center)end,private.hub_kpi_mapped_units_projection_v1(p_tenant_id,report));
end $function$
;
CREATE OR REPLACE FUNCTION public.hub_kpi_overview_months_v1(p_tenant_id uuid, p_fiscal_year integer, p_selected_months integer[], p_cost_center text DEFAULT NULL::text, p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
#variable_conflict use_variable
declare generation uuid;revision integer;months integer[];report jsonb;center text:=coalesce(p_cost_center,'');
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object' or length(p_filters::text)>4000 or length(center)>100 then raise exception 'Ogiltigt rapporturval';end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 select active_generation,correction_revision into generation,revision from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 select c.report into report from private.hub_kpi_overview_cache_v1 c where c.tenant_id=p_tenant_id and c.generation_id=generation and c.revision=revision and c.fiscal_year=p_fiscal_year and c.months=months and c.center=center and c.filters=p_filters;
 if found then return report;end if;
 if not pg_try_advisory_xact_lock(hashtextextended(concat_ws(':','kpi-overview',p_tenant_id,generation,revision,p_fiscal_year,months,center,p_filters),0))then raise exception 'Rapporten förbereds redan. Försök igen om en stund.'using errcode='55P03';end if;
 report:=private.hub_kpi_overhead_projection_v1(p_tenant_id,p_fiscal_year,months,
 case when p_cost_center is null then p_filters else p_filters||jsonb_build_object('cost_center',p_cost_center)end,
 private.hub_kpi_mapped_units_projection_v1(p_tenant_id,private.hub_kpi_prepared_overview_v1(p_tenant_id,p_fiscal_year,months,p_cost_center,p_filters)));
 insert into private.hub_kpi_overview_cache_v1(tenant_id,generation_id,revision,fiscal_year,months,center,filters,report) values(p_tenant_id,generation,revision,p_fiscal_year,months,center,p_filters,report)on conflict do nothing;
 return report;
end $function$
;
CREATE OR REPLACE FUNCTION public.hub_overhead_month_save_v1(p_tenant uuid, p_month date, p_center text, p_management numeric, p_other numeric, p_evidence text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare before_row jsonb;after_row jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required'using errcode='42501';end if;
 if p_month is null or p_month<>date_trunc('month',p_month)::date or p_management is null or p_other is null or p_management<0 or p_other<0 or p_management='NaN'::numeric or p_other='NaN'::numeric or p_management>1000000000 or p_other>1000000000 or length(trim(p_evidence)) not between 3 and 1000 or p_evidence is null then raise exception 'Ogiltigt månadsunderlag';end if;
 if not exists(select 1 from public.kpi_project_classification_periods where tenant_id=p_tenant and cost_center=p_center)then raise exception 'Okänt kostnadsställe';end if;
 perform pg_advisory_xact_lock(hashtextextended(concat_ws(':','overhead-month',p_tenant,p_month,p_center),0));
 select to_jsonb(s) into before_row from private.hub_overhead_months_v1 s where tenant_id=p_tenant and month_start=p_month and cost_center=p_center;
 insert into private.hub_overhead_months_v1(tenant_id,month_start,cost_center,management_cost,other_overhead,evidence,updated_by)
 values(p_tenant,p_month,p_center,p_management,p_other,trim(p_evidence),auth.uid())
 on conflict(tenant_id,month_start,cost_center)do update set management_cost=excluded.management_cost,other_overhead=excluded.other_overhead,evidence=excluded.evidence,updated_by=excluded.updated_by,updated_at=now() returning to_jsonb(hub_overhead_months_v1.*) into after_row;
 insert into private.hub_overhead_month_events_v1(tenant_id,month_start,cost_center,before_value,after_value,actor)values(p_tenant,p_month,p_center,before_row,after_row,auth.uid());
 update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=p_tenant;
end $function$
;
CREATE OR REPLACE FUNCTION public.hub_overhead_period_v1(p_tenant uuid, p_year integer, p_months integer[], p_filters jsonb DEFAULT '{}'::jsonb, p_revenue numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare result jsonb;months integer[];generation uuid;management numeric;other_cost numeric;hours numeric;covered integer;expected integer;unsupported boolean;missing_hours integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 months:=private.hub_kpi_month_scope_v1(p_year,p_months);
 generation:=private.hub_kpi_active_report_generation_v1(p_tenant);
 unsupported:=p_filters ?| array['group','unit','vehicle','project'];
 with centers as(select distinct cost_center from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=generation and fiscal_year=p_year and extract(month from occurred_on)::int=any(months) and (not(p_filters?'cost_center')or cost_center=any(string_to_array(p_filters->>'cost_center',',')))),
 dates as(select make_date(case when m>=9 then p_year else p_year+1 end,m,1) dt from unnest(months)m),
 scopes as(select c.cost_center,d.dt from centers c cross join dates d)
 select count(*),count(s.month_start),sum(s.management_cost),sum(s.other_overhead) into expected,covered,management,other_cost from scopes x left join private.hub_overhead_months_v1 s on s.tenant_id=p_tenant and s.cost_center=x.cost_center and s.month_start=x.dt;
 -- Distinct accepted source rows prevent article splitting/overlaps duplicating hours.
 with accepted as(select f.source_row_id,case when count(distinct f.hours)<=1 then max(f.hours) end hours from private.hub_kpi_billable_hours_v1 f
 where f.tenant_id=p_tenant and f.generation_id=generation and f.fiscal_year=p_year and extract(month from f.occurred_on)::int=any(months)
 and (not(p_filters?'cost_center')or f.cost_center=any(string_to_array(p_filters->>'cost_center',',')))
 and (not(p_filters?'group')or f.business_group=any(string_to_array(p_filters->>'group',',')))
 and (not(p_filters?'unit')or f.unit_id::text=p_filters->>'unit')
 and (not(p_filters?'vehicle')or f.vehicle=p_filters->>'vehicle') and (not(p_filters?'project')or f.project=p_filters->>'project')
 group by f.source_row_id)
 select sum(a.hours),count(*)filter(where a.hours is null) into hours,missing_hours from accepted a;
 if missing_hours>0 then hours:=null;end if;
 if unsupported or expected=0 or covered<>expected then management:=null;other_cost:=null;end if;
 result:=jsonb_build_object('management_cost',management,'other_overhead',other_cost,'total_overhead',management+other_cost,
 'revenue',p_revenue,'overhead_revenue_pct',round((management+other_cost)/nullif(p_revenue,0)*100,2),
 'management_revenue_pct',round(management/nullif(p_revenue,0)*100,2),'management_overhead_pct',round(management/nullif(management+other_cost,0)*100,2),
 'billable_hours',hours,'billable_rows_missing_quantity',missing_hours,'overhead_per_billable_hour',round((management+other_cost)/nullif(hours,0),2),
 'management_per_billable_hour',round(management/nullif(hours,0),2),'status',case when unsupported then 'unsupported_scope' when management is null then 'missing_cost_evidence' when hours is null or hours<=0 then 'missing_billable_hours' else 'source' end,
 'covered_month_scopes',covered,'expected_month_scopes',expected,
 'basis','Overhead = arbetsledning inklusive lönebikostnader + övrig overhead enligt verifierat månadsunderlag. Arbetsledning ingår i overheadsumman. Debiterbara timmar = unika godkända Workify-artikelrader med timenhet, externa kunder och belopp i rapporten. Kreditrader minskar timmarna. Nyckeltalen kompletterar rapporten och ändrar inte bokförda kostnader.',
 'missing_reason',case when unsupported then 'Overheadunderlaget gäller kostnadsställen. Fördelning till vald grupp eller enhet är inte verifierad.' when management is null then 'Verifierat underlag för arbetsledning och övrig overhead saknas för en eller flera månader/kostnadsställen.' end);
 return result;
end $function$
;CREATE OR REPLACE FUNCTION private.hub_kpi_run_report_jobs_v1()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
 SET work_mem TO '32MB'
AS $function$
declare job record; generation uuid; first_year integer; last_year integer; yr integer;
 claims text:=current_setting('request.jwt.claims',true); subject text:=current_setting('request.jwt.claim.sub',true);
 phase text; phase_started timestamptz; metrics jsonb; failure_context text; failure_message text;
 local_now timestamp:=clock_timestamp() at time zone 'Europe/Stockholm';
begin
 if not pg_try_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0)) then return;end if;
 if local_now::time>=time '03:20' then
 update private.hub_kpi_report_state set status='queued',requested_at=clock_timestamp(),last_nightly_date=local_now::date,error_code=null
 where (last_nightly_date is null or last_nightly_date<local_now::date) and status<>'queued';
 end if;
 for job in select * from private.hub_kpi_report_state where status='queued' order by requested_at for update skip locked loop
 begin
 perform pg_advisory_xact_lock(hashtextextended('workify-file-import:'||job.tenant_id::text,0));
phase:='snapshot'; phase_started:=clock_timestamp(); metrics:='{}'::jsonb;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',job.requested_by,'role','authenticated')::text,true);
 perform set_config('request.jwt.claim.sub',job.requested_by::text,true);
 if not public.hub_has_permission(job.tenant_id,'kpi.manage') then raise exception 'Report job permission revoked' using errcode='42501';end if;
 last_year:=extract(year from local_now)::integer-case when extract(month from local_now)<9 then 1 else 0 end+1;
 select least(last_year-5,coalesce(min(extract(year from occurred_on)::integer-case when extract(month from occurred_on)<9 then 1 else 0 end),last_year-5)) into first_year
 from public.kpi_import_rows where tenant_id=job.tenant_id and is_valid and data_kind in ('revenue','cost') and occurred_on is not null;
 if first_year<2000 then raise exception 'Invalid historical fiscal year';end if;
 insert into private.hub_kpi_report_generations(tenant_id,first_fiscal_year,last_fiscal_year) values(job.tenant_id,first_year,last_year) returning id into generation;
 insert into private.hub_kpi_prepared_hub_objects select generation,t.* from public.hub_objects t where tenant_id=job.tenant_id and object_type in ('Vehicle','FuelTransaction');
 insert into private.hub_kpi_prepared_fuel_reviews select generation,t.* from public.kpi_bsmart_cost_reviews t where t.tenant_id=job.tenant_id;
 insert into private.hub_kpi_prepared_fuel_state(generation_id,last_connector_success,connector_status) select generation,max(last_success_at),max(status) from public.hub_connections where tenant_id=job.tenant_id and connector_type='piusi_bsmart';
insert into private.hub_kpi_prepared_hub_transpa_entities select generation,t.* from public.hub_transpa_entities t where tenant_id=job.tenant_id and entity_type='vehicle';
insert into private.hub_kpi_prepared_hub_vehicle_meter_readings select generation,t.* from public.hub_vehicle_meter_readings t where tenant_id=job.tenant_id and reading_type='odometer_km';
insert into private.hub_kpi_prepared_kpi_business_groups select generation,t.* from public.kpi_business_groups t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_import_rows select generation,t.* from public.kpi_import_rows t where tenant_id=job.tenant_id and data_kind='next_historical_time';
insert into private.hub_kpi_prepared_kpi_project_classification_periods select generation,t.* from public.kpi_project_classification_periods t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_settings select generation,t.* from public.kpi_settings t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_transpa_time_facts select generation,t.* from public.kpi_transpa_time_facts t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_unit_periods select generation,t.* from public.kpi_unit_periods t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_units select generation,t.* from public.kpi_units t where tenant_id=job.tenant_id;
insert into private.hub_kpi_prepared_kpi_vehicle_distance_periods select generation,t.* from public.kpi_vehicle_distance_periods t where tenant_id=job.tenant_id;
 analyze private.hub_kpi_prepared_hub_objects;
 analyze private.hub_kpi_prepared_kpi_unit_periods;
 analyze private.hub_kpi_prepared_kpi_project_classification_periods;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='daily_time'; phase_started:=clock_timestamp();
 insert into private.hub_kpi_prepared_daily
 select generation,d.* from public.kpi_transpa_vehicle_time_daily_secure(job.tenant_id,'2000-01-01',make_date(last_year+1,8,31)) d;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='financial_facts'; phase_started:=clock_timestamp();
 for yr in first_year..last_year loop
 insert into private.hub_kpi_prepared_facts select generation,job.tenant_id,yr,f.*,jsonb_build_object('time_report_id',f.original->'time_report_id','_humla_distribution',jsonb_build_object('status',f.original#>'{_humla_distribution,status}'))
 from private.hub_kpi_filtered_classified_facts_v1(job.tenant_id,make_date(yr,9,1),make_date(yr+1,8,31),'{}') f;
 end loop;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 -- The new generation is invisible to autovacuum until commit. Refresh the
 -- planner's estimates here, before updates and joins on those new rows.
 analyze private.hub_kpi_prepared_facts;
 phase:='material'; phase_started:=clock_timestamp();
 perform private.hub_kpi_separate_material_v1(job.tenant_id,generation);
 perform private.hub_material_project_cost_scope_v1(job.tenant_id,generation);
 update private.hub_kpi_prepared_facts set display_original=display_original||jsonb_build_object('_humla_material_separation',original->'_humla_material_separation') where generation_id=generation and original?'_humla_material_separation';

 update private.hub_kpi_prepared_facts set display_original=display_original||jsonb_build_object('_humla_invoice',jsonb_build_object(
 'order_number',nullif(trim(original->>'Ordernummer'),''),
 'article_date',private.hub_kpi_workify_date_v1(original->>'Artikeldatum'),
 'invoice_date',private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),''))),
 'invoice_text',coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),'')),
 'customer_name',original->>'Kundnamn',
 'end_text',coalesce(nullif(trim(original->>'Slutdatum'),''),nullif(trim(original->>'PlaneradKlart'),'')),
 'end_date',private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Slutdatum'),''),nullif(trim(original->>'PlaneradKlart'),'')))))
 where generation_id=generation and source='Workify' and kind='revenue';
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='fuel'; phase_started:=clock_timestamp();
 perform private.hub_kpi_prepare_piusi_facts_v1(job.tenant_id,generation);
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='display'; phase_started:=clock_timestamp();
 insert into private.hub_kpi_prepared_display_facts select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original as original from private.hub_kpi_prepared_facts where generation_id=generation;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='distance'; phase_started:=clock_timestamp();
 insert into private.hub_kpi_prepared_month_distance
 select generation,job.tenant_id,v.vehicle_id,m.dt::date,(m.dt+interval '1 month'-interval '1 day')::date,
 private.hub_kpi_interpolated_distance_v1(job.tenant_id,v.vehicle_id,m.dt::date,(m.dt+interval '1 month'-interval '1 day')::date)
 from (select distinct vehicle_id from private.hub_kpi_prepared_hub_vehicle_meter_readings where generation_id=generation) v
 cross join generate_series(make_date(first_year,9,1)::timestamp,make_date(last_year+1,8,1)::timestamp,interval '1 month') m(dt);
 if exists(select 1 from private.hub_kpi_prepared_facts where generation_id=generation and (amount is null or amount='NaN'::numeric or occurred_on is null)) then
 raise exception 'Invalid prepared financial facts';end if;
 perform private.hub_ps_validate_fuel_v1(job.tenant_id,generation);
perform private.hub_next_validate_revenue_identity_v1(job.tenant_id,generation);
perform private.hub_next_validate_completeness_v1(job.tenant_id,generation);
perform private.hub_next_validate_reexport_generation_v1(job.tenant_id,generation);
perform private.hub_workify_validate_approved_generation_v1(job.tenant_id,generation);
perform private.hub_apply_cost_allocation_v1(job.tenant_id,generation);
perform private.hub_prepare_billable_hours_v1(job.tenant_id,generation);
update private.hub_kpi_report_generations set completed_at=clock_timestamp() where id=generation;
 update private.hub_kpi_report_state set active_generation=generation,synced_at=clock_timestamp(),status='ready',error_code=null,
 last_nightly_date=case when local_now::time>=time '03:20' then local_now::date else last_nightly_date end where tenant_id=job.tenant_id;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 phase:='cleanup'; phase_started:=clock_timestamp();
 -- Retain the latest two derived generations, never remove raw Hub data.
 delete from private.hub_kpi_report_generations where tenant_id=job.tenant_id and id not in
 (select id from private.hub_kpi_report_generations where tenant_id=job.tenant_id order by completed_at desc nulls last limit 2);
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 update private.hub_kpi_report_state set last_job_metrics=metrics,last_error_details=null where tenant_id=job.tenant_id;
 exception when query_canceled or others then
 get stacked diagnostics failure_context=PG_EXCEPTION_CONTEXT,failure_message=MESSAGE_TEXT;
 metrics:=metrics||jsonb_build_object(phase,extract(epoch from(clock_timestamp()-phase_started)));
 update private.hub_kpi_report_state set status='failed',error_code=sqlstate,last_job_metrics=metrics,last_error_details=jsonb_build_object('phase',phase,'message',failure_message,'context',failure_context) where tenant_id=job.tenant_id;
 raise log 'KPI report preparation failed: tenant %, SQLSTATE %',job.tenant_id,sqlstate;
 end;
 end loop;
 perform set_config('request.jwt.claims',coalesce(claims,''),true);
 perform set_config('request.jwt.claim.sub',coalesce(subject,''),true);
end $function$
;
revoke all on function private.hub_prepare_billable_hours_v1(uuid,uuid,integer) from public,anon,authenticated;
revoke all on function public.hub_overhead_month_save_v1(uuid,date,text,numeric,numeric,text), public.hub_overhead_period_v1(uuid,integer,integer[],jsonb,numeric), private.hub_kpi_overhead_projection_v1(uuid,integer,integer[],jsonb,jsonb),public.hub_kpi_internal_summary_v1(uuid,integer,integer[],jsonb),private.hub_material_approved_cost_scopes_v1(uuid),public.hub_kpi_overview_months_v1(uuid,integer,integer[],text,jsonb) from public,anon;
grant execute on function public.hub_overhead_month_save_v1(uuid,date,text,numeric,numeric,text),public.hub_overhead_period_v1(uuid,integer,integer[],jsonb,numeric),private.hub_kpi_overhead_projection_v1(uuid,integer,integer[],jsonb,jsonb),public.hub_kpi_internal_summary_v1(uuid,integer,integer[],jsonb),private.hub_material_approved_cost_scopes_v1(uuid),public.hub_kpi_overview_months_v1(uuid,integer,integer[],text,jsonb) to authenticated;
alter function private.hub_kpi_prepared_comparison_v1(uuid,integer,integer[],jsonb) set jit='off';
alter function private.hub_kpi_internal_overview_v1(uuid,integer,integer[],jsonb) set jit='off';
