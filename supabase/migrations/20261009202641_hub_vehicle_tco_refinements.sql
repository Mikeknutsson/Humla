create or replace function private.hub_asset_tco_v1(p_tenant_id uuid,p_as_of date,p_asset uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' set statement_timeout='15s' as $$
declare answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'fleet.read') then raise exception 'Fordonsbehörighet saknas' using errcode='42501';end if;
 if p_as_of is null or p_as_of>current_date then raise exception 'Välj ett datum senast idag';end if;
 with assets as materialized (
  select o.id,o.data,o.status from public.hub_objects o where o.tenant_id=p_tenant_id and o.object_type='Vehicle'
   and public.hub_resolve_canonical_object_v1(p_tenant_id,o.id)=o.id and (p_asset is null or o.id=p_asset)
 ), identities as materialized (
  select distinct k.identity_value registration,k.object_id from public.hub_identity_keys k where k.tenant_id=p_tenant_id and k.confidence=1
   and k.identity_type in ('registration_number','vehicle_registration')
   and exists(select 1 from assets a where a.id=k.object_id)
   and not exists(select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id and other.confidence=1
     and other.identity_type in ('registration_number','vehicle_registration') and other.identity_value=k.identity_value
     and public.hub_resolve_canonical_object_v1(p_tenant_id,other.object_id)<>k.object_id)
 ), costs as materialized (
  select i.object_id,count(*) cost_rows,round(sum(f.amount) filter(where (f.category in ('fuel','service_repair') or (f.category='fixed' and coalesce(f.description,'') !~* '(leasing|amortering|avskriv)'))),2) operating_cost,
   round(sum(f.amount) filter(where f.category='fuel'),2) fuel,round(sum(f.amount) filter(where f.category='service_repair'),2) service_repair,
   round(sum(f.amount) filter(where f.category='fixed' and coalesce(f.description,'') !~* '(leasing|amortering|avskriv)'),2) fixed,
   count(*) filter(where (f.category not in ('fuel','service_repair','fixed','personnel','depreciation') or (f.category='fixed' and coalesce(f.description,'') ~* '(leasing|amortering|avskriv)'))) pending_cost_rows,
   min(f.occurred_on) first_cost_date,max(f.occurred_on) last_cost_date,
   coalesce(jsonb_agg(jsonb_build_object('id',f.fact_id,'date',f.occurred_on,'amount',f.amount,'category',f.category,'source',f.source,'description',f.description,'account',f.account)) filter(where p_asset is not null and (f.category in ('fuel','service_repair') or (f.category='fixed' and coalesce(f.description,'') !~* '(leasing|amortering|avskriv)'))),'[]'::jsonb) evidence
  from private.hub_kpi_prepared_facts f join private.hub_kpi_report_state state on state.tenant_id=p_tenant_id and state.active_generation=f.generation_id
  join identities i on i.registration=f.vehicle join private.hub_asset_ownership own on own.tenant_id=p_tenant_id and own.asset_id=i.object_id
  where f.tenant_id=p_tenant_id and f.kind='cost' and f.category<>'personnel'
    and f.occurred_on between own.purchase_date and p_as_of group by i.object_id
 ), latest_meters as materialized (
  select public.hub_resolve_canonical_object_v1(p_tenant_id,m.vehicle_id) asset_id,m.reading_type,m.reading_value,m.recorded_at,m.id
  from (select distinct on (vehicle_id,reading_type) vehicle_id,reading_type,reading_value,recorded_at,id
   from public.hub_vehicle_meter_readings where tenant_id=p_tenant_id and recorded_at<((p_as_of+1)::timestamp at time zone 'Europe/Stockholm')
   order by vehicle_id,reading_type,recorded_at desc,id desc)m
 ), base as materialized (
  select a.*,to_jsonb(own)-'tenant_id'-'updated_by' ownership,own.purchase_date,own.purchase_cost,own.residual_value,own.holding_months,own.purchase_meter,own.meter_type,own.price_basis,own.model_year,own.variant,
    meters.reading_value current_meter,meters.recorded_at meter_date,
    costs.operating_cost,costs.fuel,costs.service_repair,costs.fixed,costs.cost_rows,costs.pending_cost_rows,costs.first_cost_date,costs.last_cost_date,costs.evidence,
    case when p_as_of>=own.purchase_date then greatest(own.residual_value,own.purchase_cost-(own.purchase_cost-own.residual_value)*least(1::numeric,(p_as_of-own.purchase_date)::numeric/nullif((own.purchase_date+make_interval(months=>own.holding_months))::date-own.purchase_date,0))) end planned_value,
    valuation.amount market_value,valuation.valued_on market_date,valuation.source valuation_source,
    valuation.price_basis market_basis
  from assets a left join private.hub_asset_ownership own on own.tenant_id=p_tenant_id and own.asset_id=a.id
  left join lateral(select m.reading_value,m.recorded_at from latest_meters m
    where m.asset_id=a.id
    and m.reading_type=coalesce(own.meter_type,case when a.data->>'odometer_type'='K_OT_HOURS' then 'engine_hours' else 'odometer_km' end)
    and m.recorded_at<((p_as_of+1)::timestamp at time zone 'Europe/Stockholm') order by m.recorded_at desc,m.id desc limit 1)meters on true
  left join costs on costs.object_id=a.id
  left join lateral(select v.* from private.hub_asset_valuations v where v.tenant_id=p_tenant_id and v.asset_id=a.id and v.valued_on<=p_as_of order by v.valued_on desc,v.created_at desc limit 1)valuation on true
 ), candidates as materialized (
  select c.*,case when c.price_type='sold' then 'sold' else 'asking' end basis from private.hub_asset_comparables c join base b on b.id=c.asset_id
  where c.tenant_id=p_tenant_id and c.comparable_confirmed and c.price_basis=b.price_basis and c.observed_on between p_as_of-180 and p_as_of
   and abs(c.model_year-b.model_year)<=2 and (c.price_type='asking' or c.sale_confirmed)
   and (b.meter_type='none' or (b.current_meter is not null and c.meter is not null and abs(c.meter-b.current_meter)<=greatest(case when b.meter_type='engine_hours' then 1000 else 20000 end,b.current_meter*0.3)))
 ), comparison as (
  select asset_id,basis,count(*) n,count(distinct source) sources,round(avg(price),2) mean,
   percentile_cont(0.5) within group(order by price)::numeric median,min(price) low,max(price) high,
   jsonb_agg(id) ids from candidates group by asset_id,basis
 ), rows as (
  select b.*,sold.n sold_count,asking.n asking_count,to_jsonb(sold)-'asset_id' sold_stats,to_jsonb(asking)-'asset_id' asking_stats,
   case when sold.n>=3 then to_jsonb(sold)-'asset_id' when asking.n>=3 then to_jsonb(asking)-'asset_id' end estimate,
   case when b.purchase_meter is not null and b.current_meter>=b.purchase_meter and b.meter_date>=(b.purchase_date::timestamp at time zone 'Europe/Stockholm') then b.current_meter-b.purchase_meter end usage
  from base b left join comparison sold on sold.asset_id=b.id and sold.basis='sold' left join comparison asking on asking.asset_id=b.id and asking.basis='asking'
 )
 select jsonb_build_object('as_of',p_as_of,'can_manage',public.hub_has_permission(p_tenant_id,'fleet.manage'),
 'sync_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant_id),
 'assets',coalesce(jsonb_agg(jsonb_build_object('id',id,'registration',data->>'registration_number','make',data->>'make','model',data->>'model',
 'description',data->>'description','vehicle_type',data->>'vehicle_type','department',data#>>'{department,title}','source_meter_type',data->>'odometer_type','status',status,
 'ownership',ownership,'current_meter',current_meter,'meter_date',meter_date,'planned_value',round(planned_value,2),
 'monthly_depreciation',round((purchase_cost-residual_value)/holding_months,2),'depreciation',round(purchase_cost-planned_value,2),
 'market_value',market_value,'market_date',market_date,'market_basis',market_basis,'valuation_source',valuation_source,
 'operating_cost',operating_cost,'fuel',fuel,'service_repair',service_repair,'fixed',fixed,'cost_rows',cost_rows,'pending_cost_rows',pending_cost_rows,
 'first_cost_date',first_cost_date,'last_cost_date',last_cost_date,'usage',usage,
 -- Imported KPI amounts are net. Gross purchase-cost profiles remain uncombined.
 'tco',case when price_basis='net' then round(purchase_cost-planned_value+operating_cost,2) end,
 'tco_per_unit',case when price_basis='net' then round((purchase_cost-planned_value+operating_cost)/nullif(case when meter_type='odometer_km' then usage/10 else usage end,0),2) end,
 'estimate',estimate,'sold_stats',sold_stats,'asking_stats',asking_stats,'sold_count',coalesce(sold_count,0),'asking_count',coalesce(asking_count,0),'cost_evidence',coalesce(evidence,'[]'::jsonb)
 ) order by data->>'registration_number'),'[]'::jsonb),
 'comparables',case when p_asset is not null then coalesce((select jsonb_agg(to_jsonb(c)-'tenant_id'-'created_by' order by observed_on desc) from private.hub_asset_comparables c where c.tenant_id=p_tenant_id and c.asset_id=p_asset),'[]') else '[]'::jsonb end,
 'valuations',case when p_asset is not null then coalesce((select jsonb_agg(to_jsonb(v)-'tenant_id'-'created_by' order by valued_on desc,created_at desc) from private.hub_asset_valuations v where v.tenant_id=p_tenant_id and v.asset_id=p_asset),'[]') else '[]'::jsonb end)
 into answer from rows;
 return answer;
