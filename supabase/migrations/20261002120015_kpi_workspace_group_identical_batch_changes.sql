create or replace function public.hub_kpi_match_changes_v1(p_tenant_id uuid,p_changes jsonb,p_from date,p_to date,p_reason text,p_preview boolean default true)
returns jsonb language plpgsql security invoker set search_path='' set statement_timeout='60s' as $fn$
declare change jsonb; output jsonb; before_values jsonb; after_values jsonb; result jsonb; saved integer:=0;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.manage') then raise exception 'KPI-administratör krävs' using errcode='42501';end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes) not between 1 and 100 or p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Kontrollera urval och datum';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text||':kpi-matching',0));
 if p_preview then
  with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)), cc as(select cost_center,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by cost_center), units as(select coalesce(unit_name,'Ej fördelat') name,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by 1)
  select jsonb_build_object('cost_centers',(select jsonb_agg(to_jsonb(c)) from cc c),'units',(select jsonb_agg(to_jsonb(u)) from units u),'cost',(select coalesce(sum(amount)filter(where kind='cost'),0)from facts),'revenue',(select coalesce(sum(amount)filter(where kind='revenue'),0)from facts)) into before_values;
 end if;
 begin
  for change in select jsonb_build_object('items',jsonb_agg(value->'item'),'targets',value->'targets','valid_from',value->>'valid_from','valid_to',nullif(value->>'valid_to','')) from jsonb_array_elements(p_changes) group by value->'targets',value->>'valid_from',nullif(value->>'valid_to','') loop
   result:=public.hub_kpi_match_save_many_v1(p_tenant_id,change->'items',change->'targets',(change->>'valid_from')::date,nullif(change->>'valid_to','')::date,p_reason);
   saved:=saved+(result->>'saved')::int;
  end loop;
  if p_preview then
   with facts as materialized(select * from private.hub_kpi_classified_facts_v1(p_tenant_id,p_from,p_to)), cc as(select cost_center,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by cost_center), units as(select coalesce(unit_name,'Ej fördelat') name,sum(amount) filter(where kind='cost') cost,sum(amount) filter(where kind='revenue') revenue from facts group by 1)
   select jsonb_build_object('cost_centers',(select jsonb_agg(to_jsonb(c)) from cc c),'units',(select jsonb_agg(to_jsonb(u)) from units u),'cost',(select coalesce(sum(amount)filter(where kind='cost'),0)from facts),'revenue',(select coalesce(sum(amount)filter(where kind='revenue'),0)from facts)) into after_values;
   with movements as (
 select 'cost_center' dimension,coalesce(b->>'cost_center',a->>'cost_center') name,coalesce((b->>'cost')::numeric,0) before_cost,coalesce((a->>'cost')::numeric,0) after_cost,coalesce((b->>'revenue')::numeric,0) before_revenue,coalesce((a->>'revenue')::numeric,0) after_revenue
 from jsonb_array_elements(coalesce(before_values->'cost_centers','[]')) b full join jsonb_array_elements(coalesce(after_values->'cost_centers','[]')) a on b->>'cost_center'=a->>'cost_center'
 union all
 select 'unit',coalesce(b->>'name',a->>'name'),coalesce((b->>'cost')::numeric,0),coalesce((a->>'cost')::numeric,0),coalesce((b->>'revenue')::numeric,0),coalesce((a->>'revenue')::numeric,0)
 from jsonb_array_elements(coalesce(before_values->'units','[]')) b full join jsonb_array_elements(coalesce(after_values->'units','[]')) a on b->>'name'=a->>'name'
 )
 select jsonb_build_object('before',before_values,'after',after_values,'saved',saved,'preview',true,'movements',coalesce(jsonb_agg(to_jsonb(m))filter(where before_cost<>after_cost or before_revenue<>after_revenue),'[]')) into output from movements m;
   raise exception using errcode='PZ001',message='preview_rollback';
  end if;
 exception when sqlstate 'PZ001' then
  if not p_preview then raise;end if;
 end;
 return coalesce(output,jsonb_build_object('saved',saved,'preview',false));
end $fn$;
revoke all on function public.hub_kpi_match_changes_v1(uuid,jsonb,date,date,text,boolean) from public,anon;
grant execute on function public.hub_kpi_match_changes_v1(uuid,jsonb,date,date,text,boolean) to authenticated;
