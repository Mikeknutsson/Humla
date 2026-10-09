-- Project financial ledger is separate from vehicle economics. Uses exact canonical
-- NEXT project identities and the latest user-confirmed project register.
create or replace function private.hub_kpi_project_report_v1(p_tenant_id uuid,p_from date,p_to date,p_center text default null,p_manager text default null,p_project uuid default null,p_page integer default 0,p_kind text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'Not authorized' using errcode='42501';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>1096 or p_page<0 or p_page>10000 or (p_center is not null and p_center not in ('10','60')) or (p_kind is not null and p_kind not in ('revenue','cost')) then raise exception 'Invalid project selection';end if;
 with registry as materialized(
  select r.project_number,r.project_name,r.project_manager,c.cost_center,c.business_group,k.object_id
  from public.kpi_next_project_register r
  join lateral(select x.cost_center,x.business_group from public.kpi_project_classification_periods x
   where x.tenant_id=p_tenant_id and x.project_reference=r.project_number and x.valid_from<=current_date and (x.valid_to is null or x.valid_to>=current_date)
   order by x.valid_from desc limit 1)c on c.cost_center in ('10','60')
  join lateral(select public.hub_resolve_canonical_object_v1(k.tenant_id,min(k.object_id::text)::uuid) object_id from public.hub_identity_keys k
   where k.tenant_id=p_tenant_id and k.identity_type='next_project_number' and k.identity_value=r.project_number and k.confidence=1
   having count(distinct public.hub_resolve_canonical_object_v1(k.tenant_id,k.object_id))=1)k on k.object_id is not null
  where r.tenant_id=p_tenant_id
 ), selected as materialized(
  select * from registry where (p_center is null or cost_center=p_center) and (p_manager is null or project_manager=p_manager) and (p_project is null or object_id=p_project)
 ), evidence as materialized(
  select r.id::text id,r.occurred_on date,r.data_kind kind,r.amount,r.account,r.description,r.project_reference project_number,s.object_id,
   b.file_name,r.row_number,r.validation_errors,
   case when private.hub_workify_customer_is_internal_v1(coalesce(nullif(r.source_data->>'Kundnamn',''),nullif(r.source_data->>'Leverantör',''),'')) then true else false end internal,
   case when cr.n=1 then cr.category when coalesce(r.source_data->>'Kontobeskrivning','') ~* '^löner? ' then 'personnel' else 'unclassified' end category
  from public.kpi_import_rows r join selected s on s.project_number=trim(r.project_reference)
  join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=p_tenant_id
  left join lateral(select count(distinct x.cost_category) n,min(x.cost_category) category from public.kpi_cost_category_rules x where x.tenant_id=p_tenant_id and x.account=r.account and x.valid_from<=r.occurred_on and (x.valid_to is null or x.valid_to>=r.occurred_on))cr on true
  where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum' and r.data_kind in ('revenue','cost')
   and r.occurred_on between p_from and p_to and r.amount is not null
   and (r.is_valid or r.validation_errors <@ '["Kostnadsfördelning behöver granskas","Fordonsbeteckning saknar verifierad regnummerkoppling"]'::jsonb)
 ), rollup as (
  select s.object_id id,s.project_number,s.project_name,s.cost_center,s.project_manager,s.business_group,count(e.id) rows,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue' and not e.internal),0),2) external_revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue' and e.internal),0),2) internal_revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='cost' and not e.internal),0),2) external_cost,
   round(coalesce(sum(e.amount) filter(where e.kind='cost' and e.internal),0),2) internal_cost,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0),2) revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) cost,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0)-coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) result,
   case when sum(e.amount) filter(where e.kind='revenue')>0 then round(100*(sum(e.amount) filter(where e.kind='revenue')-coalesce(sum(e.amount) filter(where e.kind='cost'),0))/(sum(e.amount) filter(where e.kind='revenue')),2) end margin,
   round(coalesce(sum(e.amount) filter(where e.kind='cost' and e.category='personnel'),0),2) personnel,
   count(e.id) filter(where e.kind='cost' and e.category='unclassified') unclassified_rows,
   count(e.id) filter(where e.validation_errors<>'[]'::jsonb) vehicle_allocation_pending
  from selected s left join evidence e on e.object_id=s.object_id group by s.object_id,s.project_number,s.project_name,s.cost_center,s.project_manager,s.business_group
 ), monthly as(
  select date_trunc('month',e.date)::date as month_start,round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0),2) revenue,
   round(coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) cost,
   round(coalesce(sum(e.amount) filter(where e.kind='revenue'),0)-coalesce(sum(e.amount) filter(where e.kind='cost'),0),2) result
  from evidence e group by 1
 ), totals as(
  select round(coalesce(sum(revenue),0),2) revenue,round(coalesce(sum(cost),0),2) cost,round(coalesce(sum(result),0),2) result,
   case when sum(revenue)>0 then round(100*sum(result)/sum(revenue),2) end margin,
   round(coalesce(sum(personnel),0),2) personnel,round(coalesce(sum(internal_revenue),0),2) internal_revenue,
   round(coalesce(sum(internal_cost),0),2) internal_cost,round(coalesce(sum(external_revenue),0),2) external_revenue,
   round(coalesce(sum(external_cost),0),2) external_cost,sum(rows) rows,sum(vehicle_allocation_pending) vehicle_allocation_pending,sum(unclassified_rows) unclassified_rows
  from rollup
 ), details as(
  select * from evidence where p_project is not null and (p_kind is null or kind=p_kind) order by date desc,id limit 200 offset p_page*200
 )
 select jsonb_build_object('from',p_from,'to',p_to,'source','NeXT projektbokföring','salary_source','NeXT för KST 10 och 60; TransPA används för Transport KST 30',
  'scope','Uppdelning enligt senaste bekräftade projektregister. Bokförda belopp, exklusive moms. Resultatet avser importerade poster, inte slutprognos.',
  'summary',(select to_jsonb(t) from totals t),'projects',coalesce((select jsonb_agg(to_jsonb(r) order by r.project_number) from rollup r),'[]'::jsonb),
  'months',coalesce((select jsonb_agg(to_jsonb(m) order by month_start) from monthly m),'[]'::jsonb),
  'managers',coalesce((select jsonb_agg(name order by name) from(select distinct project_manager name from registry where project_manager<>'')m),'[]'::jsonb),
  'transactions',coalesce((select jsonb_agg(to_jsonb(e) order by date desc,id) from details e),'[]'::jsonb),
  'transaction_count',case when p_project is null then 0 else (select count(*) from evidence where p_kind is null or kind=p_kind) end,
  'excluded_rows',(select count(*) from public.kpi_import_rows r join selected s on s.project_number=trim(r.project_reference) where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum' and r.occurred_on between p_from and p_to and (r.amount is null or (not r.is_valid and not(r.validation_errors <@ '["Kostnadsfördelning behöver granskas","Fordonsbeteckning saknar verifierad regnummerkoppling"]'::jsonb)))),
  'latest_source_date',(select max(r.occurred_on) from public.kpi_import_rows r join selected s on s.project_number=trim(r.project_reference) where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum'),
  'unassigned_rows',(select count(*) from public.kpi_import_rows r where r.tenant_id=p_tenant_id and r.source_data?'Projektnr' and r.source_data?'Bokf datum' and r.occurred_on between p_from and p_to and not exists(select 1 from registry s where s.project_number=trim(r.project_reference)) and trim(r.cost_center) in ('10','60'))
 ) into answer;
 return answer;
end $$;
revoke all on function private.hub_kpi_project_report_v1(uuid,date,date,text,text,uuid,integer,text) from public,anon;
grant execute on function private.hub_kpi_project_report_v1(uuid,date,date,text,text,uuid,integer,text) to authenticated;
create or replace function public.hub_kpi_project_report_v1(p_tenant_id uuid,p_from date,p_to date,p_center text default null,p_manager text default null,p_project uuid default null,p_page integer default 0,p_kind text default null)
returns jsonb language sql stable security invoker set search_path='' set statement_timeout='45s' as $$
 select private.hub_kpi_project_report_v1(p_tenant_id,p_from,p_to,p_center,p_manager,p_project,p_page,p_kind)
$$;
revoke all on function public.hub_kpi_project_report_v1(uuid,date,date,text,text,uuid,integer,text) from public,anon;
grant execute on function public.hub_kpi_project_report_v1(uuid,date,date,text,text,uuid,integer,text) to authenticated;
notify pgrst,'reload schema';