end $$;

create or replace function private.hub_asset_tco_save_v1(p_tenant_id uuid,p_asset uuid,p_action text,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare canonical uuid; own private.hub_asset_ownership; report jsonb; asset jsonb; estimate jsonb; result_id uuid; url text; identity text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'fleet.manage') or not public.hub_has_permission(p_tenant_id,'fleet.read') then raise exception 'Fordonsadministratör krävs' using errcode='42501';end if;
 canonical:=public.hub_resolve_canonical_object_v1(p_tenant_id,p_asset);
 if canonical is null or canonical<>p_asset or not exists(select 1 from public.hub_objects where tenant_id=p_tenant_id and id=canonical and object_type='Vehicle') then raise exception 'Fordonet saknar verifierat Humla-ID';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||canonical::text,0));
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'Ogiltigt underlag';end if;
 if p_action='ownership' then
  if (p_data->>'purchase_date')::date>current_date then raise exception 'Inköpsdatum får inte ligga i framtiden';end if;
  insert into private.hub_asset_ownership(tenant_id,asset_id,asset_class,purchase_date,purchase_cost,residual_value,holding_months,purchase_meter,meter_type,model_year,variant,price_basis,notes,updated_by)
  values(p_tenant_id,canonical,p_data->>'asset_class',(p_data->>'purchase_date')::date,(p_data->>'purchase_cost')::numeric,(p_data->>'residual_value')::numeric,(p_data->>'holding_months')::integer,nullif(p_data->>'purchase_meter','')::numeric,p_data->>'meter_type',nullif(p_data->>'model_year','')::integer,left(coalesce(p_data->>'variant',''),300),p_data->>'price_basis',coalesce(p_data->>'notes',''),auth.uid())
  on conflict(tenant_id,asset_id) do update set asset_class=excluded.asset_class,purchase_date=excluded.purchase_date,purchase_cost=excluded.purchase_cost,residual_value=excluded.residual_value,holding_months=excluded.holding_months,purchase_meter=excluded.purchase_meter,meter_type=excluded.meter_type,model_year=excluded.model_year,variant=excluded.variant,price_basis=excluded.price_basis,notes=excluded.notes,revision=hub_asset_ownership.revision+1,updated_by=auth.uid(),updated_at=now();
  insert into private.hub_asset_ownership_history(tenant_id,asset_id,snapshot,actor) select p_tenant_id,canonical,to_jsonb(o),auth.uid() from private.hub_asset_ownership o where tenant_id=p_tenant_id and asset_id=canonical;
 elsif p_action='comparable' then
  url:=regexp_replace(trim(p_data->>'url'),'[?#].*$','');identity:=lower(coalesce(nullif(trim(p_data->>'listing_identity'),''),url));
  if (p_data->>'observed_on')::date>current_date then raise exception 'Prisdatum får inte ligga i framtiden';end if;
  insert into private.hub_asset_comparables(tenant_id,asset_id,source,url,listing_identity,title,price,price_basis,price_type,observed_on,model_year,meter,comparable_confirmed,sale_confirmed,notes,created_by)
  values(p_tenant_id,canonical,p_data->>'source',url,identity,p_data->>'title',(p_data->>'price')::numeric,p_data->>'price_basis',p_data->>'price_type',(p_data->>'observed_on')::date,(p_data->>'model_year')::integer,nullif(p_data->>'meter','')::numeric,coalesce((p_data->>'comparable_confirmed')::boolean,false),coalesce((p_data->>'sale_confirmed')::boolean,false),coalesce(p_data->>'notes',''),auth.uid());
 elsif p_action='remove_comparable' then
  delete from private.hub_asset_comparables where tenant_id=p_tenant_id and asset_id=canonical and id=(p_data->>'id')::uuid;
 elsif p_action in ('valuation','accept_estimate') then
  select * into own from private.hub_asset_ownership where tenant_id=p_tenant_id and asset_id=canonical;
  if own.asset_id is null then raise exception 'Spara inköpsuppgifterna först';end if;
  report:=private.hub_asset_tco_v1(p_tenant_id,current_date,canonical);asset:=report#>'{assets,0}';estimate:=asset->'estimate';
  if p_action='accept_estimate' and (estimate is null or estimate='null'::jsonb) then raise exception 'Minst tre jämförbara priser krävs';end if;
  if (coalesce(nullif(p_data->>'valued_on',''),current_date::text))::date>current_date then raise exception 'Värderingsdatum får inte ligga i framtiden';end if;
  insert into private.hub_asset_valuations(tenant_id,asset_id,valued_on,amount,price_basis,source,notes,meter,meter_recorded_at,method,evidence,created_by)
  values(p_tenant_id,canonical,case when p_action='accept_estimate' then current_date else (p_data->>'valued_on')::date end,
  case when p_action='accept_estimate' then (estimate->>'median')::numeric else (p_data->>'amount')::numeric end,
  own.price_basis,case when p_action='accept_estimate' then 'Jämförelsemotor' else p_data->>'source' end,coalesce(p_data->>'notes',''),
  (asset->>'current_meter')::numeric,(asset->>'meter_date')::timestamptz,
  case when p_action='accept_estimate' then 'comparable_median_v1' else 'manual' end,
  jsonb_build_object('estimate',case when p_action='accept_estimate' then estimate end,'ownership_revision',own.revision,'comparables',case when p_action='accept_estimate' then (select jsonb_agg(to_jsonb(c)-'created_by') from private.hub_asset_comparables c where c.tenant_id=p_tenant_id and c.asset_id=canonical and c.id::text in (select jsonb_array_elements_text(estimate->'ids'))) end),auth.uid()) returning id into result_id;
 else raise exception 'Okänd åtgärd';end if;
 return jsonb_build_object('saved',true,'id',result_id);
