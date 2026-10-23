-- User-confirmed allocation: full supplier work (4015/6840), plus project 2105.
alter table private.hub_saw_activity_rules_v1 add column supplier_accounts text[] not null default array['4015','6840'], add column additional_cost_project_id uuid references public.hub_objects(id);
update private.hub_saw_activity_rules_v1 r set supplier_share=1, additional_cost_project_id=public.hub_resolve_canonical_object_v1(r.tenant_id,k.object_id),reason='User confirmed 100% supplier accounts 4015/6840 and all costs of 2105, separately reported'
from public.hub_identity_keys k where k.tenant_id=r.tenant_id and k.identity_type='next_project_number' and k.identity_value='2105';
CREATE OR REPLACE FUNCTION private.hub_apply_saw_activity_v1(p_tenant uuid, p_generation uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r private.hub_saw_activity_rules_v1;f private.hub_kpi_prepared_facts;outrow private.hub_kpi_prepared_facts;
 hours numeric;share numeric;allocation numeric;why text;meta jsonb;project_id uuid;before_totals jsonb;after_totals jsonb;
begin
 select * into r from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant;
 if not found then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into before_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)x;
 for f in select * from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and occurred_on>=r.valid_from and not(original?'_humla_saw_activity') and
 ((kind='revenue' and source='Workify' and original->>'Artikelnummer'='12-04') or kind='cost')
 loop
  hours:=null;share:=null;why:=null;allocation:=null;
  if f.kind='revenue' then
   if f.unit_id is null or f.unit_id=r.unit_id or lower(trim(f.original->>'Enhet'))not in('tim','h','timme','timmar') or not coalesce(trim(f.original->>'Kvantitet')~'^-?[0-9]+([.,][0-9]+)?$',false)then continue;end if;
   hours:=replace(trim(f.original->>'Kvantitet'),',','.')::numeric;
   allocation:=f.amount-hours*r.truck_hour_rate;why:='article_hour_split';
  else
   -- An invoice line that also matches a project is allocated once; the explicit supplier share wins.
   if lower(trim(f.original->>'Leverantör'))=lower(r.supplier_name) and f.source='NEXT' and f.account=any(r.supplier_accounts) then
    share:=r.supplier_share;why:='supplier_work_full';
   else
    select public.hub_resolve_canonical_object_v1(p_tenant,k.object_id) into project_id from public.hub_identity_keys k
     where k.tenant_id=p_tenant and k.identity_type='next_project_number' and k.identity_value=f.project limit 1;
    if project_id=r.additional_cost_project_id then share:=1;why:='marcus_vehicle_cost';
    elsif f.source not like 'NEXT%' then continue;
    elsif project_id=any(r.project_ids)then share:=1;why:='confirmed_saw_project';
    elsif project_id=r.review_project_id and private.hub_saw_cost_evidence_v1(p_tenant,p_generation,f.original) is not null then
     share:=1;why:='saw_evidence_on_shared_project';
    else continue;end if;
   end if;
   allocation:=case when share=1 then f.amount else round(f.amount*share,2) end;
  end if;
  meta:=jsonb_build_object('rule','saw_activity_v1','reason',why,'original_fact_id',f.fact_id,'original_amount',f.amount,'original_unit_id',f.unit_id,'original_unit_name',f.unit_name,'original_cost_center',f.cost_center,'hours',hours,'truck_hour_rate',r.truck_hour_rate,'allocated_amount',allocation,'share',share,'verified_evidence',case when why='saw_evidence_on_shared_project' then private.hub_saw_cost_evidence_v1(p_tenant,p_generation,f.original)end);
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
 delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts ff where ff.tenant_id=p_tenant and ff.generation_id=p_generation and ff.original?'_humla_saw_activity' and d.tenant_id=ff.tenant_id and d.generation_id=ff.generation_id and d.fact_id=ff.fact_id;
 insert into private.hub_kpi_prepared_display_facts select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_saw_activity';
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into after_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)x;
 if before_totals is distinct from after_totals then raise exception 'Saw allocation changed financial totals';end if;
