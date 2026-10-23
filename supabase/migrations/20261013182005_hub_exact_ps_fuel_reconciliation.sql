-- Preserve the approved exact-text policy. Do not suppress supplier invoices,
-- Circle K, Preem or other external purchases, even on account 5360.
create function private.hub_ps_own_tank_source_v1(p_original jsonb,p_account text)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_account='5360' and p_original->>'Verifikationstext'='PS Olje AB',false);
$$;
revoke all on function private.hub_ps_own_tank_source_v1(jsonb,text) from public,anon,authenticated;
grant execute on function private.hub_ps_own_tank_source_v1(jsonb,text) to service_role;

do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_prepare_piusi_facts_v1(uuid,uuid)'::regprocedure);
 needle:=$old$f.category='fuel' and f.description='PS Olje AB'
 and exists(select 1 from private.hub_kpi_prepared_hub_objects o where o.generation_id=p_generation and o.tenant_id=p_tenant and o.object_type='FuelTransaction' and o.data->>'source_system'='piusi_bsmart'
 and date_trunc('month',(o.data->>'transaction_date')::timestamp)::date=date_trunc('month',f.occurred_on)::date)$old$;
 if strpos(definition,needle)=0 then raise exception 'Unexpected own-tank reconciliation policy';end if;
 execute replace(definition,needle,$new$f.category='fuel' and private.hub_ps_own_tank_source_v1(f.original,f.account)
 and exists(select 1 from private.hub_kpi_prepared_facts p where p.generation_id=p_generation and p.tenant_id=p_tenant and p.source='Piusi' and p.kind='cost'
 and date_trunc('month',p.occurred_on)=date_trunc('month',f.occurred_on))$new$);
end $migration$;

create table private.hub_ps_fuel_runs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,previous_generation uuid not null,
 original_hash text not null,expected_rows bigint not null,expected_amount numeric not null,
 approval_reference text not null,status text not null default 'pending',verified_generation uuid,verified_at timestamptz,result jsonb
);
create unique index hub_ps_one_pending on private.hub_ps_fuel_runs(tenant_id) where status='pending';
alter table private.hub_ps_fuel_runs enable row level security;
revoke all on private.hub_ps_fuel_runs from public,anon,authenticated;
create table private.hub_ps_fuel_items(
 run_id uuid not null references private.hub_ps_fuel_runs(id),tenant_id uuid not null,
 fact_id text not null,occurred_on date not null,amount numeric not null,cost_center text,
 evidence jsonb not null,primary key(run_id,fact_id)
);
alter table private.hub_ps_fuel_items enable row level security;
revoke all on private.hub_ps_fuel_items from public,anon,authenticated;

create function private.hub_ps_validate_fuel_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
declare run record;raw_hash text;actual_rows bigint;actual_amount numeric;
begin
 select * into run from private.hub_ps_fuel_runs where tenant_id=p_tenant and status='pending' for update;
 if not found then return;end if;
 select count(*),sum(amount) into actual_rows,actual_amount from private.hub_ps_fuel_items where run_id=run.id and tenant_id=p_tenant;
 if actual_rows is distinct from run.expected_rows or actual_amount is distinct from run.expected_amount then raise exception 'PS audit differs from approved scope';end if;
 if exists(select 1 from private.hub_ps_fuel_items i
 left join private.hub_kpi_prepared_facts f on f.tenant_id=i.tenant_id and f.generation_id=p_generation and f.fact_id=i.fact_id
 where i.run_id=run.id and (f.fact_id is null or f.amount is distinct from 0::numeric
 or not private.hub_ps_own_tank_source_v1(f.original,f.account)
 or f.occurred_on is distinct from i.occurred_on
 or f.original#>>'{_humla_fuel_reconciliation,booked_amount}' is distinct from i.amount::text))
 then raise exception 'PS fuel reconciliation does not match audited originals';end if;
 -- All rows remain, and only the audited consumption duplicates lose KPI impact.
 if exists(select 1 from
 (select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=run.previous_generation)o
 full join (select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation)n using(fact_id)
 left join private.hub_ps_fuel_items i on i.run_id=run.id and i.tenant_id=p_tenant and i.fact_id=o.fact_id
 where row(o.occurred_on,o.kind,o.category,o.project,o.vehicle,o.unit_id,o.unit_name,o.business_group,o.source,o.account,o.cost_center)
 is distinct from row(n.occurred_on,n.kind,n.category,n.project,n.vehicle,n.unit_id,n.unit_name,n.business_group,n.source,n.account,n.cost_center)
 or (i.fact_id is null and o.amount is distinct from n.amount)
 or (i.fact_id is not null and o.amount is distinct from i.amount))
 then raise exception 'PS correction changed unrelated financial rows';end if;
 select md5(string_agg(md5(to_jsonb(r)::text),','order by r.id)) into raw_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 if raw_hash is distinct from run.original_hash then raise exception 'Original imports changed';end if;
 update private.hub_ps_fuel_runs set status='verified',verified_generation=p_generation,verified_at=clock_timestamp(),
 result=jsonb_build_object('rows',actual_rows,'removedDuplicateAmount',actual_amount,'difference',0,'originalsPreserved',true,'otherFactsPreserved',true)
 where id=run.id;
end $$;
revoke all on function private.hub_ps_validate_fuel_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function private.hub_ps_validate_fuel_v1(uuid,uuid) to service_role;
do $migration$
declare definition text;needle text:='perform private.hub_next_validate_revenue_identity_v1(job.tenant_id,generation);';
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected publication validation';end if;
 execute replace(definition,needle,'perform private.hub_ps_validate_fuel_v1(job.tenant_id,generation);'||chr(10)||needle);
end $migration$;

-- Add verification evidence to the existing scoped dashboard contract.
do $migration$
declare definition text;needle text:=$old$'active_allocation_rules',(select count(*)$old$;
begin
 definition:=pg_get_functiondef('public.hub_kpi_center_reconciliation_v1(uuid,date,date)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected center reconciliation contract';end if;
 execute replace(definition,needle,$new$'transpa_coverage',(select jsonb_build_object('reports',count(*),'employees',count(distinct t.employee_id),'hours',round(coalesce(sum(t.work_hours),0),2),
 'cost_codes',(select coalesce(jsonb_agg(jsonb_build_object('code',c.code,'reports',c.reports) order by c.code),'[]'::jsonb)
 from(select code.value code,count(distinct x.time_report_id) reports from public.kpi_transpa_time_facts x
 cross join lateral jsonb_array_elements_text(x.cost_distribution_codes)code
 where x.tenant_id=p_tenant_id and x.work_date between p_from and p_to and x.work_hours>0 group by code.value)c))
 from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant_id and t.work_date between p_from and p_to and t.work_hours>0),
 'fuel_correction',(select jsonb_build_object('status',r.status,'result',r.result,
 'periodRows',(select count(*) from private.hub_ps_fuel_items i where i.run_id=r.id and i.occurred_on between p_from and p_to),
 'periodAmount',(select coalesce(sum(i.amount),0) from private.hub_ps_fuel_items i where i.run_id=r.id and i.occurred_on between p_from and p_to))
 from private.hub_ps_fuel_runs r where r.tenant_id=p_tenant_id order by r.verified_at desc nulls last limit 1),
 'active_allocation_rules',(select count(*)$new$);
end $migration$;
