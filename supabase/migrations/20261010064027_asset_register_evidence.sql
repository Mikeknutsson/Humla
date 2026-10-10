-- Source evidence, not new ledger costs and not a guessed complete TCO profile.
create table private.hub_asset_register_rows (
 tenant_id uuid not null references public.hub_tenants(id),
 source_sha256 text not null check(length(source_sha256)=64),
 source_key text not null,
 asset_id uuid references public.hub_objects(id),
 link_kind text not null check(link_kind in ('asset','related','bundle','review')),
 sold boolean not null,
 evidence jsonb not null check(jsonb_typeof(evidence)='object'),
 imported_at timestamptz not null default now(),
 imported_by uuid not null,
 primary key(tenant_id,source_sha256,source_key)
);
create index hub_asset_register_asset on private.hub_asset_register_rows(tenant_id,asset_id);
alter table private.hub_asset_register_rows enable row level security;
revoke all on private.hub_asset_register_rows from public,anon,authenticated;

-- A permission-checked, read-only companion to the existing TCO RPC.
create function private.hub_asset_register_v1(p_tenant uuid,p_asset uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'fleet.read') then raise exception 'Fordonsbehörighet saknas' using errcode='42501';end if;
 select jsonb_build_object(
 'summary',(select jsonb_build_object('rows',count(*),'exact_links',count(asset_id),'active_acquisitions',count(*) filter(where asset_id is not null and link_kind='asset' and not sold),'review_rows',count(*) filter(where asset_id is null or link_kind<>'asset')) from private.hub_asset_register_rows where tenant_id=p_tenant),
 'rows',coalesce(jsonb_agg(jsonb_build_object('asset_id',r.asset_id,'source_key',r.source_key,'link_kind',r.link_kind,'sold',r.sold,'evidence',r.evidence-'monthly','imported_at',r.imported_at) order by r.source_key),'[]')) into result
 from private.hub_asset_register_rows r where r.tenant_id=p_tenant and (p_asset is null or r.asset_id=p_asset);
 return result;
end $$;
create function public.hub_asset_register_v1(p_tenant uuid,p_asset uuid default null)
returns jsonb language sql stable security invoker set search_path='' as $$select private.hub_asset_register_v1(p_tenant,p_asset)$$;
revoke all on function private.hub_asset_register_v1(uuid,uuid),public.hub_asset_register_v1(uuid,uuid) from public,anon;
grant execute on function private.hub_asset_register_v1(uuid,uuid),public.hub_asset_register_v1(uuid,uuid) to authenticated;

-- Keep the existing calculations; remove only the accidental ownership gate on cost evidence.
-- Confirmed profiles still use purchase date; otherwise show all available cost history.
do $migration$
declare definition text;
begin
 select pg_get_functiondef('private.hub_asset_tco_v1(uuid,date,uuid)'::regprocedure) into definition;
 if position('join private.hub_asset_ownership own on own.tenant_id=p_tenant_id and own.asset_id=i.object_id' in definition)=0 then raise exception 'Unexpected TCO definition; review before changing';end if;
 definition:=replace(definition,'join private.hub_asset_ownership own on own.tenant_id=p_tenant_id and own.asset_id=i.object_id','left join private.hub_asset_ownership own on own.tenant_id=p_tenant_id and own.asset_id=i.object_id');
 definition:=replace(definition,'f.occurred_on between own.purchase_date and p_as_of','f.occurred_on<=p_as_of and (own.purchase_date is null or f.occurred_on>=own.purchase_date)');
 execute definition;
end $migration$;
