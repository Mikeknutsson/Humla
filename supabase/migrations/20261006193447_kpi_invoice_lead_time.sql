-- Workify article date → actual invoice date. Uninvoiced rows never enter the KPI.
create function private.hub_kpi_workify_date_v1(value text) returns date
language plpgsql immutable set search_path='' as $$
begin
 if trim(value) !~ '^\d{4}-\d{2}-\d{2}([ T].*)?$' then return null;end if;
 return left(trim(value),10)::date;
exception when datetime_field_overflow or invalid_datetime_format then return null;
end $$;
revoke all on function private.hub_kpi_workify_date_v1(text) from public,anon,authenticated;

create function private.hub_kpi_invoice_lead_time_v1(p_tenant_id uuid,p_year integer,p_months integer[],p_filters jsonb,p_page integer default -1)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare generation uuid; months integer[]; result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if p_page < -1 or p_page > 100000 then raise exception 'Invalid page';end if;
 generation:=private.hub_kpi_active_report_generation_v1(p_tenant_id);
 months:=private.hub_kpi_month_scope_v1(p_year,p_months);
 if not exists(select 1 from private.hub_kpi_report_generations g where g.id=generation and p_year between g.first_fiscal_year and g.last_fiscal_year) then raise exception 'Fiscal year outside prepared report coverage' using errcode='55000';end if;
 with raw as materialized(
 select f.original#>>'{_humla_invoice,order_number}' order_number,
 (f.original#>>'{_humla_invoice,article_date}')::date article_date,
 (f.original#>>'{_humla_invoice,invoice_date}')::date invoice_date,
 f.original#>>'{_humla_invoice,invoice_text}' invoice_text,
 f.original#>>'{_humla_invoice,customer_name}' customer_name,f.unit_name,f.vehicle
 from private.hub_kpi_prepared_display_facts f
 where f.generation_id=generation and f.tenant_id=p_tenant_id and f.fiscal_year=p_year
 and extract(month from f.occurred_on)::integer=any(months)
 and f.source='Workify' and f.kind='revenue'
 and nullif(f.original#>>'{_humla_invoice,invoice_text}','') is not null
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
 ), days as(
 select order_number,article_date,min(invoice_date) invoice_date,
 count(*) source_rows,max(customer_name) customer_name,
 string_agg(distinct coalesce(unit_name,vehicle,'Ej fördelat'),', ' order by coalesce(unit_name,vehicle,'Ej fördelat')) units,
 bool_and(invoice_date is not null) and min(invoice_date)=max(invoice_date)
 and article_date is not null and order_number is not null and min(invoice_date)>=article_date valid
 from raw group by order_number,article_date
 ), valid as materialized(select *,invoice_date-article_date days_to_invoice from days where valid),
 page as(select * from valid order by days_to_invoice desc,order_number,article_date limit case when p_page<0 then 0 else 100 end offset greatest(p_page,0)*100)
 select jsonb_build_object('average_days',round(avg(days_to_invoice),2),'order_days',count(*),'orders',count(distinct order_number),
 'invalid_order_days',(select count(*) from days where not coalesce(valid,false)),
 'basis','Artikeldatum till Fakturerad/fakturadatum, kalenderdagar. Varje order och utförd dag räknas en gång. Ofakturerade utesluts. Ogiltiga, motstridiga och negativa datum utesluts.',
 'rows',coalesce((select jsonb_agg(to_jsonb(p)-'valid' order by days_to_invoice desc,order_number,article_date) from page p),'[]'::jsonb)) into result from valid;
 return result;
end $$;
revoke all on function private.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer) from public,anon;
grant execute on function private.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer) to authenticated;

-- Bound SQL body keeps the public endpoint an invoker; authorization lives privately.
create function public.hub_kpi_invoice_lead_time_v1(p_tenant_id uuid,p_year integer,p_months integer[],p_filters jsonb default '{}',p_page integer default 0)
returns jsonb language sql stable security invoker
begin atomic
 select private.hub_kpi_invoice_lead_time_v1(p_tenant_id,p_year,p_months,p_filters,p_page);
end;
revoke all on function public.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer) from public,anon;
grant execute on function public.hub_kpi_invoice_lead_time_v1(uuid,integer,integer[],jsonb,integer) to authenticated;

do $$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 needle:=' insert into private.hub_kpi_prepared_display_facts select';
 if position(needle in definition)=0 or position('_humla_invoice' in definition)>0 then raise exception 'Invoice preparation anchor mismatch';end if;
 definition:=replace(definition,needle,$patch$
 update private.hub_kpi_prepared_facts set display_original=display_original||jsonb_build_object('_humla_invoice',jsonb_build_object(
 'order_number',nullif(trim(original->>'Ordernummer'),''),
 'article_date',private.hub_kpi_workify_date_v1(original->>'Artikeldatum'),
 'invoice_date',private.hub_kpi_workify_date_v1(coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),''))),
 'invoice_text',coalesce(nullif(trim(original->>'Fakturadatum'),''),nullif(trim(original->>'Fakturerad'),'')),
 'customer_name',original->>'Kundnamn'))
 where generation_id=generation and source='Workify' and kind='revenue';
$patch$||needle);
 execute definition;
 definition:=pg_get_functiondef('private.hub_kpi_prepared_snapshot_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 needle:='''hub_contract_version'',''fiscal-months-v1'',';
 if position(needle in definition)=0 or position('''invoice_lead_time''' in definition)>0 then raise exception 'Invoice snapshot anchor mismatch';end if;
 definition:=replace(definition,needle,'''invoice_lead_time'',private.hub_kpi_invoice_lead_time_v1(p_tenant_id,p_fiscal_year,months,p_filters,-1),'||needle);
 execute definition;
end $$;
