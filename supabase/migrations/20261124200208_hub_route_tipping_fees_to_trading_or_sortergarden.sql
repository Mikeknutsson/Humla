-- External tipping is trading. Only receipts for our own facilities belong to Sortergården.
create or replace function private.hub_route_tipping_revenue_v1(p_tenant uuid, p_generation uuid)
returns integer
language plpgsql
set search_path to ''
set jit to 'off'
as $function$
declare
 changed integer;
begin
 with settings as materialized (
  select valid_from, target_unit_id
  from private.hub_vehicle_revenue_component_rules_v1
  where tenant_id=p_tenant and rule_key='external_ifa_tipping'
 ), source_rows as materialized (
  select f.fact_id, f.occurred_on, f.project, f.vehicle, f.unit_id, f.unit_name,
   f.business_group, f.cost_center, f.cost_center_name, f.category, f.kind, f.source,
   trim(coalesce(f.original->>'Artikelnummer','')) as code,
   coalesce(nullif(trim(f.original->>'Artikelnamn'),''),f.description,'') as article,
   trim(coalesce(f.original->>'ArtikelKommentar','')) as remark,
   trim(coalesce(f.original->>'Ordernummer','')) as order_no,
   trim(coalesce(f.original->>'Enhet','')) as measure,
   settings.target_unit_id as trading_id,
   coalesce(f.original->>'Konto',f.account) as account,
   u.data->>'unit_type' as current_unit_type
  from private.hub_kpi_prepared_facts f
  join settings on f.occurred_on>=settings.valid_from
  left join public.hub_objects u on u.tenant_id=f.tenant_id and u.id=f.unit_id
  where f.tenant_id=p_tenant and f.generation_id=p_generation
   and ((f.source='Workify' and f.kind='revenue')
     or (f.project='5100' and f.cost_center='30' and f.kind='cost' and f.category='tipp_deponi'))
 ), classified as (
  select r.*,
   case
    when r.kind='cost' then 'project_cost'
    when r.project='5100' and r.code in ('F6','F9','F19') and r.article ~* '^Försäljning' then 'trading_sale'
    when r.code='BJ0' and r.order_no='45040' and r.remark ~* '^Bakbar sandlådesand från Björklunds' and r.measure ilike 'Ton' then 'gravel_sale'
    when r.kind='revenue' and (
     r.article ~* '^(tippavgift|tippning|behandlingsavgift|deponiavgift|mottagningsavgift)'
     or (r.category='tipp_deponi' and (r.vehicle is not null or r.current_unit_type in ('vehicle','compound'))
       and r.article !~* '^(försäljning|fyllnadsmaterial)')
     or (r.code='BJ0' and r.article ilike 'Annan' and r.measure ilike 'Ton'
       and r.remark ~* '^mkm[ -]*(schakt|massor)([[:space:]]|$)'
       and exists (
        select 1 from private.hub_kpi_prepared_facts sibling
        where sibling.tenant_id=p_tenant and sibling.generation_id=p_generation
         and sibling.source='Workify' and sibling.kind='revenue' and sibling.fact_id<>r.fact_id
         and sibling.original->>'Ordernummer'=r.order_no
         and sibling.occurred_on between r.occurred_on-14 and r.occurred_on+14
         and sibling.original->>'Enhet' ilike 'Tim'
         and sibling.original->>'Artikelnamn' ~* '^(ekipage|enkelbil|transport|lastbil)'
       ))
    ) then 'tipping'
   end as route
  from source_rows r
 ), destinations as (
  select r.*,
   case
    when r.route='gravel_sale' then '4004'
    when r.route<>'tipping' then '5100'
    when concat_ws(' ',r.article,r.remark) ~* 'extern mottagare|miljögården|moskogen|vankiva|bubbetorp'
      or r.code in ('3-07','3-29','FA-7','FA-8') then '5100'
    when r.cost_center='20' and r.project in ('5002','5003','5004','5005','5011','5012') then r.project
    when r.code in ('3-09','3-15','3-16','3-24') then '5002'
    when r.code='3-03' then '5003'
    when r.code in ('3-04','3-05','3-14','3-21') then '5004'
    when r.code in ('3-00','3-01','3-02','3-06','3-17','3-2-1','3-25','3-26')
      or r.article ~* 'pukavik' then '5005'
    when r.code in ('3-11','3-12') then '5012'
    else '5100'
   end as target_project,
   case when r.route in ('gravel_sale','trading_sale') or (r.route='project_cost' and r.account='4022') then 'material'
    when r.route='project_cost' and r.account='8422' then 'other' else 'tipp_deponi' end as target_category
  from classified r
  where r.route is not null
 ), candidates as materialized (
  select d.*, up.unit_id as target_unit, up.payload->>'name' as target_name,
   case when d.route='gravel_sale' then 'Grusmaterial' else g.name end as target_group,
   case when d.route='gravel_sale' then d.cost_center else pc.cost_center end as target_center,
   case when d.route='gravel_sale' then d.cost_center_name else pc.cost_center_name end as target_center_name
  from destinations d
  join lateral (
   select p.unit_id,p.payload from public.kpi_unit_periods p
   where p.tenant_id=p_tenant and p.payload->'projects' ? d.target_project
    and p.valid_from<=d.occurred_on and (p.valid_to is null or p.valid_to>=d.occurred_on)
    and (d.target_project<>'5100' or p.unit_id=d.trading_id)
   order by p.valid_from desc,p.unit_id limit 1
  ) up on true
  join public.kpi_business_groups g on g.tenant_id=p_tenant and g.id::text=up.payload->>'business_group_id'
  join lateral (
   select p.cost_center,p.cost_center_name from public.kpi_project_classification_periods p
   where p.tenant_id=p_tenant and p.project_reference=d.target_project
    and p.valid_from<=d.occurred_on and (p.valid_to is null or p.valid_to>=d.occurred_on)
   order by p.valid_from desc limit 1
  ) pc on true
  where (d.unit_id,d.unit_name,d.business_group,d.cost_center,d.project,d.category)
     is distinct from (up.unit_id,up.payload->>'name',
      case when d.route='gravel_sale' then 'Grusmaterial' else g.name end,
      case when d.route='gravel_sale' then d.cost_center else pc.cost_center end,d.target_project,d.target_category)
     or d.vehicle is not null
 ), updated as (
  update private.hub_kpi_prepared_facts f
  set vehicle=null,unit_id=c.target_unit,unit_name=c.target_name,project=c.target_project,
   business_group=c.target_group,cost_center=c.target_center,cost_center_name=c.target_center_name,
   category=c.target_category,
   original=coalesce(f.original,'{}')||jsonb_build_object('_humla_tipping_routing',jsonb_build_object(
    'route',c.route,'old_vehicle',c.vehicle,'old_unit',c.unit_name,'old_project',c.project,
    'old_group',c.business_group,'old_cost_center',c.cost_center,'old_category',c.category)),
   classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('tipping_routing',c.route),
   display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_tipping_routing',jsonb_build_object('route',c.route))
  from candidates c
  where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=c.fact_id
  returning f.*
 ), synced as (
  update private.hub_kpi_prepared_display_facts d
  set vehicle=u.vehicle,unit_id=u.unit_id,unit_name=u.unit_name,project=u.project,business_group=u.business_group,
   cost_center=u.cost_center,category=u.category,original=u.display_original
  from updated u
  where d.tenant_id=u.tenant_id and d.generation_id=u.generation_id and d.fact_id=u.fact_id
  returning d.fact_id
 )
 select count(*) into changed from updated;
 return changed;
