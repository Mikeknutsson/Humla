-- User-confirmed activity allocation. Source keys are resolved by the Hub adapter;
-- the persistent rule and financial output use the canonical EconomicUnit ID.
create table private.hub_saw_activity_rules_v1(
 tenant_id uuid primary key references public.hub_tenants(id),
 unit_id uuid not null references public.hub_objects(id),
 truck_hour_rate numeric not null check(truck_hour_rate>=0),
 project_ids uuid[] not null, review_project_id uuid not null references public.hub_objects(id),
 supplier_name text not null, supplier_share numeric not null check(supplier_share between 0 and 1),
 valid_from date not null, reason text not null
);
alter table private.hub_saw_activity_rules_v1 enable row level security;
revoke all on private.hub_saw_activity_rules_v1 from public,anon,authenticated;
do $$declare t uuid;u uuid;ids uuid[];review_id uuid;begin
 select tenant_id into strict t from public.kpi_units where name='CMO589' and origin='manual';
 perform set_config('request.jwt.claim.sub',(select user_id::text from public.hub_tenant_members where tenant_id=t and role='owner' and status='active' and display_name ilike '%Mike%' limit 1),true);
 select array_agg(distinct public.hub_resolve_canonical_object_v1(t,object_id)) into ids from public.hub_identity_keys where tenant_id=t and identity_type='next_project_number' and identity_value in('10648','11291');
 select public.hub_resolve_canonical_object_v1(t,object_id) into strict review_id from public.hub_identity_keys where tenant_id=t and identity_type='next_project_number' and identity_value='10818';
 if cardinality(ids)<>2 then raise exception 'Saw project identity incomplete';end if;
 insert into public.kpi_units(tenant_id,name,origin,unit_type,projects,registrations,employees,valid_from,enabled)
 values(t,'Sågning','manual','project',array['10648','11291'],'{}','{}','2025-09-01',true) returning id into u;
 insert into private.hub_saw_activity_rules_v1 values(t,u,1250,ids,review_id,'Ett strå vassare i Sölvesborg AB',0.5,'2025-09-01','Mike 2026-10-22: 1250 kr/timme till lastbil, resterande till Sågning; 10648,11291, verifierad sågning på 10818 samt 50% av leverantörens fakturabelopp.');
end $$;

create or replace function private.hub_apply_saw_activity_v1(p_tenant uuid,p_generation uuid)
returns void language plpgsql security definer set search_path='' as $$
declare r private.hub_saw_activity_rules_v1;f private.hub_kpi_prepared_facts;outrow private.hub_kpi_prepared_facts;
 hours numeric;share numeric;allocation numeric;why text;meta jsonb;project_id uuid;before_totals jsonb;after_totals jsonb;
begin
 select * into r from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant;
 if not found then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into before_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)x;
 for f in select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and occurred_on>=r.valid_from and not(original?'_humla_saw_activity') and
 ((kind='revenue' and source='Workify' and original->>'Artikelnummer'='12-04') or(kind='cost' and (source like 'NEXT%' )))
 loop
  hours:=null;share:=null;why:=null;allocation:=null;
  if f.kind='revenue' then
   if f.unit_id is null or f.unit_id=r.unit_id or lower(trim(f.original->>'Enhet'))not in('tim','h','timme','timmar') or not coalesce(trim(f.original->>'Kvantitet')~'^-?[0-9]+([.,][0-9]+)?$',false)then continue;end if;
   hours:=replace(trim(f.original->>'Kvantitet'),',','.')::numeric;
   allocation:=f.amount-hours*r.truck_hour_rate;why:='article_hour_split';
  else
   -- An invoice line that also matches a project is allocated once; the explicit supplier share wins.
   if lower(trim(f.original->>'Leverantör'))=lower(r.supplier_name) and f.source='NEXT' then
    share:=r.supplier_share;why:='supplier_50_percent';
   else
    select public.hub_resolve_canonical_object_v1(p_tenant,k.object_id) into project_id from public.hub_identity_keys k
     where k.tenant_id=p_tenant and k.identity_type='next_project_number' and k.identity_value=f.project limit 1;
    if project_id=any(r.project_ids)then share:=1;why:='confirmed_saw_project';
    elsif project_id=r.review_project_id and concat_ws(' ',f.description,f.original->>'Verifikationstext',f.original->>'AO/ÄTA-benämning',f.original->>'Beskrivning')~*'(sågning|trädfäll|kransåg|beskärning)'then
     share:=1;why:='saw_evidence_on_shared_project';
    else continue;end if;
   end if;
   allocation:=case when share=1 then f.amount else round(f.amount*share,2) end;
  end if;
  meta:=jsonb_build_object('rule','saw_activity_v1','reason',why,'original_fact_id',f.fact_id,'original_amount',f.amount,'original_unit_id',f.unit_id,'original_unit_name',f.unit_name,'original_cost_center',f.cost_center,'hours',hours,'truck_hour_rate',r.truck_hour_rate,'allocated_amount',allocation,'share',share);
  -- Retain full source evidence and earlier allocation history in both branches.
  outrow:=f;outrow.fact_id:=f.fact_id||':saw';outrow.amount:=allocation;outrow.unit_id:=r.unit_id;outrow.unit_name:='Sågning';outrow.business_group:='Sågning';outrow.cost_center:='30';outrow.vehicle:=null;
  outrow.original:=f.original||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','saw'));
  if f.kind='revenue' then outrow.original:=outrow.original||jsonb_build_object('Kvantitet','0');end if;
  outrow.display_original:=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','saw'));
  insert into private.hub_kpi_prepared_facts select (outrow).*;
  update private.hub_kpi_prepared_facts set amount=f.amount-allocation,
   original=f.original||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','retained')),
   display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','retained'))
   where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id;
 end loop;
 delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation and f.original?'_humla_saw_activity' and d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id;
 insert into private.hub_kpi_prepared_display_facts select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_saw_activity';
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into after_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)x;
 if before_totals is distinct from after_totals then raise exception 'Saw allocation changed financial totals';end if;
end $$;
revoke all on function private.hub_apply_saw_activity_v1(uuid,uuid)from public,anon,authenticated;
-- Run after all identity and probability allocations, before generation publication.
do $$declare d text;needle text:='update private.hub_kpi_report_generations set completed_at=clock_timestamp() where id=generation;';begin
 d:=pg_get_functiondef('private.hub_kpi_run_report_jobs_v1()'::regprocedure);
 if position(needle in d)=0 then raise exception 'Report publication hook changed';end if;
 execute replace(d,needle,'perform private.hub_apply_saw_activity_v1(job.tenant_id,generation);'||chr(10)||needle);
end $$;
