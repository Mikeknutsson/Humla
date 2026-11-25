create function private.hub_assign_workify_10818_revenue_v1(p_tenant uuid,p_generation uuid)
returns integer
language sql
set search_path to ''
as $function$
 with target as materialized (
  select r.unit_id, u.name, r.valid_from, u.valid_from unit_from, u.valid_to unit_to
  from private.hub_saw_activity_rules_v1 r
  join public.kpi_units u on u.tenant_id=r.tenant_id and u.id=r.unit_id and u.enabled
  where r.tenant_id=p_tenant
 ), changed as (
  update private.hub_kpi_prepared_facts f
  set unit_id=t.unit_id,unit_name=t.name,vehicle=null,project='10818',
   cost_center='30',cost_center_name='Transport',business_group='Sågning',
   original=coalesce(f.original,'{}')||jsonb_build_object('_humla_workify_10818',jsonb_build_object(
    'reason','standalone_saw_work','previous_project',f.project,'previous_unit',f.unit_name,
    'previous_vehicle',f.vehicle,'previous_cost_center',f.cost_center)),
   display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_workify_10818','standalone_saw_work')
  from target t
  where f.tenant_id=p_tenant and f.generation_id=p_generation
   and f.kind='revenue' and f.source='Workify' and f.amount<>0
   and f.occurred_on>=greatest(t.valid_from,t.unit_from) and (t.unit_to is null or f.occurred_on<=t.unit_to)
   and (f.project is null or f.project='10818')
   and (f.cost_center is null or f.cost_center in ('30','unclassified'))
   and coalesce(f.category,'') not in ('material','tipp_deponi','tipp')
   and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
   and exists (
    select 1 from public.kpi_project_classification_periods p
    where p.tenant_id=f.tenant_id and p.project_reference='10818' and p.cost_center='30'
     and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)
   )
   and (
    (f.original->>'Artikelnummer'='12-041' and lower(btrim(f.original->>'Artikelnamn'))='extra såg-gubbe')
    or (f.original->>'Artikelnummer'='12-042' and lower(btrim(f.original->>'Artikelnamn'))='manuell sågning av träd')
   )
   and row(f.unit_id,f.vehicle,f.project,f.cost_center,f.business_group)
    is distinct from row(t.unit_id,null::text,'10818'::text,'30'::text,'Sågning'::text)
  returning f.*
 ), display_updated as (
  update private.hub_kpi_prepared_display_facts d
  set unit_id=f.unit_id,unit_name=f.unit_name,vehicle=f.vehicle,project=f.project,
   cost_center=f.cost_center,business_group=f.business_group,original=f.display_original
  from changed f
  where d.tenant_id=f.tenant_id and d.generation_id=f.generation_id and d.fact_id=f.fact_id
  returning d.fact_id
 )
 select count(*)::integer from changed
$function$;

revoke all on function private.hub_assign_workify_10818_revenue_v1(uuid,uuid) from public,anon,authenticated,service_role;

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
 perform private.hub_assign_workify_10818_revenue_v1(p_tenant,p_generation);
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
   if lower(trim(f.original->>'Leverantör'))=lower(r.supplier_name) and f.source='NEXT' and f.account=any(r.supplier_accounts) and exists(select 1 from public.hub_identity_keys sk where sk.tenant_id=p_tenant and sk.identity_type='next_project_number' and sk.identity_value=f.project and public.hub_resolve_canonical_object_v1(p_tenant,sk.object_id)=r.supplier_project_id) then
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
  outrow:=f;outrow.fact_id:=f.fact_id||':saw'; outrow.amount:=allocation;outrow.unit_id:=r.unit_id;outrow.unit_name:='Sågning';outrow.business_group:='Sågning';outrow.cost_center:='30';outrow.vehicle:=null;
  outrow.original:=f.original||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','saw'));
  if f.kind='revenue' then outrow.original:=outrow.original||jsonb_build_object('Kvantitet','0');end if;
  outrow.display_original:=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','saw'));
  insert into private.hub_kpi_prepared_facts select (outrow).*;
  update private.hub_kpi_prepared_facts set amount=f.amount-allocation,
   cost_center=case when why='supplier_work_full' then '10' else f.cost_center end,
   unit_id=case when why='supplier_work_full' then null else f.unit_id end,
   unit_name=case when why='supplier_work_full' then null else f.unit_name end,
   business_group=case when why='supplier_work_full' then null else f.business_group end,
   original=f.original||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','retained')),
   display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_saw_activity',meta||jsonb_build_object('branch','retained'))
   where tenant_id=p_tenant and generation_id=p_generation and fact_id=f.fact_id;
 end loop;
 delete from private.hub_kpi_prepared_display_facts d using private.hub_kpi_prepared_facts ff where ff.tenant_id=p_tenant and ff.generation_id=p_generation and ff.original?'_humla_saw_activity' and d.tenant_id=ff.tenant_id and d.generation_id=ff.generation_id and d.fact_id=ff.fact_id;
 insert into private.hub_kpi_prepared_display_facts select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_saw_activity';
 perform private.hub_allocate_saw_supplier_common_v1(p_tenant,p_generation);
select jsonb_agg(to_jsonb(x) order by fiscal_year,kind) into after_totals from(select fiscal_year,kind,sum(amount)amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation group by 1,2)x;
 if before_totals is distinct from after_totals then raise exception 'Saw allocation changed financial totals';end if;
end $function$
;

do $migration$
declare active record;
begin
 perform pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));
 for active in
  select s.tenant_id,s.active_generation from private.hub_kpi_report_state s
  join private.hub_saw_activity_rules_v1 r on r.tenant_id=s.tenant_id
  where s.active_generation is not null
 loop
  if private.hub_assign_workify_10818_revenue_v1(active.tenant_id,active.active_generation)>0 then
   update private.hub_kpi_report_state set correction_revision=correction_revision+1 where tenant_id=active.tenant_id;
  end if;
 end loop;
end
$migration$;