end
$function$;

revoke all on function private.hub_route_tipping_revenue_v1(uuid,uuid) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION private.hub_detach_vehicle_nontransport_v1(p_tenant uuid, p_generation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare before_money jsonb;after_money jsonb;changed integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where tenant_id=p_tenant and id=p_generation)then raise exception 'Generation mismatch';end if;
 select jsonb_build_object('rows',count(*),'revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost'))
 into before_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 with candidates as materialized(
 select f.fact_id,f.unit_id old_unit,f.unit_name old_name,f.vehicle old_vehicle,f.project old_project,f.category old_category,f.cost_center old_cost_center,f.business_group old_group,
 r.rule_key,r.target_unit_id,up.payload->>'name' target_name,up.payload->'projects'->>0 target_project,
 case when r.rule_key='pure_material' then 'Grusmaterial' else g.name end target_group,
 case when r.rule_key='pure_material' then 'material' else 'tipp_deponi' end target_category,pc.cost_center target_cost_center,pc.cost_center_name target_cost_center_name
 from private.hub_kpi_prepared_facts f
 left join public.hub_objects carrier on carrier.id=f.unit_id and carrier.tenant_id=f.tenant_id and carrier.object_type='EconomicUnit'
 join private.hub_vehicle_revenue_component_rules_v1 r on r.tenant_id=f.tenant_id and f.occurred_on>=r.valid_from
 join public.hub_objects target on target.id=r.target_unit_id and target.tenant_id=r.tenant_id and target.object_type='EconomicUnit'
 join public.kpi_unit_periods up on up.tenant_id=r.tenant_id and up.unit_id=r.target_unit_id and up.valid_from<=f.occurred_on and(up.valid_to is null or up.valid_to>=f.occurred_on)
 join public.kpi_business_groups g on g.tenant_id=r.tenant_id and g.id::text=up.payload->>'business_group_id'
 left join lateral(select pc.cost_center,pc.cost_center_name from public.kpi_project_classification_periods pc
 where pc.tenant_id=p_tenant and pc.project_reference=up.payload->'projects'->>0 and pc.valid_from<=f.occurred_on and(pc.valid_to is null or pc.valid_to>=f.occurred_on) order by pc.valid_from desc limit 1)pc on true
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='Workify' and f.kind='revenue'
 and (r.rule_key='fill_material' or carrier.data->>'unit_type' in('vehicle','compound'))
 and ((r.rule_key='pure_material' and ((coalesce(nullif(f.original->>'Artikelnamn',''),f.description,'') ~* '^(Krossmaterial|Murgrus|Rörgrus|Gjutgrus|Natursingel)' and concat_ws(' ',f.original->>'Artikelnamn',f.description) !~* 'transport|uttaget.*kund') or (trim(coalesce(f.original->>'ArtikelKommentar','')) ~* '^inte ink[l]?[.]?[[:space:]]+transport[.]?$' and coalesce(f.original->>'Artikelnamn',f.description,'') ~* 'Råberg')))
 or(r.rule_key='external_ifa_tipping' and f.original->>'Artikelnummer'='3-29' and coalesce(f.original->>'Artikelnamn',f.description,'') ilike 'Tippavgift IFA-Schakt%')
 or (r.rule_key='fill_material' and coalesce(f.original->>'Artikelnamn',f.description,'') ilike '%Fyllnadsmaterial%' and pc.cost_center is not null
 and(f.unit_id is distinct from r.target_unit_id or f.cost_center is distinct from pc.cost_center or f.category<>'tipp_deponi' or f.original#>>'{_humla_material_separation,status}'='needs_review')))
 ), updated as(
 update private.hub_kpi_prepared_facts f set unit_id=c.target_unit_id,unit_name=c.target_name,vehicle=null,project=c.target_project,
 business_group=c.target_group,category=c.target_category,
 cost_center=case when c.rule_key='fill_material' then c.target_cost_center else f.cost_center end,
 cost_center_name=case when c.rule_key='fill_material' then c.target_cost_center_name else f.cost_center_name end,
 original=(case when c.rule_key='fill_material' or trim(coalesce(f.original->>'ArtikelKommentar','')) ~* '^inte ink[l]?[.]?[[:space:]]+transport[.]?$' then (f.original-'_humla_material_separation')||jsonb_build_object('_humla_previous_material_review',f.original->'_humla_material_separation') else f.original end)||jsonb_build_object('_humla_vehicle_component_correction',jsonb_build_object('rule',c.rule_key,'old_unit_id',c.old_unit,'old_unit_name',c.old_name,'old_vehicle',c.old_vehicle,'old_project',c.old_project,'old_category',c.old_category,'old_cost_center',c.old_cost_center,'old_group',c.old_group,'target_unit_id',c.target_unit_id,'actor',auth.uid(),'corrected_at',now())),
 classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('vehicle_component_rule',c.rule_key),
 display_original=(case when c.rule_key='fill_material' then coalesce(f.display_original,'{}')-'_humla_material_separation' else coalesce(f.display_original,'{}') end)||jsonb_build_object('_humla_vehicle_component_correction',jsonb_build_object('rule',c.rule_key,'old_unit_id',c.old_unit,'target_unit_id',c.target_unit_id))
 from candidates c where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=c.fact_id returning f.*
 ), synced as(
 update private.hub_kpi_prepared_display_facts d set unit_id=u.unit_id,unit_name=u.unit_name,vehicle=u.vehicle,project=u.project,
 business_group=u.business_group,category=u.category,cost_center=u.cost_center,original=u.display_original
 from updated u where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=u.fact_id returning d.fact_id
 )
 select count(*) into changed from updated;
 select jsonb_build_object('rows',count(*),'revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost'))
 into after_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 if before_money is distinct from after_money then raise exception 'Component correction changed financial totals';end if;
 changed:=changed+private.hub_route_tipping_revenue_v1(p_tenant,p_generation);
 return jsonb_build_object('changed_rows',changed,'financial_totals_unchanged',true);
end $function$;

do $migration$
declare
 report record;
begin
 perform pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));
 for report in
  select s.tenant_id,s.active_generation from private.hub_kpi_report_state s
  join private.hub_vehicle_revenue_component_rules_v1 r on r.tenant_id=s.tenant_id and r.rule_key='external_ifa_tipping'
  where s.active_generation is not null
 loop
  if private.hub_route_tipping_revenue_v1(report.tenant_id,report.active_generation)>0 then
   update private.hub_kpi_report_state
   set correction_revision=correction_revision+1 where tenant_id=report.tenant_id;
  end if;
 end loop;
end
$migration$;
