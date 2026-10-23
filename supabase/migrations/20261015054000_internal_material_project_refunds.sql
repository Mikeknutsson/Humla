-- Read-only project refund proposal. No ledger entries or financial facts are changed.
create or replace function public.hub_kpi_internal_material_project_refunds_v1(
 p_tenant_id uuid,p_from date,p_to date,p_months integer[] default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit='off' set plan_cache_mode='force_custom_plan' as $$
declare items jsonb:='[]';yr integer;first_year integer;last_year integer;result jsonb;generation uuid;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then
  raise exception 'KPI access required' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid period';end if;
 if p_months is not null and (cardinality(p_months)=0 or exists(select 1 from unnest(p_months)m where m is null or m<1 or m>12)) then raise exception 'Invalid months';end if;
 select active_generation into generation from private.hub_kpi_report_state where tenant_id=p_tenant_id;
 first_year:=extract(year from p_from)::int-case when extract(month from p_from)<9 then 1 else 0 end;
 last_year:=extract(year from p_to)::int-case when extract(month from p_to)<9 then 1 else 0 end;
 for yr in first_year..last_year loop
  items:=items||coalesce(private.hub_kpi_internal_material_margin_v1(p_tenant_id,yr,coalesce(p_months,array[9,10,11,12,1,2,3,4,5,6,7,8]),
   jsonb_build_object('date_from',p_from,'date_to',p_to))->'details','[]');
 end loop;
 -- Resolve only the published source IDs, through canonical identity keys and
 -- the same dated classification / approved-cost-scope knowledge as transfers.
 with project_keys as materialized(
  select k.identity_value,count(distinct k.object_id) n,(array_agg(distinct k.object_id))[1] id
  from public.hub_identity_keys k join public.hub_objects o on o.id=k.object_id and o.tenant_id=k.tenant_id
  where k.tenant_id=p_tenant_id and k.identity_type='next_project_number' and k.confidence=1 and lower(o.object_type)='project'
  group by k.identity_value
 ), cost_scopes as materialized(select * from private.hub_material_approved_cost_scopes_v1(p_tenant_id)),
 source_rows as materialized(
  select d,x.source_data,
   (regexp_match(trim(coalesce(nullif(x.source_data->>'Littranummer',''),x.source_data->>'Projekt')),'^(?:AO)?([^[:space:]]+)','i'))[1] reference
  from jsonb_array_elements(items)d
  left join public.kpi_import_rows x on x.tenant_id=p_tenant_id and x.id=(d->>'source_row')::uuid
 ), receivers as materialized(
  select d,jsonb_build_object('project',s.reference,'receiver_id',case when k.n=1 then k.id end,
   'receiver_center',coalesce(cs.project_cost_center,case when c.n=1 then c.code else '10' end),
   'receiver_rule',case when cs.project_cost_center is null and c.n<>1 then 'Standardregel: 10 Entreprenad vid utebliven entydig KST-matchning' end,
   'littra',s.source_data->>'Littranummer','source_center',f.cost_center) r
  from source_rows s left join project_keys k on k.identity_value=s.reference
  left join lateral(select v.cost_center project_cost_center from cost_scopes v where v.project=s.reference and v.valid_from<=(d->>'date')::date order by v.valid_from desc limit 1)cs on true
  left join lateral(select count(distinct p.cost_center)n,min(p.cost_center)code from public.kpi_project_classification_periods p
   where p.tenant_id=p_tenant_id and p.project_reference=s.reference and p.valid_from<=(d->>'date')::date and (p.valid_to is null or p.valid_to>=(d->>'date')::date))c on true
  left join lateral(select p.cost_center from private.hub_kpi_prepared_facts p where p.tenant_id=p_tenant_id and p.generation_id=generation
   and p.fact_id in(d->>'source_row',(d->>'source_row')||':material') and p.category='material' and p.kind='revenue' limit 1)f on true
 ), linked as materialized(
  select d, t.r,
   t.r->>'receiver_center' receiver_center,
   case when t.r->>'receiver_center'='10' then nullif(t.r->>'receiver_id','') end project_id,
   coalesce(o.data->>'display_name',t.r->>'receiver_name') project_name,
   (d->>'billed')::numeric billed,(d->>'purchase_cost')::numeric purchase,
   case when (d->>'bundled')::boolean is not true then (d->>'difference')::numeric end refund
  from receivers t
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
