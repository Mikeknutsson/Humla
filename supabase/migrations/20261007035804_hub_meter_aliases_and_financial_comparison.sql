-- Several provider IDs can refer to one canonical reading. Keep all aliases
-- in hub_external_references, but only one domain reading per Humla object.
do $patch$
declare definition text; needle text;
begin
 definition:=pg_get_functiondef('public.hub_sync_fordonskontroll_meter_readings(uuid,uuid,text,jsonb)'::regprocedure);
 needle:='      insert into public.hub_vehicle_meter_readings(';
 if strpos(definition,needle)=0 then raise exception 'Meter import contract changed';end if;
 definition:=replace(definition,needle,$replacement$
      if exists(select 1 from public.hub_vehicle_meter_readings m where m.object_id=object_id_value) then
        if not exists(select 1 from public.hub_vehicle_meter_readings m
          where m.object_id=object_id_value and m.tenant_id=p_tenant_id and m.connection_id=p_connection_id) then
          raise exception 'Canonical reading belongs to another tenant or connection';
        end if;
        update public.hub_vehicle_meter_readings m set
          vehicle_id=asset_id,reading_type=p_reading_type,reading_value=canonical_data->>'reading_value',
          recorded_at=(canonical_data->>'recorded_at')::timestamptz,raw_data=r
        where m.object_id=object_id_value and m.tenant_id=p_tenant_id and m.connection_id=p_connection_id;
        continue;
      end if;
      insert into public.hub_vehicle_meter_readings($replacement$);
 definition:=replace(definition,'reading_value=canonical_data->>''reading_value''','reading_value=(canonical_data->>''reading_value'')::numeric');
 execute definition;
end $patch$;

-- Overview only consumes previous-year financial comparison, not operational
-- vehicle/time/distance detail. Dedicated projection retains exact financial
-- filters and coverage semantics; full snapshots remain unchanged elsewhere.
create function private.hub_kpi_prepared_comparison_v1(p_tenant_id uuid,p_fiscal_year integer,p_selected_months integer[],p_filters jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' set plan_cache_mode='force_custom_plan' as $$
declare generation uuid; months integer[]; result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 generation:=private.hub_kpi_active_report_generation_v1(p_tenant_id);
 if not exists(select 1 from private.hub_kpi_report_generations g where g.id=generation and p_fiscal_year between g.first_fiscal_year and g.last_fiscal_year) then raise exception 'Fiscal year outside prepared report coverage' using errcode='55000';end if;
 months:=private.hub_kpi_month_scope_v1(p_fiscal_year,p_selected_months);
 with selected_facts as materialized(
 select f.* from private.hub_kpi_prepared_display_facts f
 where f.generation_id=generation and f.tenant_id=p_tenant_id and f.fiscal_year=p_fiscal_year
 and extract(month from f.occurred_on)::int=any(months)
 and (not(p_filters?'group') or f.business_group=any(string_to_array(p_filters->>'group',',')))
 and (not(p_filters?'unit') or coalesce(f.unit_id::text,'vehicle:'||f.vehicle,'unassigned')=p_filters->>'unit')
 and (not(p_filters?'vehicle') or coalesce(f.vehicle,'unassigned')=p_filters->>'vehicle')
 and (not(p_filters?'project') or coalesce(f.project,'unassigned')=p_filters->>'project')
 and (not(p_filters?'category') or f.category=p_filters->>'category')
 and (not(p_filters?'kind') or f.kind=p_filters->>'kind')
 and (not(p_filters?'source') or f.source=p_filters->>'source')
 and (not(p_filters?'date_from') or f.occurred_on>=(p_filters->>'date_from')::date)
 and (not(p_filters?'date_to') or f.occurred_on<=(p_filters->>'date_to')::date)),
 facts as(select * from selected_facts where not(p_filters?'cost_center') or cost_center=any(string_to_array(p_filters->>'cost_center',','))),
 totals as(select coalesce(sum(amount) filter(where kind='revenue'),0) revenue,coalesce(sum(amount) filter(where kind='cost'),0) cost from facts)
 select jsonb_build_object('scope','financial-comparison-v1','period',jsonb_build_object('fiscal_year',p_fiscal_year,'selected_months',months,'from',make_date(p_fiscal_year,9,1),'to',make_date(p_fiscal_year+1,8,31)),'filters',p_filters,
 'metrics',jsonb_build_object('revenue',round(t.revenue,2),'total_cost',round(t.cost,2),'result',round(t.revenue-t.cost,2),'margin_pct',round((t.revenue-t.cost)/nullif(t.revenue,0)*100,2)),
 'coverage',(select jsonb_build_object('revenue_months',coalesce(jsonb_agg(m) filter(where revenue_rows>0),'[]'),'cost_months',coalesce(jsonb_agg(m) filter(where next_rows>0),'[]')) from(select m,count(f.fact_id) filter(where f.source='Workify') revenue_rows,count(f.fact_id) filter(where f.source='NEXT') next_rows from unnest(months) m left join selected_facts f on extract(month from f.occurred_on)::int=m group by m)x)) into result from totals t;
 return result;
end $$;
revoke all on function private.hub_kpi_prepared_comparison_v1(uuid,integer,integer[],jsonb) from public,anon,authenticated;
do $patch$
declare definition text;needle text:='previous_data:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_fiscal_year-1,months,previous_filters);';
begin
 definition:=pg_get_functiondef('private.hub_kpi_prepared_overview_v1(uuid,integer,integer[],text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Overview comparison contract changed';end if;
 execute replace(definition,needle,'previous_data:=private.hub_kpi_prepared_comparison_v1(p_tenant_id,p_fiscal_year-1,months,previous_filters);');
end $patch$;
