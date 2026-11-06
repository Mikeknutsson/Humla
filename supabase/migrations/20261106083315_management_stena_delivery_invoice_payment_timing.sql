create or replace function private.hub_kpi_management_accounting_basis_v1(p_tenant uuid,p_year int,p_months int[],p_filters jsonb,p_report jsonb) returns jsonb
language plpgsql stable set search_path='' as $$
declare timing jsonb;ref private.hub_kpi_accounting_references;report_revenue numeric;report_result numeric;period_from date;period_to date;center text;sources jsonb;fact_cost numeric;next_cost numeric;unassigned_cost numeric; adjustment numeric;
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
 with f as materialized(select * from private.hub_kpi_prepared_month_facts_v1(p_tenant,p_year,p_months,p_filters)),
 cohort as(select date_trunc('month',occurred_on)::date delivery_month,count(*) rows,round(sum(amount),2) amount,
 count(*)filter(where nullif(original#>>'{_humla_invoice,invoice_date}','')is not null)actual_invoice_date_rows
 from f where kind='revenue'and(source='Stena portal'or(source='Workify'and original->>'Kundnamn'in('Elleholms Maskin (STENA)','Stena Recycling AB')))
 group by date_trunc('month',occurred_on)::date)
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('invoice_date_assumed',(delivery_month+interval '1 month - 1 day')::date,'payment_date_assumed',(delivery_month+interval '1 month - 1 day')::date+45)order by delivery_month),'[]')into timing from cohort c;
 return jsonb_build_object('stena_timing',timing,'stena_rule','Stena följs på kördatum i driftuppföljningen. Betalningsprognosen antar fakturering sista dagen i körmånaden och betalning 45 kalenderdagar senare. Fakturadatum och bokföringsdatum behövs för avstämning mot bokföringen.','fortnox_verified',case when ref.id is null then false else abs(report_revenue-ref.revenue)<=0.5 and abs(report_result-ref.result)<=0.5 end,'status',case when ref.id is null then 'fortnox_source_missing'when abs(report_revenue-ref.revenue)<=0.5 and abs(report_result-ref.result)<=0.5 then 'matches_uploaded_report'else 'differences'end,
 'revenue_basis','Intäkter följer artikel-/utförandedatum från Workify och Stena. Fakturadatum, bokföringsdatum och periodisering i Fortnox kan ge andra periodbelopp.',
 'cost_basis','NeXT-raderna följer importerade Bokf datum. Schabloner, interna fördelningar och ersättning av tankinköp med förbrukning kan skilja från Fortnox.',
 'next_cost_in_report',next_cost,'cost_before_report_adjustments',fact_cost,'report_cost_adjustment',adjustment,
 'unallocated_cost',unassigned_cost,'sources',sources,
 'fortnox_revenue',ref.revenue,'fortnox_cost',ref.revenue-ref.result,'fortnox_result',ref.result,
 'difference',round(report_result-ref.result,2),'revenue_difference',round(report_revenue-ref.revenue,2),'cost_difference',round((p_report->>'cost')::numeric-(ref.revenue-ref.result),2),
 'reference_file',ref.source->>'file_name','reference_sha256',ref.source->>'sha256','reference_notes',ref.source->>'notes',
 'reference_metrics',ref.source->'metrics','reference_filters',ref.source->>'filters');
end $$;
