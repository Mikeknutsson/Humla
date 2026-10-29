
create table private.hub_overhead_unit_exclusions_v1(
tenant_id uuid not null,unit_id uuid not null,cost_center text not null,valid_from date not null,reason text not null,
primary key(tenant_id,unit_id,cost_center,valid_from),
foreign key(unit_id) references public.hub_objects(id));
alter table private.hub_overhead_unit_exclusions_v1 enable row level security;
revoke all on private.hub_overhead_unit_exclusions_v1 from public,anon,authenticated;
insert into private.hub_overhead_unit_exclusions_v1(tenant_id,unit_id,cost_center,valid_from,reason)
select distinct u.tenant_id,public.hub_resolve_canonical_object_v1(u.tenant_id,u.id),'30',s.valid_from,
'User confirmed: material and tipping/trading in KST30 must not receive overhead'
from public.kpi_units u join private.hub_kpi_material_separation_settings s on s.tenant_id=u.tenant_id and s.enabled
join public.hub_objects o on o.tenant_id=u.tenant_id and o.id=u.id and o.object_type='EconomicUnit'
where lower(trim(u.name)) in('grusmaterial - lager','trading material','tippen elleholm')
on conflict do nothing;
create function private.hub_overhead_unit_eligible_v1(p_tenant uuid,p_unit uuid,p_center text,p_on date)
returns boolean language sql stable set search_path='' as $f$
select not exists(select 1 from private.hub_overhead_unit_exclusions_v1 e
where e.tenant_id=p_tenant and e.unit_id=public.hub_resolve_canonical_object_v1(p_tenant,p_unit)
and e.cost_center=p_center and e.valid_from<=p_on);
$f$;
revoke all on function private.hub_overhead_unit_eligible_v1(uuid,uuid,text,date) from public,anon,authenticated;
do $patch$
declare d text;n text;
begin
d:=pg_get_functiondef('private.hub_apply_monthly_overhead_v1(uuid,uuid)'::regprocedure);
n:='and f.cost_center in(''20'',''30'')';
if strpos(d,n)=0 then raise exception 'Monthly hook missing';end if;
d:=replace(d,n,n||chr(10)||' and private.hub_overhead_unit_eligible_v1(p_tenant,f.unit_id,f.cost_center,f.occurred_on)');
execute d;
d:=pg_get_functiondef('private.hub_allocate_saw_supplier_common_v1(uuid,uuid)'::regprocedure);
n:='and not coalesce((original->>''_humla_excluded_from_kpi'')::boolean,false)group by unit_id';
if strpos(d,n)=0 then raise exception 'Supplier hook missing';end if;
d:=replace(d,n,'and private.hub_overhead_unit_eligible_v1(p_tenant,unit_id,''30'',occurred_on) '||n);
execute d;
d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
n:='perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);'||chr(10)||'perform private.hub_saw_material_value_v1(job.tenant_id,generation);';
if strpos(d,n)=0 then raise exception 'Worker sequence missing';end if;
d:=replace(d,n,'perform private.hub_saw_material_value_v1(job.tenant_id,generation);'||chr(10)||'perform private.hub_apply_monthly_overhead_v1(job.tenant_id,generation);');
execute d;
end $patch$;
