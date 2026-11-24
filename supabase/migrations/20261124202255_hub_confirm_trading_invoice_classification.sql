CREATE OR REPLACE FUNCTION private.hub_route_tipping_revenue_v1(p_tenant uuid, p_generation uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
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
   f.amount,f.original as evidence,
   exists (select 1 from public.hub_tenants t where t.id=f.tenant_id and t.slug='elleholms') as elleholms,
   u.data->>'unit_type' as current_unit_type
  from private.hub_kpi_prepared_facts f
  join settings on f.occurred_on>=settings.valid_from
  left join public.hub_objects u on u.tenant_id=f.tenant_id and u.id=f.unit_id
  where f.tenant_id=p_tenant and f.generation_id=p_generation
   and ((f.source='Workify' and f.kind='revenue')
     or (f.project='5100' and f.cost_center='30' and f.kind='cost' and f.category in ('tipp_deponi','material'))
     or (f.source='NEXT' and f.kind='revenue' and f.project in ('4004','5100')
       and f.original->>'Faktura nr'='37776'))
 ), classified as (
  select r.*,
   case
    -- Owner-confirmed exceptions are bound to source documents and row evidence.
    when r.elleholms and r.source='NEXT' and r.kind='cost' and r.project='5100'
      and r.evidence->>'Leverantör'='Swerock AB' and r.evidence->>'Verifikation nr'='16D2079'
      and r.evidence->>'Verifikationstext'='Levfakt Swerock AB (73475)'
      and r.occurred_on=date '2026-11-10' and r.amount=562317.62 then 'confirmed_blue_concrete_cost'
    when r.kind='cost' and r.category='tipp_deponi' then 'project_cost'
    when r.elleholms and r.kind='revenue' and r.project in ('4004','5100')
      and r.occurred_on=date '2026-09-15' and r.amount=20940
      and (
       (r.source='NEXT' and r.evidence->>'Faktura nr'='37776'
         and lower(btrim(r.evidence->>'Verifikationstext'))='försäljning salt')
       or (r.source='Workify' and r.evidence->>'Externt fakturanr'='37776'
         and lower(btrim(r.evidence->>'Fakturarubrik'))='försäljning salt')
      ) then 'confirmed_salt_sale'
    when r.elleholms and r.source='Workify' and r.kind='revenue' and r.project in ('4004','5100')
      and r.order_no='46017' and r.code='F13' and lower(r.article)='saltblandad 2-5'
      and r.evidence->>'Kundnamn'='Södra Skogsägarna ekonomisk förening'
      and r.occurred_on=date '2026-11-20' and r.amount=16450 then 'confirmed_salt_sale'
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
   case when r.route in ('gravel_sale','trading_sale','confirmed_salt_sale') or (r.route='project_cost' and r.account='4022') then 'material'
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
    'old_group',c.business_group,'old_cost_center',c.cost_center,'old_category',c.category,
    'evidence',case c.route when 'confirmed_blue_concrete_cost' then 'Swerock 73475 / Workify 45779, owner confirmed'
     when 'confirmed_salt_sale' then 'Invoice 37776 or Workify 46017 F13, owner confirmed' end)),
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

