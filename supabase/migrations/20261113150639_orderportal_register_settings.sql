create table public.hub_orderportal_register_settings (
 tenant_id uuid not null references public.hub_tenants(id),
 object_id uuid not null references public.hub_objects(id),
 category text not null default '' check (char_length(category)<=80),
 unit text not null default '' check (char_length(unit)<=20),
 note text not null default '' check (char_length(note)<=2000),
 revision integer not null check (revision>0),
 updated_by uuid not null default auth.uid(),
 updated_at timestamptz not null default now(),
 primary key (tenant_id,object_id)
);
alter table public.hub_orderportal_register_settings enable row level security;
revoke all on public.hub_orderportal_register_settings from public,anon,authenticated;
grant select,insert on public.hub_orderportal_register_settings to authenticated;
grant update(category,unit,note,revision,updated_by,updated_at) on public.hub_orderportal_register_settings to authenticated;
create policy orderportal_register_settings_read on public.hub_orderportal_register_settings for select to authenticated
 using (public.hub_has_permission(tenant_id,'kpi.manage'));
create policy orderportal_register_settings_write on public.hub_orderportal_register_settings for all to authenticated
 using (public.hub_has_permission(tenant_id,'kpi.manage'))
 with check (
  updated_by=(select auth.uid()) and public.hub_has_permission(tenant_id,'kpi.manage')
  and exists (select 1 from public.hub_objects o where o.id=object_id
   and o.tenant_id=hub_orderportal_register_settings.tenant_id and o.status='active'
   and (o.object_type='Article' or (unit='' and o.object_type in ('Person','Vehicle','vehicle'))))
 );
