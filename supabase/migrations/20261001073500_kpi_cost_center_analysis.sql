create table public.kpi_project_classification_periods (
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.hub_tenants(id),
 project_reference text not null,project_name text not null,cost_center text not null,cost_center_name text not null,
 business_group text,registrations text[] not null default '{}',valid_from date not null,valid_to date,
 source jsonb not null,created_at timestamptz not null default now(),
 unique(tenant_id,project_reference,valid_from),check(valid_to is null or valid_to>=valid_from)
);
create index kpi_project_classification_dates on public.kpi_project_classification_periods(tenant_id,project_reference,valid_from,valid_to);
create index kpi_project_classification_registrations on public.kpi_project_classification_periods using gin(registrations);
alter table public.kpi_project_classification_periods enable row level security;
revoke all on public.kpi_project_classification_periods from anon,authenticated;
grant select on public.kpi_project_classification_periods to authenticated;
create policy kpi_project_classification_read on public.kpi_project_classification_periods for select to authenticated using(public.hub_has_permission(tenant_id,'kpi.read'));

create function private.hub_kpi_classified_facts_v1(p_tenant_id uuid,p_from date,p_to date)
returns table(fact_id text,occurred_on date,kind text,amount numeric,category text,project text,vehicle text,unit_id uuid,unit_name text,business_group text,source text,description text,account text,file_name text,row_number integer,original jsonb,cost_center text,cost_center_name text,classification_source jsonb)
language sql stable security definer set search_path='' as $function$
 with facts as materialized(select * from private.hub_kpi_financial_facts_v1(p_tenant_id,p_from,p_to)),
 registry as materialized(select * from public.kpi_project_classification_periods where tenant_id=p_tenant_id and valid_from<=p_to and (valid_to is null or valid_to>=p_from))
 select f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,
  case when own_group.has_group then f.business_group when explicit_group.has_group then f.business_group
   when cc.center_count>1 or bg.group_count>1 then 'Ej klassificerat' else coalesce(bg.group_name,f.business_group) end,
  f.source,f.description,f.account,f.file_name,f.row_number,f.original,
  case when cc.center_count=1 then cc.code else 'unclassified' end,
  case when cc.center_count=1 then cc.name else 'Ej klassificerat' end,
  jsonb_build_object('registry_sources',cc.sources,'reason',case when cc.center_count>1 then 'conflicting_cost_centers' when cc.center_count=0 then 'missing_cost_center' else 'exact_dated_reference' end)
 from facts f
 left join lateral(
  select count(distinct r.cost_center) center_count,min(r.cost_center) code,min(r.cost_center_name) name,jsonb_agg(distinct r.source) sources
  from registry r where r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
  and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id'))
 ) cc on true
 left join lateral(
  with candidates as(select r.business_group,case when r.project_reference=f.project then 1 when f.vehicle=any(r.registrations) then 2 else 3 end priority
   from registry r where r.business_group is not null and r.valid_from<=f.occurred_on and (r.valid_to is null or r.valid_to>=f.occurred_on)
   and (r.project_reference=f.project or f.vehicle=any(r.registrations) or (f.source='TransPA' and r.project_reference=f.original->>'employee_id')))
  select count(distinct business_group) group_count,case when count(distinct business_group)=1 then min(business_group) end group_name from candidates where priority=(select min(priority) from candidates)
 ) bg on true
 left join lateral(select exists(select 1 from public.kpi_unit_periods p where p.tenant_id=p_tenant_id and p.unit_id=f.unit_id and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on) and nullif(p.payload->>'business_group_id','') is not null) has_group) own_group on true
 left join lateral(select exists(select 1 from public.kpi_project_business_groups p where p.tenant_id=p_tenant_id and p.project_reference=f.project and p.source='kpi_admin_dated' and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)) has_group) explicit_group on true;
