-- Preserve completion dates in the slim nightly projection, without changing sources.
do $$ declare definition text; needle text; begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 needle:='''customer_name'',original->>''Kundnamn''))';
 if position(needle in definition)=0 then raise exception 'Invoice preparation anchor changed';end if;
 definition:=replace(definition,needle,$patch$'customer_name',original->>'Kundnamn',
 'end_text',coalesce(nullif(trim(original->>'Slutdatum'),''),nullif(trim(original->>'PlaneradKlart'),'')),
 'end_date',private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Slutdatum'),''),nullif(trim(original->>'PlaneradKlart'),'')))))$patch$);
 execute definition;
end $$;

-- Existing prepared generations get the same metadata; no financial amounts change.
update private.hub_kpi_prepared_display_facts d
set original=jsonb_set(d.original,'{_humla_invoice}',(d.original->'_humla_invoice')||jsonb_build_object(
 'end_text',coalesce(nullif(trim(f.original->>'Slutdatum'),''),nullif(trim(f.original->>'PlaneradKlart'),'')),
 'end_date',private.hub_kpi_workify_date_v1(coalesce(nullif(trim(f.original->>'Slutdatum'),''),nullif(trim(f.original->>'PlaneradKlart'),'')))))
from private.hub_kpi_prepared_facts f
where d.generation_id=f.generation_id and d.tenant_id=f.tenant_id and d.fact_id=f.fact_id
and d.source='Workify' and d.kind='revenue' and d.original?'_humla_invoice';

create or replace function private.hub_kpi_invoice_lead_time_v1(p_tenant_id uuid,p_year integer,p_months integer[],p_filters jsonb,p_page integer default -1)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare generation uuid; months integer[]; result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if p_page < -1 or p_page > 100000 then raise exception 'Invalid page';end if;
 if p_filters?'invoice_customer' and p_filters->>'invoice_customer' not in ('external','internal') then raise exception 'Invalid invoice customer selection';end if;
 generation:=private.hub_kpi_active_report_generation_v1(p_tenant_id);
 months:=private.hub_kpi_month_scope_v1(p_year,p_months);
 if not exists(select 1 from private.hub_kpi_report_generations g where g.id=generation and p_year between g.first_fiscal_year and g.last_fiscal_year) then raise exception 'Fiscal year outside prepared report coverage' using errcode='55000';end if;
 with scope as materialized(
 select f.original#>>'{_humla_invoice,order_number}' order_number,
 string_agg(distinct coalesce(f.unit_name,f.vehicle,'Ej fördelat'),', ' order by coalesce(f.unit_name,f.vehicle,'Ej fördelat')) units
 from private.hub_kpi_prepared_display_facts f
 where f.generation_id=generation and f.tenant_id=p_tenant_id and f.fiscal_year=p_year
 and extract(month from f.occurred_on)::integer=any(months)
 and f.source='Workify' and f.kind='revenue'
 and nullif(f.original#>>'{_humla_invoice,order_number}','') is not null
 and (not(p_filters?'cost_center') or f.cost_center=any(string_to_array(p_filters->>'cost_center',',')))
 and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
 and (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit')
 and (not(p_filters?'vehicle') or coalesce(f.vehicle,'unassigned')=p_filters->>'vehicle')
 and (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project')
 and (not(p_filters?'category') or f.category=p_filters->>'category')
 and (not(p_filters?'kind') or f.kind=p_filters->>'kind')
 and (not(p_filters?'source') or f.source=p_filters->>'source')
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)
 group by f.original#>>'{_humla_invoice,order_number}'
 ), raw as(
 -- Complete order context, including days outside selected months/units.
 -- Filtering an early day must not move the actual completion date backwards.
 select s.order_number,s.units,
 (f.original#>>'{_humla_invoice,article_date}')::date article_date,
 (f.original#>>'{_humla_invoice,invoice_date}')::date invoice_date,
 f.original#>>'{_humla_invoice,invoice_text}' invoice_text,
 (f.original#>>'{_humla_invoice,end_date}')::date end_date,
 f.original#>>'{_humla_invoice,end_text}' end_text,
 f.original#>>'{_humla_invoice,customer_name}' customer_name
 from private.hub_kpi_prepared_display_facts f join scope s on s.order_number=f.original#>>'{_humla_invoice,order_number}'
 where f.generation_id=generation and f.tenant_id=p_tenant_id and f.source='Workify' and f.kind='revenue'
 ), orders as(
 select order_number,max(units) units,count(*) source_rows,max(customer_name) customer_name,
 bool_or(coalesce(customer_name,'')~*'elleholms[[:space:]]+maskin') is_internal,
 min(article_date) first_article_date,max(article_date) article_date,
 min(invoice_date) invoice_date,min(end_date) end_date,
 coalesce(min(end_date),max(article_date)) completion_date,
 case when bool_or(nullif(end_text,'') is not null) then 'order_end' else 'last_article' end completion_source,
 bool_and(nullif(invoice_text,'') is not null) invoiced,
 bool_and(invoice_date is not null) and min(invoice_date)=max(invoice_date)
 and bool_and(article_date is not null)
 and bool_and(nullif(end_text,'') is null or end_date is not null)
 and (min(end_date)=max(end_date) or count(end_date)=0)
 and coalesce(min(end_date),max(article_date))>=max(article_date)
 and min(invoice_date)>=coalesce(min(end_date),max(article_date)) valid
 from raw group by order_number
 ), valid as materialized(select *,invoice_date-completion_date days_to_invoice from orders where invoiced and valid),
 selected as materialized(select * from valid where not(p_filters?'invoice_customer') or is_internal=(p_filters->>'invoice_customer'='internal')),
 page as(select * from selected order by days_to_invoice desc,order_number limit case when p_page<0 then 0 else 100 end offset greatest(p_page,0)*100)
 select jsonb_build_object(
 'average_days',round(avg(days_to_invoice) filter(where days_to_invoice>0 and not is_internal),2),
 'averaged_orders',count(*) filter(where days_to_invoice>0 and not is_internal),
 'internal_average_days',round(avg(days_to_invoice) filter(where days_to_invoice>0 and is_internal),2),
 'internal_averaged_orders',count(*) filter(where days_to_invoice>0 and is_internal),
 'internal_orders',count(*) filter(where is_internal),'zero_orders',count(*) filter(where days_to_invoice=0),
 'orders',count(*),'row_count',(select count(*) from selected),
 'fallback_orders',count(*) filter(where completion_source='last_article'),
 'uninvoiced_orders',(select count(*) from orders where not invoiced),
 'invalid_orders',(select count(*) from orders where invoiced and not coalesce(valid,false)),
 -- Compatibility aliases for older consumers during the deployment transition.
 'order_days',count(*),'averaged_order_days',count(*) filter(where days_to_invoice>0 and not is_internal),
 'internal_averaged_order_days',count(*) filter(where days_to_invoice>0 and is_internal),
 'internal_order_days',count(*) filter(where is_internal),'zero_order_days',count(*) filter(where days_to_invoice=0),
 'invalid_order_days',(select count(*) from orders where invoiced and not coalesce(valid,false)),
 'basis','Orderns slutdatum (Slutdatum/PlaneradKlart) till fakturadatum, annars sista artikeldatum. Varje order räknas en gång. Ordrar väljs via artikelrader i aktiv period och aktiva filter; hela orderns datum används. Ofakturerade, ogiltiga, motstridiga och negativa datum utesluts. Noll dagar utesluts från båda snitten. Elleholms Maskin redovisas separat.',
 'rows',coalesce((select jsonb_agg(to_jsonb(p)-'valid'-'invoiced' order by days_to_invoice desc,order_number) from page p),'[]'::jsonb)) into result from valid;
 return result;
end $$;
revoke all on function private.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer) from public,anon;
grant execute on function private.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer) to authenticated;