end $$;
revoke all on function private.hub_asset_tco_v1(uuid,date,uuid),private.hub_asset_tco_save_v1(uuid,uuid,text,jsonb) from public,anon;
grant execute on function private.hub_asset_tco_v1(uuid,date,uuid),private.hub_asset_tco_save_v1(uuid,uuid,text,jsonb) to authenticated;
create or replace function public.hub_asset_tco_v1(p_tenant_id uuid,p_as_of date,p_asset uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$ select private.hub_asset_tco_v1(p_tenant_id,p_as_of,p_asset) $$;
create or replace function public.hub_asset_tco_save_v1(p_tenant_id uuid,p_asset uuid,p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.hub_asset_tco_save_v1(p_tenant_id,p_asset,p_action,p_data) $$;
revoke all on function public.hub_asset_tco_v1(uuid,date,uuid),public.hub_asset_tco_save_v1(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.hub_asset_tco_v1(uuid,date,uuid),public.hub_asset_tco_save_v1(uuid,uuid,text,jsonb) to authenticated;


alter table private.hub_asset_ownership add constraint ownership_finite check(purchase_cost::text<>'NaN' and residual_value::text<>'NaN' and coalesce(purchase_meter::text,'')<>'NaN');
alter table private.hub_asset_comparables add constraint comparable_finite check(price::text<>'NaN' and coalesce(meter::text,'')<>'NaN');
alter table private.hub_asset_valuations add constraint valuation_finite check(amount::text<>'NaN');
