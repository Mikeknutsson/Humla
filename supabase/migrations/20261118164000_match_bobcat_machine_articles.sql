-- The NeXT project register and both articles name the same Bobcat e27z.
insert into public.hub_identity_keys (tenant_id,object_id,object_type,identity_type,identity_value,confidence)
select k.tenant_id,k.object_id,'Project','next_machine_article_number',a.code,1
from public.hub_identity_keys k
join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id and o.object_type='Project'
join public.kpi_next_project_register p on p.tenant_id=k.tenant_id and p.project_number=k.identity_value
join public.kpi_next_article_register a on a.tenant_id=k.tenant_id and a.code in ('M1088','M1088 DAG')
where k.identity_type='next_project_number' and k.identity_value='1088' and k.confidence=1
 and p.project_name ilike '%Bobcat e27z%' and a.name ilike '%Bobcat e27z%'
 and not exists (
  select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id
   and other.identity_type='next_machine_article_number' and other.identity_value=a.code
 )
on conflict do nothing;
