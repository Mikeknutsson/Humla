-- NEXT ledger rows and Workify orders have distinct source identities.
create function private.hub_is_next_ledger_revenue_v1(p_source jsonb)
returns boolean language sql immutable set search_path='' as $$
 select coalesce(p_source ?& array['Konto','Projektnr','Verifikation nr','Bokf datum']
 and not(p_source?'Ordernummer') and nullif(trim(p_source->>'Konto'),'') is not null
 and nullif(trim(p_source->>'Projektnr'),'') is not null
 and nullif(trim(p_source->>'Verifikation nr'),'') is not null,false);
$$;
revoke all on function private.hub_is_next_ledger_revenue_v1(jsonb) from public,anon;
grant execute on function private.hub_is_next_ledger_revenue_v1(jsonb) to authenticated,service_role;

do $migration$
declare signature text;definition text;needle text;
begin
 foreach signature in array array['private.hub_kpi_financial_facts_v1(uuid,date,date)','private.hub_kpi_financial_month_facts_v1(uuid,date,date,integer[])'] loop
 definition:=pg_get_functiondef(signature::regprocedure);
 needle:='case when x.data_kind=''revenue'' then case when nullif(x.allocation->>''project_carrier_reference'','''') is not null';
 if strpos(definition,needle)=0 then raise exception 'Unexpected revenue project adapter';end if;
 definition:=replace(definition,needle,'case when x.data_kind=''revenue'' and private.hub_is_next_ledger_revenue_v1(x.source_data) then coalesce(nullif(trim(x.project_reference),''''),trim(x.source_data->>''Projektnr'')) when x.data_kind=''revenue'' then case when nullif(x.allocation->>''project_carrier_reference'','''') is not null');
 needle:='case when x.data_kind=''cost'' then ''NEXT'' else ''Workify'' end src';
 if strpos(definition,needle)=0 then raise exception 'Unexpected source adapter';end if;
 definition:=replace(definition,needle,'case when x.data_kind=''cost'' or private.hub_is_next_ledger_revenue_v1(x.source_data) then ''NEXT'' else ''Workify'' end src');
 needle:='x.description descr,x.account acc';
 if strpos(definition,needle)=0 then raise exception 'Unexpected account adapter';end if;
 definition:=replace(definition,needle,'x.description descr,case when x.data_kind=''revenue'' and private.hub_is_next_ledger_revenue_v1(x.source_data) then coalesce(nullif(x.account,''''),x.source_data->>''Konto'') else x.account end acc');
 -- Workify article/order rules must not interpret ledger rows.
 definition:=replace(definition,'ar on true','ar on not private.hub_is_next_ledger_revenue_v1(x.source_data)');
 definition:=replace(definition,'ov on true','ov on not private.hub_is_next_ledger_revenue_v1(x.source_data)');
 execute definition;
 end loop;
end $migration$;

create table private.hub_next_revenue_identity_runs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null,previous_generation uuid not null,
 original_hash text not null,approval_reference text not null,status text not null default 'pending',
 verified_generation uuid,verified_at timestamptz,result jsonb
);
alter table private.hub_next_revenue_identity_runs enable row level security;
revoke all on private.hub_next_revenue_identity_runs from public,anon,authenticated;
create unique index hub_next_revenue_pending on private.hub_next_revenue_identity_runs(tenant_id) where status='pending';

