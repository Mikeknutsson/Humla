-- Stena history exports carry monetary row amounts. Load-carrier counts
-- describe the transport and are not a generic monetary multiplier.
-- Preserve source fields, approved overrides, canonical identities and Workify fallback.
create table private.hub_stena_price_correction_audit_v1 (
 tenant_id uuid not null, file_hash text not null, row_number integer not null,
 revenue_object_id uuid, before_amount numeric, after_amount numeric,
 corrected_at timestamptz not null default now(),
 reason text not null default 'stena_source_row_total_no_generic_load_multiplier',
 primary key(tenant_id,file_hash,row_number)
);
alter table private.hub_stena_price_correction_audit_v1 enable row level security;
revoke all on private.hub_stena_price_correction_audit_v1 from public,anon,authenticated;

create or replace function private.hub_stena_amount_v2(
 p_kind text,p_price numeric,p_extra numeric,p_count numeric,p_settled numeric,p_type text
) returns numeric language sql immutable set search_path='' as $fn$
 select case when p_kind='settled' then
  case when p_settled::text not in ('NaN','Infinity','-Infinity') then round(p_settled,2) end
 when p_kind='history' and p_price is not null
  and p_price::text not in ('NaN','Infinity','-Infinity')
  and coalesce(p_extra,0)::text not in ('NaN','Infinity','-Infinity')
 then round(p_price+coalesce(p_extra,0),2)
 else null end
$fn$;

create or replace function private.hub_stena_price_basis_v1(p_type text,p_count numeric)
returns text language sql immutable set search_path='' as $fn$
 select 'source_row_total'::text
$fn$;

insert into private.hub_stena_price_correction_audit_v1
 (tenant_id,file_hash,row_number,revenue_object_id,before_amount,after_amount)
select r.tenant_id,r.file_hash,r.row_number,r.revenue_object_id,r.amount,
 private.hub_stena_amount_v2(f.source_kind,r.price,r.extra,r.load_count,r.settled_amount,r.load_carrier_type)
from private.hub_stena_rows_v1 r join private.hub_stena_files_v1 f using(tenant_id,file_hash)
where f.source_kind='history' and r.amount is distinct from
 private.hub_stena_amount_v2(f.source_kind,r.price,r.extra,r.load_count,r.settled_amount,r.load_carrier_type);

update private.hub_stena_rows_v1 r set amount=a.after_amount
from private.hub_stena_price_correction_audit_v1 a
where r.tenant_id=a.tenant_id and r.file_hash=a.file_hash and r.row_number=a.row_number;

-- Diagnostic comparison only: Workify is not the authority for Stena prices.
create view private.hub_stena_price_review_v1 with(security_invoker=true) as
with workify as (
 select a.tenant_id,a.portal_ids[1] object_id,
 sum((a.before_fact->>'amount')::numeric) workify_amount,count(*) workify_rows
 from private.hub_stena_projection_audit_v1 a
 join private.hub_kpi_report_state s on s.tenant_id=a.tenant_id and s.active_generation=a.generation_id
 where cardinality(a.portal_ids)=1
 group by a.tenant_id,a.portal_ids[1]
)
select r.tenant_id,r.revenue_object_id,r.booking,r.occurred_on,r.registration,
 f.file_name,r.row_number,r.price,r.extra,r.load_count,
 coalesce(o.amount,r.amount) stena_amount,w.workify_amount,w.workify_rows,
 w.workify_amount-coalesce(o.amount,r.amount) difference,
 'needs_reconciliation_not_automatic_override'::text status
from private.hub_stena_rows_v1 r join private.hub_stena_files_v1 f using(tenant_id,file_hash)
join workify w on w.tenant_id=r.tenant_id and w.object_id=r.revenue_object_id
left join private.hub_stena_amount_overrides_v1 o on o.tenant_id=r.tenant_id and o.revenue_object_id=r.revenue_object_id
where f.source_kind='history' and o.revenue_object_id is null
 and abs(w.workify_amount-r.amount)>=1;
revoke all on private.hub_stena_price_review_v1 from public,anon,authenticated;

do $tests$
begin
 if private.hub_stena_amount_v2('history',3267,null,3,null,'Flak 35 kbm')<>3267
 or private.hub_stena_amount_v2('history',1082,2164,3,null,'Flak 35 kbm')<>3246
 or private.hub_stena_amount_v2('settled',null,null,3,7314,null)<>7314
 or private.hub_stena_amount_v2('history',null,null,3,null,null) is not null
 or private.hub_stena_amount_v2('history',0,null,3,null,null)<>0
 then raise exception 'Stena row amount regression'; end if;
 if exists(select 1 from private.hub_stena_rows_v1 r
 join private.hub_stena_files_v1 f using(tenant_id,file_hash)
 where f.source_kind='history' and r.amount is distinct from round(r.price+coalesce(r.extra,0),2))
 then raise exception 'Stena derived amount mismatch';end if;
end $tests$;

-- Rebuild through the existing authorized report worker. No new identity or auth path.
update private.hub_kpi_report_state s
set status='queued',requested_at=clock_timestamp(),error_code=null
where exists(select 1 from private.hub_stena_rules_v1 r where r.tenant_id=s.tenant_id and r.enabled);