end $function$

;
create table private.hub_saw_cost_revision_audit_v1 (
 revision text not null, tenant_id uuid not null, generation_id uuid not null, fact_id text not null,
 before_fact jsonb not null, created_at timestamptz not null default now(),
 primary key(revision,tenant_id,generation_id,fact_id));
alter table private.hub_saw_cost_revision_audit_v1 enable row level security;
revoke all on private.hub_saw_cost_revision_audit_v1 from public,anon,authenticated;
do $repair$
declare t record; before_totals jsonb; after_totals jsonb;
begin
 perform pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));
 for t in select r.tenant_id,s.active_generation as generation_id from private.hub_saw_activity_rules_v1 r join private.hub_kpi_report_state s using(tenant_id) where r.additional_cost_project_id is not null loop
 perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||t.tenant_id::text,0));
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into before_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=t.tenant_id and generation_id=t.generation_id group by 1,2)x;
 insert into private.hub_saw_cost_revision_audit_v1(revision,tenant_id,generation_id,fact_id,before_fact)
 select 'full_work_and_marcus',f.tenant_id,f.generation_id,f.fact_id,to_jsonb(f) from private.hub_kpi_prepared_facts f
 where f.tenant_id=t.tenant_id and f.generation_id=t.generation_id and f.kind='cost' and f.original?'_humla_saw_activity';
 if exists(select 1 from private.hub_kpi_prepared_facts f where f.tenant_id=t.tenant_id and f.generation_id=t.generation_id and f.kind='cost' and f.original#>>'{_humla_saw_activity,branch}'='saw' and not exists(select 1 from private.hub_kpi_prepared_facts p where p.tenant_id=f.tenant_id and p.generation_id=f.generation_id and p.fact_id=f.original#>>'{_humla_saw_activity,original_fact_id}' and p.original#>>'{_humla_saw_activity,branch}'='retained')) then raise exception 'Missing retained cost';end if;
 delete from private.hub_kpi_prepared_display_facts d using private.hub_saw_cost_revision_audit_v1 a where a.revision='full_work_and_marcus' and a.tenant_id=t.tenant_id and a.generation_id=t.generation_id and d.tenant_id=a.tenant_id and d.generation_id=a.generation_id and d.fact_id=a.fact_id;
 delete from private.hub_kpi_prepared_facts f where f.tenant_id=t.tenant_id and f.generation_id=t.generation_id and f.kind='cost' and f.original#>>'{_humla_saw_activity,branch}'='saw';
 update private.hub_kpi_prepared_facts f set amount=(f.original#>>'{_humla_saw_activity,original_amount}')::numeric,original=f.original-'_humla_saw_activity',display_original=f.display_original-'_humla_saw_activity'
 where f.tenant_id=t.tenant_id and f.generation_id=t.generation_id and f.kind='cost' and f.original#>>'{_humla_saw_activity,branch}'='retained';
 insert into private.hub_kpi_prepared_display_facts
 select f.generation_id,f.tenant_id,f.fiscal_year,f.fact_id,f.occurred_on,f.kind,f.amount,f.category,f.project,f.vehicle,f.unit_id,f.unit_name,f.business_group,f.source,f.cost_center,f.display_original
 from private.hub_kpi_prepared_facts f join private.hub_saw_cost_revision_audit_v1 a on a.tenant_id=f.tenant_id and a.generation_id=f.generation_id and a.fact_id=f.fact_id
 where a.revision='full_work_and_marcus' and f.tenant_id=t.tenant_id and f.generation_id=t.generation_id;
 perform private.hub_apply_saw_activity_v1(t.tenant_id,t.generation_id);
 select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into after_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=t.tenant_id and generation_id=t.generation_id group by 1,2)x;
 if before_totals is distinct from after_totals then raise exception 'Revision changed financial totals';end if;
 end loop;
end $repair$;
