create or replace function private.hub_fleet_compare_rows_v1(p_assets jsonb,p_members jsonb)
returns jsonb language sql immutable set search_path='' as $$
with members as materialized(select a from jsonb_array_elements(p_assets) a where p_members ? (a->>'id')),
metrics as materialized(select a->>'id' id,m.key,m.value from members cross join lateral (values
 ('cost_per_unit',(a->>'cost_per_unit')::numeric),('fuel_per_unit',(a->>'fuel_per_unit')::numeric),
 ('repair_per_unit',(a->>'service_repair')::numeric/nullif(case when a->>'meter_type'='engine_hours' then (a->>'usage')::numeric else (a->>'usage')::numeric/10 end,0))) m(key,value)
 where (a->>'missing_months')::integer=0 and (a->>'usage')::numeric>0 and m.value>=0),
comparisons as(select target.a,mkey.key,m.value,ref.n,ref.median from members target cross join (values('cost_per_unit'),('fuel_per_unit'),('repair_per_unit')) mkey(key)
 left join metrics m on m.id=target.a->>'id' and m.key=mkey.key
 left join lateral(select count(*) n,percentile_cont(0.5) within group(order by x.value)::numeric median from metrics x join members other on other.a->>'id'=x.id
 where x.id<>target.a->>'id' and x.key=mkey.key and other.a->>'meter_type'=target.a->>'meter_type') ref on true),
per_asset as(select a,jsonb_object_agg(coalesce(key,'unavailable'),jsonb_build_object('value',round(value,2),'peers',n,'median',case when n>=3 then round(median,2) end,
 'change_pct',case when n>=3 and median>0 and value is not null then round((value-median)/median*100,1) end,
 'outlier',coalesce(n>=3 and median>0 and value>median*1.3,false))) metrics from comparisons group by a)
select coalesce(jsonb_agg(jsonb_build_object('id',a->>'id','registration',a->>'registration','description',a->>'description','model',a->>'model','meter_type',a->>'meter_type','cost',a->'cost','service_repair',a->'service_repair','usage',a->'usage','metrics',metrics) order by a->>'registration',a->>'id'),'[]'::jsonb) from per_asset
$$;
