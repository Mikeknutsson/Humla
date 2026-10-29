insert into private.hub_overhead_unit_exclusions_v1(tenant_id,unit_id,cost_center,valid_from,reason)
select s.tenant_id,public.hub_resolve_canonical_object_v1(s.tenant_id,s.material_unit_id),'20',s.valid_from,
'Material unit receives no overhead, including historical KST20 entries'
from private.hub_kpi_material_separation_settings s where s.enabled on conflict do nothing;