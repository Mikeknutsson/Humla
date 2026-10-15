-- Source-only people are retained when there is no unique canonical name match.
-- The adapter accepts original rows; approval is stored separately from source data.
create function private.hub_import_approved_next_time_rows_v1(p_tenant uuid,p_batch uuid,p_rows jsonb,p_approval text)
returns integer language plpgsql set search_path='' as $$
declare r jsonb;person uuid;matches integer;key_name text;b public.kpi_import_batches;n integer:=0;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required'using errcode='42501';end if;
 select * into strict b from public.kpi_import_batches where tenant_id=p_tenant and id=p_batch for update;
 if b.data_kind<>'next_historical_time'or b.status<>'processing'or nullif(trim(p_approval),'')is null then raise exception 'Invalid approved import';end if;
 for r in select value from jsonb_array_elements(p_rows)loop
  if(r->>'work_date')::date not between b.period_start and b.period_end or(r->>'hours')::numeric<0 or nullif(r->>'person_name','')is null then raise exception 'Invalid source row';end if;
  key_name:=upper(trim(r->>'person_name'));
  select count(distinct object_id),(array_agg(distinct object_id))[1]into matches,person from public.hub_identity_keys
   where tenant_id=p_tenant and object_type='Person'and identity_type='next_person_name'and identity_value=key_name and confidence=1;
  if matches>1 then raise exception 'Ambiguous NEXT person identity';end if;
  if matches=0 then
   select count(*),(array_agg(id))[1]into matches,person from public.hub_objects
    where tenant_id=p_tenant and object_type='Person'and status='active'
    and(key_name=upper(trim(data->>'display_name'))or key_name=upper(trim(data->>'name')));
   if matches>1 then raise exception 'Ambiguous canonical person name';end if;
   if matches=0 then
    insert into public.hub_objects(tenant_id,object_type,data,source_of_truth)
     values(p_tenant,'Person',jsonb_build_object('display_name',r->>'person_name','source_only',true,'source','NEXT'),'NEXT')returning id into person;
   end if;
   insert into public.hub_identity_keys(tenant_id,object_id,object_type,identity_type,identity_value,confidence)
    values(p_tenant,person,'Person','next_person_name',key_name,1);
  end if;
  if exists(select 1 from public.kpi_import_rows where batch_id=p_batch and row_number=(r->>'row_number')::int)then
   if not exists(select 1 from public.kpi_import_rows x where x.batch_id=p_batch and x.row_number=(r->>'row_number')::int
    and x.source_data-'_humla_time_approval'=r->'raw'and x.paid_hours=(r->>'hours')::numeric and x.employee_object_id=person)then raise exception 'Existing physical row differs';end if;
  else
   insert into public.kpi_import_rows(tenant_id,batch_id,row_number,data_kind,occurred_on,employee_object_id,employee_number,
    project_reference,cost_center,description,quantity,paid_hours,source_data,source_system,external_transaction_id,source_fingerprint)
   values(p_tenant,p_batch,(r->>'row_number')::int,'next_historical_time',(r->>'work_date')::date,person,r->>'person_name',
    r->>'project',r->>'cost_center','HISTORICAL',(r->>'hours')::numeric,(r->>'hours')::numeric,
    (r->'raw')||jsonb_build_object('_humla_time_approval',jsonb_build_object('approved',true,'approved_by',auth.uid(),'reference',p_approval)),
    'NEXT',b.file_hash||':'||(r->>'row_number'),b.file_hash||':'||(r->>'row_number'));
   n:=n+1;
  end if;
 end loop;
 return n;
end $$;
revoke all on function private.hub_import_approved_next_time_rows_v1(uuid,uuid,jsonb,text)from public,anon,authenticated;