CREATE OR REPLACE FUNCTION private.hub_transport_leader_facts_v2(p_tenant uuid, p_from date, p_to date, p_user uuid)
 RETURNS SETOF private.hub_kpi_prepared_display_facts
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare caller uuid:=auth.uid();owner_access boolean;generation uuid;authorized_centers text[]; combined_transport boolean:=coalesce(p_user='00000000-0000-0000-0000-000000000030'::uuid,false);
begin
 if caller is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid scope or period' using errcode='22023';end if;
 select m.role='owner' into owner_access from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=caller and m.status='active';
 if owner_access is null or (p_user is not null and p_user<>caller and not owner_access) then raise exception 'Access denied' using errcode='42501';end if;
 if p_user is not null and not combined_transport and not exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active') then raise exception 'Access denied' using errcode='42501';end if;
 select s.active_generation into generation from private.hub_kpi_report_state s where s.tenant_id=p_tenant;
 if generation is null then raise exception 'Published report unavailable';end if;
 select p.cost_centers into authorized_centers from private.hub_foreman_access_plans p where p.tenant_id=p_tenant and p.auth_user_id=coalesce(p_user,caller) and p.status='active';
 return query
 with transport_profiles as materialized (
  select m.user_id,p.cost_centers
  from public.hub_tenant_members m
  left join private.hub_foreman_access_plans p on p.tenant_id=m.tenant_id and p.auth_user_id=m.user_id and p.status='active'
  where combined_transport and m.tenant_id=p_tenant and m.status='active'
   and trim(m.display_name) ~* '^(marcus|ola|pierre)([[:space:]]|$)'
 ), recurring as materialized(
  select f as fact,coalesce(b.original,f.original) evidence
  from private.hub_kpi_prepared_display_facts f
  left join private.hub_kpi_prepared_facts b on b.tenant_id=f.tenant_id and b.generation_id=f.generation_id and b.fact_id=f.fact_id
   and f.source='Avskrivningsregister'
  where f.tenant_id=p_tenant and f.generation_id=generation
   and f.kind='cost' and (f.source='Avskrivningsregister' or (f.source='Preliminär arbetskostnad' and f.original?'_humla_provisional_cost'))
   and f.occurred_on between date_trunc('month',p_from)::date and (date_trunc('month',p_to)+interval '1 month -1 day')::date
 ), scoped as(
  select f.* from private.hub_kpi_prepared_display_facts f
  where f.tenant_id=p_tenant and f.generation_id=generation and f.occurred_on between p_from and p_to
   and not coalesce(f.kind='cost' and (f.source='Avskrivningsregister' or (f.source='Preliminär arbetskostnad' and f.original?'_humla_provisional_cost')),false)
  union all
  select f.* from recurring r cross join lateral private.hub_foreman_recurring_fact_v1(r.fact,r.evidence,p_from,p_to) f
 ),
 -- NEXT's ledger copy of a Workify invoice is counted once when the exact
 -- external invoice number, project, date, and amount agree.
 salt_invoice_copies as materialized (
  select f.fact_id,f.source,f.occurred_on,f.amount,f.unit_id,f.cost_center,f.project,
   b.original->>'Externt fakturanr' workify_invoice,b.original->>'Faktura nr' ledger_invoice
  from scoped f
  join private.hub_kpi_prepared_facts b on b.tenant_id=f.tenant_id and b.generation_id=f.generation_id and b.fact_id=f.fact_id
  where f.project in ('4004','5100') and f.kind='revenue' and f.source in ('NEXT','Workify')
   and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
   and lower(trim(coalesce(b.original->>'Fakturarubrik',b.original->>'Verifikationstext','')))='försäljning salt'
 ),
 duplicated_salt_ledger as materialized (
  select n.fact_id from salt_invoice_copies n join salt_invoice_copies w
   on w.source='Workify' and n.ledger_invoice=w.workify_invoice
   and n.occurred_on=w.occurred_on and n.amount=w.amount
   and n.unit_id is not distinct from w.unit_id and n.cost_center is not distinct from w.cost_center
   and n.project=w.project
  where n.source='NEXT' and nullif(n.ledger_invoice,'') is not null
  group by n.fact_id having count(*)=1
 )
 select f.generation_id,f.tenant_id,f.fiscal_year,f.fact_id,f.occurred_on,f.kind,f.amount,c.category,f.project,f.vehicle,
 case when extra.include then ('00000000-0000-0000-0000-0000000000'||b.bucket)::uuid else f.unit_id end,
 case when extra.include then case b.bucket when 33 then 'Ej klassificerat – Workify' when 35 then 'Trading Material' else 'Övriga poster' end else f.unit_name end,
 case when extra.include then 'Ej tilldelat – Transport' else f.business_group end,
 f.source,f.cost_center,f.original from scoped f
 left join private.hub_kpi_prepared_facts ledger on f.source='NEXT' and f.kind='cost' and f.project='5100'
  and f.category='tipp_deponi'
  and (f.original#>>'{_humla_tipping_routing,route}') is distinct from 'confirmed_blue_concrete_cost'
  and ledger.tenant_id=f.tenant_id and ledger.generation_id=f.generation_id and ledger.fact_id=f.fact_id
 cross join lateral (select case ledger.original->>'Konto' when '4022' then 'material' when '8422' then 'other' else f.category end category) c
 cross join lateral (
  select combined_transport and owner_access and exists (
   select 1 from transport_profiles p
   where case when p.cost_centers is not null then f.cost_center=any(p.cost_centers) else exists (
    select 1 from public.hub_transport_leader_units a
    where a.tenant_id=p_tenant and a.user_id=p.user_id and a.unit_id=f.unit_id
     and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)
   ) end
  ) as assigned
 ) a
 cross join lateral (
  select case
   -- Use the existing Trading Material card for external tipping and material.
   when f.unit_name='Trading Material' or f.project='5100'
     or (c.category='tipp_deponi' and f.business_group in ('Återvinning','Trading Material')) then 35
   when f.business_group='Ej klassificerat' and f.source='Workify' then 33
   else 34
  end as bucket
 ) b
 cross join lateral (select combined_transport and owner_access and f.cost_center='30' and (b.bucket=35 or not a.assigned) as include) extra
 where not exists(select 1 from duplicated_salt_ledger d where d.fact_id=f.fact_id)
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and (case when combined_transport then owner_access and (a.assigned or f.cost_center='30') else ((owner_access and p_user is null and f.cost_center='30') or (not(owner_access and p_user is null) and (case when authorized_centers is not null then f.cost_center=any(authorized_centers) else exists(
 select 1 from public.hub_transport_leader_units a where a.tenant_id=p_tenant and a.user_id=coalesce(p_user,caller)
 and a.unit_id=f.unit_id and a.valid_from<=f.occurred_on and (a.valid_to is null or a.valid_to>=f.occurred_on)) end))) end);
end $function$;

insert into public.humla_architecture_rules (rule_code,title,rule_text,status,rule_level)
values ('KPI-001','Evidence check before revenue and cost classification','Before classifying revenue or costs, compare the original article or invoice row, source reference, order or invoice number, date, amount and, when available, quantity and unit price. Separate transport, materials and tipping or treatment fees on the same order. A vehicle registration or ledger account is supporting evidence. Match accounting copies by invoice, date and amount so each business event is counted once. Confirm ambiguous ownership or cost splits against source documents or with the responsible user. Preserve the original fact, log the evidence and verify totals and row counts after the change.','ACTIVE','MODULE')
on conflict (rule_code) do nothing;

do $migration$
declare
 report record;
begin
 perform pg_advisory_xact_lock(hashtextextended('hub_kpi_report_worker_v1',0));
 for report in
  select s.tenant_id,s.active_generation from private.hub_kpi_report_state s
  join public.hub_tenants t on t.id=s.tenant_id and t.slug='elleholms'
  where s.active_generation is not null
 loop
  if private.hub_route_tipping_revenue_v1(report.tenant_id,report.active_generation)>0 then
   update private.hub_kpi_report_state set correction_revision=correction_revision+1
   where tenant_id=report.tenant_id;
  end if;
 end loop;
end
$migration$;
