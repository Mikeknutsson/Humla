-- Avoid de-TOASTing every Workify row whenever only the internal customer is needed.
create index if not exists hub_kpi_prepared_internal_customer_period_idx
on private.hub_kpi_prepared_facts(generation_id,tenant_id,fiscal_year,occurred_on,cost_center)
where source='Workify'and kind='revenue'
and lower(trim(display_original#>>'{_humla_invoice,customer_name}'))='elleholms maskin ab';

-- Missing historical NEXT imports should return immediately, without scanning costs.
do $migration$
declare d text;needle text:=' g:=private.hub_kpi_active_report_generation_v1(p_tenant);';
begin
 d:=pg_get_functiondef('private.hub_kpi_next_time_period_v1(uuid,integer,integer[],jsonb)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected NEXT time period helper';end if;
 d:=replace(d,needle,needle||$patch$
 if not exists(select 1 from private.hub_kpi_prepared_kpi_import_rows r where r.tenant_id=p_tenant and r.generation_id=g
  and r.data_kind='next_historical_time'and r.occurred_on between make_date(p_year,9,1)and make_date(p_year+1,8,31)
  and extract(month from r.occurred_on)::int=any(months))then
  return jsonb_build_object('available',false,'rows',0,'project_hours',null,'workshop_hours',null,'absence_hours',0,'supplement_hours',0,
   'review_rows',0,'unmapped_unit_hours',0,'workshop_hours_without_cost_reference',0,'workshop_cost_references','[]'::jsonb,'units','[]'::jsonb,
   'basis','Publicerad NEXT-tid saknas för perioden. Saknat underlag visas inte som noll arbetade timmar.');
 end if;
$patch$);
 execute d;
end $migration$;
