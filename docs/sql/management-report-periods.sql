create or replace function private.hub_kpi_management_accounting_basis_v1(p_tenant uuid,p_year int,p_months int[],p_filters jsonb,p_report jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare sources jsonb;fact_cost numeric;next_cost numeric;unassigned_cost numeric; adjustment numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required' using errcode='42501';end if;
 with f as materialized(select * from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)),
 grouped as(select coalesce(source,'Källa saknas') source,kind,count(*) rows,sum(amount) amount from f group by source,kind)
 select coalesce((select jsonb_agg(to_jsonb(g)order by kind,source)from grouped g),'[]'),
 (select sum(amount)from f where kind='cost'),(select sum(amount)from f where kind='cost'and source='NEXT'),
 (select sum(amount)from f where kind='cost'and unit_id is null)
 into sources,fact_cost,next_cost,unassigned_cost;
 adjustment:=(p_report->>'cost')::numeric-coalesce(fact_cost,0);
 return jsonb_build_object('fortnox_verified',false,'status','fortnox_source_missing',
 'revenue_basis','Intäkter följer artikel-/utförandedatum från Workify och Stena. Fakturadatum, bokföringsdatum och periodisering i Fortnox kan ge andra periodbelopp.',
 'cost_basis','NeXT-raderna följer importerade Bokf datum. Schabloner, interna fördelningar och ersättning av tankinköp med förbrukning kan skilja från Fortnox.',
 'next_cost_in_report',next_cost,'cost_before_report_adjustments',fact_cost,'report_cost_adjustment',adjustment,
 'unallocated_cost',unassigned_cost,'sources',sources,
 'fortnox_revenue',null,'fortnox_cost',null,'fortnox_result',null,'difference',null);
end $$;
revoke all on function private.hub_kpi_management_accounting_basis_v1(uuid,int,int[],jsonb,jsonb)from public,anon,authenticated;

create or replace function public.hub_kpi_management_report_v1(p_tenant_id uuid,p_from date,p_to date,p_cost_center text default '30',p_filters jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' set jit=off set statement_timeout='45s' as $$
declare fy int;last_month int;months int[];ytd_months int[];base jsonb;selected jsonb;ytd jsonb;scope jsonb;end_scope jsonb;metrics jsonb;start_month date;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant_id,'kpi.read')then raise exception 'KPI access required'using errcode='42501';end if;
 if p_from is null or p_to is null or p_from>p_to then raise exception 'Invalid report period'using errcode='22023';end if;
 fy:=extract(year from p_from)::int-case when extract(month from p_from)<9 then 1 else 0 end;
 if fy not between 2001 and 2100 or p_to>make_date(fy+1,8,31)then raise exception 'Period must fit one fiscal year'using errcode='22023';end if;
 if p_filters is null or jsonb_typeof(p_filters)<>'object'or length(p_filters::text)>2000 or exists(select 1 from jsonb_object_keys(p_filters)k where k not in('group','unit','vehicle','project'))then raise exception 'Unsupported management filter'using errcode='22023';end if;
 if p_cost_center is null or p_cost_center !~ '^(10|20|30|40|50|60|90)(,(10|20|30|40|50|60|90))*$'then raise exception 'Invalid cost center'using errcode='22023';end if;
 select array_agg(extract(month from d)::int order by d)into months from generate_series(date_trunc('month',p_from),date_trunc('month',p_to),interval '1 month')d;
 select array_agg(extract(month from d)::int order by d)into ytd_months from generate_series(make_date(fy,9,1)::timestamp,date_trunc('month',p_to),interval '1 month')d;
 last_month:=extract(month from p_to)::int;start_month:=date_trunc('month',p_to)::date;
 -- YTD has its own lower bound. A custom start date must never truncate YTD.
 end_scope:=p_filters||jsonb_build_object('date_to',p_to);
 base:=public.hub_kpi_monthly_transport_report_v1(p_tenant_id,fy,last_month,p_cost_center,end_scope);
 scope:=p_filters||jsonb_build_object('cost_center',p_cost_center,'date_from',p_from,'date_to',p_to);
 selected:=case when p_from=start_month then base->'month'else private.hub_kpi_transport_period_report_v1(p_tenant_id,fy,months,scope)end;
 ytd:=base->'ytd';
 selected:=selected||jsonb_build_object('accounting_basis',private.hub_kpi_management_accounting_basis_v1(p_tenant_id,fy,months,scope,selected));
 ytd:=ytd||jsonb_build_object('accounting_basis',private.hub_kpi_management_accounting_basis_v1(p_tenant_id,fy,ytd_months,p_filters||jsonb_build_object('cost_center',p_cost_center,'date_from',make_date(fy,9,1),'date_to',p_to),ytd));
 -- Keep the operating model explicit; these are not verified booked sales.
 select jsonb_agg(case when m->>'key'='revenue'then m||jsonb_build_object('label','Registrerade intäkter – Humla')when m->>'key'='result'then m||jsonb_build_object('label','Resultat – Humlas modell')else m end order by ord)into metrics from jsonb_array_elements(selected->'metrics')with ordinality a(m,ord);
 selected:=jsonb_set(selected,'{metrics}',metrics);
 select jsonb_agg(case when m->>'key'='revenue'then m||jsonb_build_object('label','Registrerade intäkter – Humla')when m->>'key'='result'then m||jsonb_build_object('label','Resultat – Humlas modell')else m end order by ord)into metrics from jsonb_array_elements(ytd->'metrics')with ordinality a(m,ord);
 ytd:=jsonb_set(ytd,'{metrics}',metrics);
 return base||jsonb_build_object('title','Månadsrapport till ledningsgruppen','period',(base->'period')||jsonb_build_object('from',p_from,'to',p_to,'months',months,'ytd_months',ytd_months),'scope',scope,'month',selected,'ytd',ytd,'invoicing_rule','Humlas operativa rapport med registrerade intäkter och beräknade kostnader. Fortnox-underlag saknas för en verifierad bokföringsavstämning.');
end $$;
revoke all on function public.hub_kpi_management_report_v1(uuid,date,date,text,jsonb)from public,anon;
grant execute on function public.hub_kpi_management_report_v1(uuid,date,date,text,jsonb)to authenticated;
