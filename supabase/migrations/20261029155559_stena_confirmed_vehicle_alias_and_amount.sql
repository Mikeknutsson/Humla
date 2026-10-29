create table private.hub_stena_amount_overrides_v1(
tenant_id uuid not null,revenue_object_id uuid not null references public.hub_objects(id),amount numeric not null,
reason text not null,approved_by uuid not null,approved_at timestamptz not null default now(),
primary key(tenant_id,revenue_object_id));
alter table private.hub_stena_amount_overrides_v1 enable row level security;
revoke all on private.hub_stena_amount_overrides_v1 from public,anon,authenticated;
do $migration$
declare d text;
begin
select pg_get_functiondef('private.hub_apply_stena_priority_v1(uuid,uuid)'::regprocedure)into d;
d:=replace(d,'create unique index on stena_current(revenue_object_id);',
'update stena_current s set amount=o.amount from private.hub_stena_amount_overrides_v1 o where o.tenant_id=p_tenant and o.revenue_object_id=s.revenue_object_id;'||chr(10)||'create unique index on stena_current(revenue_object_id);');
d:=replace(d,$old$s.registration=regexp_replace(upper(up.period_data#>>'{main_vehicle,source_reference}'),'[^A-Z0-9]','','g'))$old$,$new$s.registration=regexp_replace(upper(up.period_data#>>'{main_vehicle,source_reference}'),'[^A-Z0-9]','','g')or exists(select 1 from public.hub_identity_keys ik where ik.tenant_id=p_tenant and ik.identity_type='stena_vehicle_registration'and ik.identity_value=s.registration and ik.object_id::text=up.period_data#>>'{main_vehicle,object_id}'))$new$);
d:=replace(d,'case when not s.fallback then s.registration end','case when not s.fallback then coalesce(s.period#>>''{main_vehicle,source_reference}'',s.registration)end');
d:=replace(d,$old$'price',s.price,$old$,$new$'confirmed_override',(select jsonb_build_object('amount',o.amount,'reason',o.reason,'approved_at',o.approved_at)from private.hub_stena_amount_overrides_v1 o where o.tenant_id=p_tenant and o.revenue_object_id=s.revenue_object_id),'price',s.price,$new$);
if position('stena_vehicle_registration'in d)=0 then raise exception 'Alias anchor missing';end if;
execute d;
end $migration$;