create table if not exists private.hub_kpi_accounting_references(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.hub_tenants(id),
 date_from date not null,date_to date not null,cost_center text not null,revenue numeric not null,result numeric not null,
 source jsonb not null,original_base64 text not null,created_by uuid not null,created_at timestamptz not null default now(),
 check(date_from<=date_to)
);
create unique index if not exists hub_kpi_accounting_reference_source on private.hub_kpi_accounting_references(tenant_id,date_from,date_to,cost_center,(source->>'sha256'));
alter table private.hub_kpi_accounting_references enable row level security;
revoke all on private.hub_kpi_accounting_references from public,anon,authenticated;
create or replace function public.hub_kpi_save_accounting_reference_v1(p_tenant_id uuid,p_from date,p_to date,p_cost_center text,p_source jsonb,p_original text)returns jsonb
language plpgsql security definer set search_path=''as $$
declare center text;rid uuid;revenue numeric;result numeric;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant_id,'kpi.manage')then raise exception 'KPI administrator required'using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to or p_cost_center is null or p_cost_center!~'^(10|20|30|40|50|60|90)(,(10|20|30|40|50|60|90))*$'or p_source is null or jsonb_typeof(p_source)<>'object'or length(p_source::text)>20000 then raise exception 'Invalid reference scope';end if;
 if p_original is null or length(p_original)>4500000 or p_source->>'sha256'is null or p_source->>'sha256'!~'^[a-f0-9]{64}$'or encode(extensions.digest(decode(p_original,'base64'),'sha256'),'hex')<>p_source->>'sha256'then raise exception 'Original hash mismatch';end if;
 revenue:=(p_source#>>'{metrics,revenue,value}')::numeric;result:=(p_source#>>'{metrics,result,value}')::numeric;
 if revenue is null or result is null or abs(revenue)>1e12 or abs(result)>1e12 or revenue='NaN'::numeric or result='NaN'::numeric then raise exception 'Invalid source totals';end if;
 select string_agg(distinct c,','order by c)into center from string_to_table(p_cost_center,',')c;
 insert into private.hub_kpi_accounting_references(tenant_id,date_from,date_to,cost_center,revenue,result,source,original_base64,created_by)
 values(p_tenant_id,p_from,p_to,center,revenue,result,p_source,p_original,auth.uid())on conflict do nothing returning id into rid;
 if rid is null then select id into rid from private.hub_kpi_accounting_references where tenant_id=p_tenant_id and date_from=p_from and date_to=p_to and cost_center=center and source->>'sha256'=p_source->>'sha256';end if;
 return jsonb_build_object('id',rid,'from',p_from,'to',p_to,'cost_center',center,'revenue',revenue,'result',result);
end $$;
revoke all on function public.hub_kpi_save_accounting_reference_v1(uuid,date,date,text,jsonb,text)from public,anon;
grant execute on function public.hub_kpi_save_accounting_reference_v1(uuid,date,date,text,jsonb,text)to authenticated;
create or replace function private.hub_kpi_management_accounting_basis_v1(p_tenant uuid,p_year int,p_months int[],p_filters jsonb,p_report jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare ref private.hub_kpi_accounting_references;report_revenue numeric;report_result numeric;period_from date;period_to date;center text;sources jsonb;fact_cost numeric;next_cost numeric;unassigned_cost numeric; adjustment numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required' using errcode='42501';end if;
 with f as materialized(select * from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)),
 grouped as(select coalesce(source,'Källa saknas') source,kind,count(*) rows,sum(amount) amount from f group by source,kind)
 select coalesce((select jsonb_agg(to_jsonb(g)order by kind,source)from grouped g),'[]'),
 (select sum(amount)from f where kind='cost'),(select sum(amount)from f where kind='cost'and source='NEXT'),
 (select sum(amount)from f where kind='cost'and unit_id is null)
 into sources,fact_cost,next_cost,unassigned_cost;
 adjustment:=round((p_report->>'cost')::numeric-coalesce(fact_cost,0),2);
 report_revenue:=(p_report->>'recorded_revenue')::numeric;report_result:=report_revenue-(p_report->>'cost')::numeric;
 period_from:=(p_filters->>'date_from')::date;period_to:=(p_filters->>'date_to')::date;
 select string_agg(distinct c,','order by c)into center from string_to_table(p_filters->>'cost_center',',')c;
 if not exists(select 1 from jsonb_object_keys(p_filters)k where k in('group','unit','vehicle','project'))then
  select * into ref from private.hub_kpi_accounting_references where tenant_id=p_tenant and date_from=period_from and date_to=period_to and cost_center=center order by created_at desc limit 1;
 end if;
 return jsonb_build_object('fortnox_verified',case when ref.id is null then false else abs(report_revenue-ref.revenue)<=0.5 and abs(report_result-ref.result)<=0.5 end,'status',case when ref.id is null then 'fortnox_source_missing'when abs(report_revenue-ref.revenue)<=0.5 and abs(report_result-ref.result)<=0.5 then 'matches_uploaded_report'else 'differences'end,
 'revenue_basis','Intäkter följer artikel-/utförandedatum från Workify och Stena. Fakturadatum, bokföringsdatum och periodisering i Fortnox kan ge andra periodbelopp.',
 'cost_basis','NeXT-raderna följer importerade Bokf datum. Schabloner, interna fördelningar och ersättning av tankinköp med förbrukning kan skilja från Fortnox.',
 'next_cost_in_report',next_cost,'cost_before_report_adjustments',fact_cost,'report_cost_adjustment',adjustment,
 'unallocated_cost',unassigned_cost,'sources',sources,
 'fortnox_revenue',ref.revenue,'fortnox_cost',ref.revenue-ref.result,'fortnox_result',ref.result,
 'difference',round(report_result-ref.result,2),'revenue_difference',round(report_revenue-ref.revenue,2),'cost_difference',round((p_report->>'cost')::numeric-(ref.revenue-ref.result),2),
 'reference_file',ref.source->>'file_name','reference_sha256',ref.source->>'sha256','reference_notes',ref.source->>'notes',
 'reference_metrics',ref.source->'metrics','reference_filters',ref.source->>'filters');
end $$;
revoke all on function private.hub_kpi_management_accounting_basis_v1(uuid,int,int[],jsonb,jsonb)from public,anon,authenticated;

do $patch$declare d text;begin
 d:=pg_get_functiondef('public.hub_kpi_management_report_v1(uuid,date,date,text,jsonb)'::regprocedure);
 d:=replace(d,'''Humlas operativa rapport med registrerade intäkter och beräknade kostnader. Fortnox-underlag saknas för en verifierad bokföringsavstämning.''',
 'case when selected#>>''{accounting_basis,status}''=''fortnox_source_missing''then ''Humlas operativa rapport. Bokföringsunderlag saknas för exakt detta urval.''else ''Humlas operativa rapport jämförd med uppladdad bokföringsrapport för samma datum och avdelningar. Differenser ändrar inte ekonomiska transaktioner.''end');
 execute d;
end $patch$;
