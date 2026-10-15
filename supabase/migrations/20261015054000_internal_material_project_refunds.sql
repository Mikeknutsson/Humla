-- Read-only project refund proposal. No ledger entries or financial facts are changed.
create or replace function public.hub_kpi_internal_material_project_refunds_v1(
 p_tenant_id uuid,p_from date,p_to date,p_months integer[] default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare transfers jsonb;transfer_map jsonb;items jsonb:='[]';yr integer;first_year integer;last_year integer;result jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501';end if;
 -- Reuse the existing Hub adapter for canonical, dated receiving-project identity.
 transfers:=public.hub_kpi_internal_transfers_v1(p_tenant_id,p_from,p_to,p_months);
 select coalesce(jsonb_object_agg(r->>'row_id',r),'{}') into transfer_map from jsonb_array_elements(transfers->'rows')r;
 first_year:=extract(year from p_from)::int-case when extract(month from p_from)<9 then 1 else 0 end;
 last_year:=extract(year from p_to)::int-case when extract(month from p_to)<9 then 1 else 0 end;
 for yr in first_year..last_year loop
  items:=items||coalesce(private.hub_kpi_internal_material_margin_v1(p_tenant_id,yr,p_months,
   jsonb_build_object('date_from',p_from,'date_to',p_to))->'details','[]');
 end loop;
 with linked as materialized(
  select d, t.r,
   t.r->>'receiver_center' receiver_center,
   case when t.r->>'receiver_center'='10' then nullif(t.r->>'receiver_id','') end project_id,
   coalesce(o.data->>'display_name',t.r->>'receiver_name') project_name,
   (d->>'billed')::numeric billed,(d->>'purchase_cost')::numeric purchase,
   case when (d->>'bundled')::boolean is not true then (d->>'difference')::numeric end refund
  from jsonb_array_elements(items)d
  cross join lateral(select transfer_map->(d->>'source_row') r)t
  left join public.hub_objects o on o.tenant_id=p_tenant_id and o.id=(t.r->>'receiver_id')::uuid
 ), classified as materialized(
  select *,case when receiver_center='10' and nullif(r->>'project','') is not null then 'project'
   when receiver_center is not null and receiver_center<>'10' then 'other_center'
   else 'unresolved' end allocation from linked
 ), projects as(
  select project_id,r->>'project' project_number,max(project_name) project_name,
   sum(billed) billed,case when count(*)filter(where purchase is null)=0 then sum(purchase) end purchase,
   case when count(*)filter(where refund is null)=0 then sum(refund) end refund,
   count(*) rows,count(*)filter(where d#>>'{evidence,status}' is distinct from 'receipt_price_list') estimated_rows,
   count(*)filter(where refund is null) missing_rows,
   count(*)filter(where nullif(r->>'receiver_rule','') is not null) default_center_rows,
   count(*)filter(where (d->>'bundled')::boolean) bundled_rows,
   jsonb_agg(d||jsonb_build_object('source_center',r->>'source_center','littra',r->>'littra') order by d->>'date',d->>'order_number') details
  from classified where allocation='project' group by project_id,r->>'project'
 ), totals as(
  select sum(billed) billed,case when count(*)filter(where purchase is null)=0 then sum(purchase) end purchase,
   case when count(*)filter(where refund is null)=0 then sum(refund) end refund,count(*) rows
  from classified where allocation='project'
 )select jsonb_build_object('projects',coalesce((select jsonb_agg(to_jsonb(p) order by project_number)from projects p),'[]'),
  'totals',to_jsonb(t),'all_material_billed',coalesce((select sum(billed)from classified),0),
  'unresolved_billed',coalesce((select sum(billed)from classified where allocation='unresolved'),0),
  'unresolved_rows',coalesce((select jsonb_agg(d||jsonb_build_object('project_reference',r->>'project','littra',r->>'littra','receiver_rule',r->>'receiver_rule') order by d->>'date')from classified where allocation='unresolved'),'[]'),
  'other_center_billed',coalesce((select sum(billed)from classified where allocation='other_center'),0),
  'other_center_rows',(select count(*)from classified where allocation='other_center'),
  'basis','Förslag till återföring av materialpåslag till mottagande projekt på KST 10. Fakturerade interna materialrader från samma publicerade underlag och inköpsregel som Översikten. Internpris minus beräknat inköp; transport och tipp återförs inte. Positivt belopp = tillbaka till projektet, negativt = tillkommande kostnad. Standardregel för KST 10 och oidentifierade projektreferenser märks som preliminära och måste verifieras före omföring. Material inklusive transport behöver särpris före återföring. Ingen bokföring, exportstatus eller KPI-summa ändras.')into result from totals t;
 return result;
end $$;
revoke all on function public.hub_kpi_internal_material_project_refunds_v1(uuid,date,date,integer[]) from public,anon;
grant execute on function public.hub_kpi_internal_material_project_refunds_v1(uuid,date,date,integer[]) to authenticated;
