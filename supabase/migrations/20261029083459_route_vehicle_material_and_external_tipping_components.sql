create table private.hub_vehicle_revenue_component_rules_v1(
 tenant_id uuid not null,rule_key text not null,target_unit_id uuid not null references public.hub_objects(id),
 valid_from date not null,approved_by uuid not null,approved_at timestamptz not null default now(),reason text not null,
 primary key(tenant_id,rule_key),check(rule_key in('pure_material','external_ifa_tipping'))
);
alter table private.hub_vehicle_revenue_component_rules_v1 enable row level security;
revoke all on private.hub_vehicle_revenue_component_rules_v1 from public,anon,authenticated;

create or replace function private.hub_detach_vehicle_nontransport_v1(p_tenant uuid,p_generation uuid)
returns jsonb language plpgsql set search_path='' set jit='off' as $fn$
declare before_money jsonb;after_money jsonb;changed integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where tenant_id=p_tenant and id=p_generation)then raise exception 'Generation mismatch';end if;
 select jsonb_build_object('rows',count(*),'revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost'))
 into before_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 with candidates as materialized(
 select f.fact_id,f.unit_id old_unit,f.unit_name old_name,f.vehicle old_vehicle,f.project old_project,f.category old_category,
 r.rule_key,r.target_unit_id,up.payload->>'name' target_name,up.payload->'projects'->>0 target_project,
 case when r.rule_key='pure_material' then 'Grusmaterial' else g.name end target_group,
 case when r.rule_key='pure_material' then 'material' else 'tipp_deponi' end target_category
 from private.hub_kpi_prepared_facts f
 join public.hub_objects carrier on carrier.id=f.unit_id and carrier.tenant_id=f.tenant_id and carrier.object_type='EconomicUnit'
 join private.hub_vehicle_revenue_component_rules_v1 r on r.tenant_id=f.tenant_id and f.occurred_on>=r.valid_from
 join public.hub_objects target on target.id=r.target_unit_id and target.tenant_id=r.tenant_id and target.object_type='EconomicUnit'
 join public.kpi_unit_periods up on up.tenant_id=r.tenant_id and up.unit_id=r.target_unit_id and up.valid_from<=f.occurred_on and(up.valid_to is null or up.valid_to>=f.occurred_on)
 join public.kpi_business_groups g on g.tenant_id=r.tenant_id and g.id::text=up.payload->>'business_group_id'
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.source='Workify' and f.kind='revenue'
 and carrier.data->>'unit_type' in('vehicle','compound')
 and ((r.rule_key='pure_material' and coalesce(nullif(f.original->>'Artikelnamn',''),f.description,'') ~* '^(Krossmaterial|Murgrus|Rörgrus|Gjutgrus|Natursingel)'
 and concat_ws(' ',f.original->>'Artikelnamn',f.description) !~* 'transport|uttaget.*kund')
 or(r.rule_key='external_ifa_tipping' and f.original->>'Artikelnummer'='3-29' and coalesce(f.original->>'Artikelnamn',f.description,'') ilike 'Tippavgift IFA-Schakt%'))
 ), updated as(
 update private.hub_kpi_prepared_facts f set unit_id=c.target_unit_id,unit_name=c.target_name,vehicle=null,project=c.target_project,
 business_group=c.target_group,category=c.target_category,
 original=f.original||jsonb_build_object('_humla_vehicle_component_correction',jsonb_build_object('rule',c.rule_key,'old_unit_id',c.old_unit,'old_unit_name',c.old_name,'old_vehicle',c.old_vehicle,'old_project',c.old_project,'old_category',c.old_category,'target_unit_id',c.target_unit_id,'actor',auth.uid(),'corrected_at',now())),
 classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('vehicle_component_rule',c.rule_key),
 display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_vehicle_component_correction',jsonb_build_object('rule',c.rule_key,'old_unit_id',c.old_unit,'target_unit_id',c.target_unit_id))
 from candidates c where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=c.fact_id returning f.*
 ), synced as(
 update private.hub_kpi_prepared_display_facts d set unit_id=u.unit_id,unit_name=u.unit_name,vehicle=u.vehicle,project=u.project,
 business_group=u.business_group,category=u.category,original=u.display_original
 from updated u where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=u.fact_id returning d.fact_id
 )
 select count(*) into changed from updated;
 select jsonb_build_object('rows',count(*),'revenue',sum(amount)filter(where kind='revenue'),'cost',sum(amount)filter(where kind='cost'))
 into after_money from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 if before_money is distinct from after_money then raise exception 'Component correction changed financial totals';end if;
 return jsonb_build_object('changed_rows',changed,'financial_totals_unchanged',true);