create function private.hub_next_validate_revenue_identity_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql set search_path='' as $$
declare run record;raw_hash text;changed bigint;ledger_amount numeric;
begin
 select * into run from private.hub_next_revenue_identity_runs where tenant_id=p_tenant and status='pending' for update;
 if not found then return;end if;
 -- Every financial row remains exactly once, with the same date/kind/amount.
 if exists(select 1 from
 (select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=run.previous_generation)o
 full join (select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation)n using(fact_id)
 where row(o.occurred_on,o.kind,o.amount) is distinct from row(n.occurred_on,n.kind,n.amount)
 or (not(o.kind='revenue' and private.hub_is_next_ledger_revenue_v1(o.original)) and
 row(o.category,o.project,o.vehicle,o.unit_id,o.unit_name,o.business_group,o.source,o.account,o.cost_center)
 is distinct from row(n.category,n.project,n.vehicle,n.unit_id,n.unit_name,n.business_group,n.source,n.account,n.cost_center)))
 then raise exception 'Revenue identity correction changed other financial facts';end if;
 if exists(select 1 from private.hub_kpi_prepared_facts f join public.kpi_import_rows r on r.id::text=f.fact_id and r.tenant_id=f.tenant_id
 where f.generation_id=p_generation and f.tenant_id=p_tenant and f.kind='revenue' and private.hub_is_next_ledger_revenue_v1(r.source_data)
 and (f.source<>'NEXT' or f.project is distinct from coalesce(nullif(trim(r.project_reference),''),trim(r.source_data->>'Projektnr'))
 or f.account is distinct from coalesce(nullif(r.account,''),r.source_data->>'Konto')))
 then raise exception 'NEXT ledger identity does not match original row';end if;
 select md5(string_agg(md5(to_jsonb(r)::text),',' order by r.id)) into raw_hash from public.kpi_import_rows r where tenant_id=p_tenant;
 if raw_hash is distinct from run.original_hash then raise exception 'Original imports changed';end if;
 select count(*),sum(amount) into changed,ledger_amount from private.hub_kpi_prepared_facts
 where tenant_id=p_tenant and generation_id=p_generation and kind='revenue' and private.hub_is_next_ledger_revenue_v1(original);
 update private.hub_next_revenue_identity_runs set status='verified',verified_generation=p_generation,verified_at=clock_timestamp(),
 result=jsonb_build_object('rows',changed,'amount',ledger_amount,'amountDifference',0,'otherFactsPreserved',true,'originalsPreserved',true)
 where id=run.id;
end $$;
revoke all on function private.hub_next_validate_revenue_identity_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function private.hub_next_validate_revenue_identity_v1(uuid,uuid) to service_role;
do $migration$
declare definition text;needle text:='perform private.hub_next_validate_completeness_v1(job.tenant_id,generation);';
begin
 definition:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Unexpected report worker';end if;
 execute replace(definition,needle,'perform private.hub_next_validate_revenue_identity_v1(job.tenant_id,generation);'||chr(10)||needle);
end $migration$;

create function public.hub_kpi_center_reconciliation_v1(p_tenant_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare generation uuid;answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid reconciliation period';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 if generation is null then return jsonb_build_object('available',false);end if;
 with facts as materialized(
 select f.*,case when kind='revenue' and private.hub_is_next_ledger_revenue_v1(original) then 'NEXT bokförda intäkter'
 when kind='revenue' and original?'Ordernummer' then 'Workify orderrader'
 when kind='revenue' then 'Övriga intäktsunderlag' else source end source_label
 from private.hub_kpi_prepared_facts f where tenant_id=p_tenant_id and generation_id=generation and occurred_on between p_from and p_to
 ), totals as(
 select cost_center,kind,source_label,count(*) rows,round(sum(amount),2) amount,
 count(*)filter(where original->>'_humla_allocation_review'='true' or (kind='cost' and unit_id is null)) allocation_review_rows
 from facts where cost_center in('20','30','40','unclassified') group by 1,2,3
 ), centers as(select * from(values('30','Transport'),('20','Sortergården'),('40','Verkstad'),('unclassified','Ej klassificerat – hela verksamheten'))c(code,name))
 select jsonb_build_object('available',true,'from',p_from,'to',p_to,'generation',generation,
 'synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant_id),
 'centers',(select jsonb_agg(jsonb_build_object('code',c.code,'name',c.name,
 'revenue',coalesce((select round(sum(amount),2) from facts where cost_center=c.code and kind='revenue'),0),
 'cost',coalesce((select round(sum(amount),2) from facts where cost_center=c.code and kind='cost'),0),
 'revenue_rows',(select count(*) from facts where cost_center=c.code and kind='revenue'),
 'cost_rows',(select count(*) from facts where cost_center=c.code and kind='cost'),
 'sources',coalesce((select jsonb_agg(to_jsonb(t) order by kind,source_label) from totals t where t.cost_center=c.code),'[]'::jsonb)) order by c.code) from centers c),
 'identity_correction',(select jsonb_build_object('status',status,'result',result) from private.hub_next_revenue_identity_runs where tenant_id=p_tenant_id order by verified_at desc nulls last limit 1),
 'active_allocation_rules',(select count(*) from public.hub_cost_allocation_rules where tenant_id=p_tenant_id and enabled)) into answer;
 return answer;
end $$;
revoke all on function public.hub_kpi_center_reconciliation_v1(uuid,date,date) from public,anon;
grant execute on function public.hub_kpi_center_reconciliation_v1(uuid,date,date) to authenticated,service_role;