$function$;
revoke all on function private.hub_kpi_classified_facts_v1(uuid,date,date) from public,anon;
grant execute on function private.hub_kpi_classified_facts_v1(uuid,date,date) to authenticated;
CREATE OR REPLACE FUNCTION public.hub_kpi_analysis_v2(p_tenant_id uuid, p_from date, p_to date, p_filters jsonb DEFAULT '{}'::jsonb, p_level text DEFAULT 'group'::text, p_grain text DEFAULT 'month'::text, p_page integer DEFAULT 0, p_export boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 if p_level not in ('group','unit','project','transaction') or p_grain not in ('year','month','week','day') or p_page<0 then raise exception 'Invalid analysis filter';end if;
 with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)), scoped as (
  select f.* from facts f where
   (not(p_filters?'cost_center') or f.cost_center=p_filters->>'cost_center') and
   (not(p_filters?'group') or f.business_group=p_filters->>'group') and
   (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit') and
   (not(p_filters?'vehicle') or f.vehicle=p_filters->>'vehicle') and
   (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project') and
   (not(p_filters?'category') or f.category=p_filters->>'category') and
   (not(p_filters?'kind') or f.kind=p_filters->>'kind') and
   (not(p_filters?'source') or f.source=p_filters->>'source') and
   (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date) and
   (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)
 ), summary as (
  select round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(amount) filter(where source='NEXT'),0),2) next_cost,round(coalesce(sum(amount) filter(where source='TransPA'),0),2) personnel_cost,count(*) rows from scoped
 ), keyed as (
  select *,case p_level when 'group' then business_group when 'unit' then coalesce(unit_id::text,'vehicle:'||vehicle,'unassigned') when 'project' then coalesce(project,'unassigned') else fact_id end group_key,
   case p_level when 'group' then business_group when 'unit' then coalesce(unit_name,vehicle,'Ej fördelat') when 'project' then coalesce(project,'Ej projektfördelat') else coalesce(description,fact_id) end group_label
  from scoped
 ), groups as (
  select group_key key,max(group_label) label,count(*) rows,round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,
   round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(case when kind='revenue' then amount else -amount end),0),2) result from keyed group by group_key
 ), periods as (
  select case p_grain when 'year' then make_date(extract(year from occurred_on)::int-case when extract(month from occurred_on)<9 then 1 else 0 end,9,1) else date_trunc(p_grain,occurred_on)::date end period_start,
   round(coalesce(sum(amount) filter(where kind='revenue'),0),2) revenue,round(coalesce(sum(amount) filter(where kind='cost'),0),2) cost,
   round(coalesce(sum(case when kind='revenue' then amount else -amount end),0),2) result,count(*) rows from scoped group by 1
 ), page_rows as (select * from scoped order by occurred_on desc,fact_id limit case when p_export then 50001 else 100 end offset case when p_export then 0 else p_page*100 end)
 select jsonb_build_object('period',jsonb_build_object('from',p_from,'to',p_to),'filters',p_filters,'level',p_level,'grain',p_grain,'page',p_page,
  'summary',(select to_jsonb(s)||jsonb_build_object('result',revenue-cost,'margin_pct',case when revenue<>0 then round((revenue-cost)/revenue*100,2) else null end) from summary s),
  'groups',coalesce((select jsonb_agg(to_jsonb(g) order by g.label) from groups g),'[]'),
  'periods',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('period_end',least(p_to,coalesce((p_filters->>'date_to')::date,p_to),case p_grain when 'year' then (period_start+interval '1 year'-interval '1 day')::date when 'month' then (period_start+interval '1 month'-interval '1 day')::date when 'week' then period_start+6 else period_start end),'period_start',greatest(p_from,coalesce((p_filters->>'date_from')::date,p_from),period_start)) order by period_start) from periods p),'[]'),
  'transactions',coalesce((select jsonb_agg(to_jsonb(r)) from page_rows r),'[]'),
  'page_size',100,'export_limit_exceeded',(select count(*)>50000 from scoped)
 ) into result;
 return result;
end $function$;

revoke all on function public.hub_kpi_analysis_v2(uuid,date,date,jsonb,text,text,integer,boolean) from public,anon;
grant execute on function public.hub_kpi_analysis_v2(uuid,date,date,jsonb,text,text,integer,boolean) to authenticated;