end $fn$;
revoke all on function private.hub_detach_vehicle_nontransport_v1(uuid,uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.hub_kpi_separate_material_v1(p_tenant uuid, p_generation uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare cfg record; batch record; f record; prices jsonb; evidence jsonb; part numeric;
 bundled boolean; carrier text; carrier_unit uuid; carrier_name text; allocation jsonb;
 before_revenue numeric; before_cost numeric; after_revenue numeric; after_cost numeric;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then
 raise exception 'KPI management required' using errcode='42501'; end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant) then
 raise exception 'Report generation tenant mismatch';end if;
 select s.*,u.name,u.projects[1] material_project into cfg from private.hub_kpi_material_separation_settings s
 join public.kpi_units u on u.id=s.material_unit_id and u.tenant_id=s.tenant_id and u.enabled and cardinality(u.projects)=1 and u.unit_type='project'
 where s.tenant_id=p_tenant and s.enabled;
 if not found then return;end if;
 -- Never apply twice to a derived generation.
 if exists(select 1 from private.hub_kpi_prepared_facts where generation_id=p_generation and original?'_humla_material_separation') then
 raise exception 'Material separation already applied';end if;
 select coalesce(sum(amount)filter(where kind='revenue'),0),coalesce(sum(amount)filter(where kind='cost'),0)
 into before_revenue,before_cost from private.hub_kpi_prepared_facts where generation_id=p_generation;


 with destinations as (
 select t.fact_id,case when count(distinct u.id)=1 then (array_agg(distinct u.id))[1] end id,
 case when count(distinct u.id)=1 then max(u.name) end name
 from private.hub_kpi_prepared_facts t join public.kpi_units u
 on u.tenant_id=p_tenant and u.enabled and u.unit_type='project' and t.project=any(u.projects)
 and u.valid_from<=t.occurred_on and (u.valid_to is null or u.valid_to>=t.occurred_on)
 where t.generation_id=p_generation and t.occurred_on>=cfg.valid_from and t.category='tipp_deponi'
 and (t.unit_id is null or t.vehicle is not null)
 group by t.fact_id
 )
 update private.hub_kpi_prepared_facts t set unit_id=d.id,unit_name=d.name,vehicle=null,
 original=t.original||jsonb_build_object('_humla_material_separation',jsonb_build_object(
 'method','tipping_destination_project','original_fact_id',t.fact_id,'original_amount',t.amount,
 'original_vehicle',t.vehicle,'original_unit_id',t.unit_id,'original_project',t.project))
 from destinations d where t.generation_id=p_generation and t.fact_id=d.fact_id and d.id is not null;
  -- Only detach material purchases from vehicle carriers. Existing storage and
 -- Trading assignments, and all tipping assignments, remain intact.
 update private.hub_kpi_prepared_facts f set
 unit_id=cfg.material_unit_id,unit_name=cfg.name,vehicle=null,project=cfg.material_project,business_group='Grusmaterial',
 original=f.original||jsonb_build_object('_humla_material_separation',jsonb_build_object(
 'method','next_material_cost','original_fact_id',f.fact_id,'original_amount',f.amount,
 'original_vehicle',f.vehicle,'original_unit_id',f.unit_id,'original_project',f.project))
 where f.generation_id=p_generation and f.occurred_on>=cfg.valid_from and f.kind='cost' and f.category='material'
 and (f.vehicle is not null or exists(select 1 from public.kpi_units u where u.id=f.unit_id and u.tenant_id=p_tenant and u.unit_type in('vehicle','compound')));

 for batch in
 select array_agg(id) ids from (
 select distinct r.id,(row_number()over(order by r.id)-1)/1000 bucket
 from public.kpi_import_rows r
 where r.tenant_id=p_tenant and exists(
 select 1 from private.hub_kpi_prepared_facts f where f.generation_id=p_generation
 and f.occurred_on>=cfg.valid_from and f.source='Workify' and f.kind='revenue' and f.fact_id=r.id::text
 and coalesce(f.original->>'Artikelnamn',f.description,'') ~* 'förstärkningslager|bärlager|slitlager|makadam|stenmjöl|råberg|dräneringsgrus|matjord|fyllnadsmaterial')
 )q group by bucket
 loop
 prices:=private.hub_kpi_material_purchase_costs_v1(p_tenant,batch.ids);
 for f in select f.*,coalesce(a.article_name,a.source_rows#>>'{0,values,Namn}','') rule_name,
 r.vehicle_registration source_registration
 from private.hub_kpi_prepared_facts f
 join public.kpi_import_rows r on r.id::text=f.fact_id and r.tenant_id=p_tenant
 left join lateral(select a.* from public.kpi_workify_article_rules a
 where a.tenant_id=p_tenant and a.article_number=f.original->>'Artikelnummer' and a.enabled
 and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
 order by a.valid_from desc,a.id limit 1)a on true
 where f.generation_id=p_generation and f.fact_id=any(array(select x::text from unnest(batch.ids)x))
 loop
 bundled:=concat_ws(' ',f.rule_name,f.original->>'Artikelnamn',f.description) ~* 'in[ck]l?[.]?[[:space:]]*transport';
 if not bundled and f.category<>'material' then continue;end if;
 evidence:=prices->f.fact_id;
 part:=case when bundled then (evidence->>'amount')::numeric else f.amount end;
 if bundled and (part is null or (part<>0 and sign(part)<>sign(f.amount)) or (evidence->>'status'='average_estimate' and coalesce((evidence->>'price_sample_count')::int,0)<>3)) then
 update private.hub_kpi_prepared_facts set original=original||jsonb_build_object('_humla_material_separation',
 jsonb_build_object('status','needs_review','reason',case when evidence->>'status'='average_estimate' and coalesce((evidence->>'price_sample_count')::int,0)<>3 then 'insufficient_quarry_prices' else coalesce(evidence->>'status','missing_purchase_price') end,'purchase',evidence))
 where generation_id=p_generation and fact_id=f.fact_id;
 continue;
 end if;
 carrier:=coalesce(nullif(f.vehicle,''),nullif(upper(trim(f.source_registration)),''));
 carrier_unit:=f.unit_id;carrier_name:=f.unit_name;
 -- A project-targeted bundled article still has a transport remainder on its
 -- resolved vehicle. Without that identity, preserve the source allocation.
 if bundled and f.vehicle is null and carrier is not null then
 select case when count(distinct u.id)=1 then (array_agg(distinct u.id))[1] end,
 case when count(distinct u.id)=1 then max(u.name) end into carrier_unit,carrier_name
 from public.kpi_units u where u.tenant_id=p_tenant and u.enabled
 and (exists(select 1 from public.kpi_unit_periods p where p.tenant_id=p_tenant and p.unit_id=u.id
 and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)
 and carrier in(select jsonb_array_elements_text(coalesce(p.payload->'registrations',to_jsonb(u.registrations)))))
 or (not exists(select 1 from public.kpi_unit_periods p where p.unit_id=u.id and p.tenant_id=p_tenant)
 and carrier=any(u.registrations) and u.valid_from<=f.occurred_on and (u.valid_to is null or u.valid_to>=f.occurred_on)));
 end if;
 allocation:=jsonb_build_object('method',case when bundled then 'purchase_price_transport_remainder' else 'material_article' end,
 'original_fact_id',f.fact_id,'original_amount',f.amount,'original_vehicle',f.vehicle,
 'original_unit_id',f.unit_id,'original_project',f.project,'purchase',evidence,
 'estimated',coalesce(evidence->>'status','') in('average_estimate','preliminary_source'));
 if bundled then
 -- Clone only revenue. Preserve date, cost centre, source and original evidence.
 insert into private.hub_kpi_prepared_facts
 select (jsonb_populate_record(null::private.hub_kpi_prepared_facts,to_jsonb(f)-'rule_name'-'source_registration'||
 jsonb_build_object('fact_id',f.fact_id||':material','amount',part,'category','material',
 'unit_id',case when f.vehicle is null and f.unit_id is not null then f.unit_id else cfg.material_unit_id end,
 'unit_name',case when f.vehicle is null and f.unit_id is not null then f.unit_name else cfg.name end,
 'vehicle',null,'project',case when f.vehicle is null and f.unit_id is not null then f.project else cfg.material_project end,
 'business_group',case when f.vehicle is null and f.unit_id is not null then f.business_group else 'Grusmaterial' end,
 'original',f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','material'))))).*;
 update private.hub_kpi_prepared_facts set amount=f.amount-part,category='transport',
 vehicle=carrier,unit_id=carrier_unit,unit_name=carrier_name,
 project=case when f.vehicle is null and carrier is not null then null else f.project end,
 original=f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','transport'))
 where generation_id=p_generation and fact_id=f.fact_id;
 elsif f.vehicle is not null then
 update private.hub_kpi_prepared_facts set vehicle=null,unit_id=cfg.material_unit_id,unit_name=cfg.name,
 project=cfg.material_project,business_group='Grusmaterial',
 original=f.original||jsonb_build_object('_humla_material_separation',allocation||jsonb_build_object('component','material'))
 where generation_id=p_generation and fact_id=f.fact_id;
 end if;
 end loop;
 end loop;
 perform private.hub_detach_vehicle_nontransport_v1(p_tenant,p_generation);
 select coalesce(sum(amount)filter(where kind='revenue'),0),coalesce(sum(amount)filter(where kind='cost'),0)
 into after_revenue,after_cost from private.hub_kpi_prepared_facts where generation_id=p_generation;
 if before_revenue<>after_revenue or before_cost<>after_cost then raise exception 'Material separation total mismatch';end if;
end $function$
