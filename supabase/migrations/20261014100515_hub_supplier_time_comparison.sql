-- Actual NEXT hours are compared with posted invoice costs. No invoice hours,
-- billing rate or service period are inferred from currency amounts.
create or replace function public.hub_supplier_work_time_v1(p_tenant uuid,p_from date,p_to date,p_assignment uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare answer jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read')then raise exception 'KPI access required';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'Invalid period';end if;
 with binding as materialized(
 select a.*,s.identity_value supplier_reference,n.identity_value person_reference,po.data->>'name' person_name,so.data->>'name' supplier_name
 from public.hub_assignments a
 join public.hub_objects po on po.id=a.subject_object_id and po.tenant_id=p_tenant and po.object_type='Person'
 join public.hub_objects so on so.id=a.context_object_id and so.tenant_id=p_tenant and so.object_type='Supplier'
 join public.hub_identity_keys s on s.object_id=so.id and s.tenant_id=p_tenant and s.identity_type='next_supplier_name' and s.confidence=1
 join public.hub_identity_keys n on n.object_id=po.id and n.tenant_id=p_tenant and n.identity_type='next_person_name' and n.confidence=1
 where a.tenant_id=p_tenant and a.status='active' and a.assignment_type='supplier_work_time_reporting'
 and (p_assignment is null or a.object_id=p_assignment)
 and (a.valid_from is null or a.valid_from<((p_to+1)::timestamp at time zone 'Europe/Stockholm'))
 and (a.valid_to is null or a.valid_to>=(p_from::timestamp at time zone 'Europe/Stockholm'))
 order by a.object_id limit 1
 ), time_batch as materialized(
 select b.* from public.kpi_import_batches b cross join binding a
 where b.tenant_id=p_tenant and b.data_kind='next_historical_time' and b.status='completed'
 and exists(select 1 from public.kpi_import_rows r where r.batch_id=b.id and r.tenant_id=p_tenant and r.occurred_on between p_from and p_to
 and upper(trim(coalesce(r.employee_number,r.source_data->>'Namn')))=a.person_reference)
 order by b.created_at desc,b.id desc limit 1
 ), hours as materialized(
 select r.* from public.kpi_import_rows r join time_batch b on b.id=r.batch_id and b.tenant_id=r.tenant_id cross join binding a
 where r.tenant_id=p_tenant and r.occurred_on between p_from and p_to
 and upper(trim(coalesce(r.employee_number,r.source_data->>'Namn')))=a.person_reference
 and (a.valid_from is null or r.occurred_on>=(a.valid_from at time zone 'Europe/Stockholm')::date)
 and (a.valid_to is null or r.occurred_on<=(a.valid_to at time zone 'Europe/Stockholm')::date)
 ), valid_hours as(
 select * from hours where is_valid and lower(trim(source_data->>'Godkänd'))in('true','ja','1')
 and paid_hours>=0 and project_reference<>'99999' and lower(trim(source_data->>'Projektnamn'))<>'frånvaro'
 ), time_projects as(
 select project_reference project,min(source_data->>'Projektnamn') name,sum(paid_hours) hours,count(*) time_rows,
 jsonb_agg(jsonb_build_object('id',id,'date',occurred_on,'hours',paid_hours,'row',row_number)order by occurred_on,row_number)time_details
 from valid_hours group by 1
 ), invoices as materialized(
 select f.* from private.hub_kpi_prepared_facts f cross join binding a
 join private.hub_kpi_report_state state on state.tenant_id=p_tenant and state.active_generation=f.generation_id
 where f.tenant_id=p_tenant and f.source='NEXT' and f.kind='cost' and f.occurred_on between p_from and p_to
 and upper(trim(f.original->>'Leverantör'))=a.supplier_reference
 ), cost_projects as(
 select project,sum(amount) invoice_cost,count(*) invoice_rows,
 jsonb_agg(jsonb_build_object('id',fact_id,'date',occurred_on,'amount',amount,'category',category,
 'voucher',original->>'Verifikation nr','text',original->>'Verifikationstext')order by occurred_on,fact_id)invoice_details
 from invoices group by 1
 ), projects as(
 select coalesce(t.project,c.project) project,t.name,coalesce(t.hours,0)hours,coalesce(c.invoice_cost,0)invoice_cost,
 coalesce(t.time_rows,0)time_rows,coalesce(c.invoice_rows,0)invoice_rows,
 case when t.project is not null and c.project is not null then 'same_project' when t.project is null then 'invoice_only' else 'hours_only' end match_status,
 coalesce(t.time_details,'[]') time_details,coalesce(c.invoice_details,'[]')invoice_details
 from time_projects t full join cost_projects c on c.project=t.project
 )select jsonb_build_object('available',exists(select 1 from binding),'binding',(select jsonb_build_object('id',object_id,'supplier_id',context_object_id,'person_id',subject_object_id,'supplier',supplier_name,'person',person_name)from binding),
 'time_source',(select jsonb_build_object('id',id,'file_name',file_name,'period_start',period_start,'period_end',period_end)from time_batch),
 'totals',jsonb_build_object('hours',(select coalesce(sum(hours),0)from projects),'invoice_cost',(select coalesce(sum(invoice_cost),0)from projects),
 'matched_projects',(select count(*)from projects where match_status='same_project'),'review_time_rows',(select count(*)from hours where not is_valid or coalesce(lower(trim(source_data->>'Godkänd')),'')not in('true','ja','1') or paid_hours is null or paid_hours<0)),
 'projects',coalesce((select jsonb_agg(to_jsonb(p)order by project)from projects p),'[]'))into answer;
 return answer;
end $$;
revoke all on function public.hub_supplier_work_time_v1(uuid,date,date,uuid)from public,anon;
grant execute on function public.hub_supplier_work_time_v1(uuid,date,date,uuid)to authenticated;
