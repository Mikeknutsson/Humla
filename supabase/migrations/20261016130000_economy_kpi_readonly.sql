-- Read-only finance access: economy staff can retrieve KPIs and exports.
-- Editing imports/mappings requires a separately approved administrator role or override.
delete from public.hub_role_permissions where role='economy' and permission_code='kpi.manage';
insert into public.hub_role_permissions(role,permission_code)
select 'economy','kpi.read'
where not exists(select 1 from public.hub_role_permissions where role='economy' and permission_code='kpi.read');
