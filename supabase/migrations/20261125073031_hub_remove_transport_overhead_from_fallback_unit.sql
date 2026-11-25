insert into private.hub_overhead_unit_exclusions_v1(tenant_id,unit_id,cost_center,valid_from,reason)
select t.id,o.id,'30',date '2025-09-01',
 'Övrigt är en uppsamlingsenhet. Fördela transportens overhead på intäktsbärarna.'
from public.hub_tenants t join public.hub_objects o on o.tenant_id=t.id and o.object_type='EconomicUnit'
 and o.data->>'report_fallback'='unresolved'
where t.slug='elleholms'
on conflict (tenant_id,unit_id,cost_center,valid_from) do nothing;

do $migration$
declare r record;
begin
 perform pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));
 for r in select s.tenant_id,s.active_generation from private.hub_kpi_report_state s
 join public.hub_tenants t on t.id=s.tenant_id and t.slug='elleholms'
 where s.active_generation is not null
 loop
  perform private.hub_apply_monthly_overhead_v1(r.tenant_id,r.active_generation);
  perform private.hub_validate_report_projection_v1(r.tenant_id,r.active_generation);
  update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=r.tenant_id;
 end loop;
end $migration$;
