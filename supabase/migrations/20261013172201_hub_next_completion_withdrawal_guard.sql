create function private.hub_next_approved_cost_in_scope_v1(p_row uuid,p_date date,p_amount numeric,p_errors jsonb)
returns boolean language sql stable set search_path='' as $$
 select case when jsonb_typeof(coalesce(p_errors,'[]'))<>'array' then false else
 not exists(select 1 from jsonb_array_elements_text(coalesce(p_errors,'[]'))e
 where e not in('Kostnadsfördelning behöver granskas','Fordonsbeteckning saknar verifierad regnummerkoppling'))
 and exists(select 1 from private.hub_next_completeness_items i
 join public.kpi_import_rows r on r.id=i.row_id and r.tenant_id=i.tenant_id
 join public.kpi_import_batches b on b.id=r.batch_id and b.tenant_id=r.tenant_id
 where i.row_id=p_row and i.occurred_on=p_date and i.amount=p_amount and r.data_kind='cost'
 and b.status in('completed','needs_review') and not(coalesce(b.provenance,'{}')?'withdrawal')) end;
$$;
revoke all on function private.hub_next_approved_cost_in_scope_v1(uuid,date,numeric,jsonb) from public,anon;
grant execute on function private.hub_next_approved_cost_in_scope_v1(uuid,date,numeric,jsonb) to authenticated,service_role;
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.hub_kpi_import_row_in_scope_v2(uuid,text,date,numeric,boolean,jsonb,jsonb)'::regprocedure);
 needle:='(p_kind=''cost'' and exists(select 1 from private.hub_next_completeness_items where row_id=p_row))';
 if strpos(definition,needle)=0 then raise exception 'Unexpected NEXT completeness predicate';end if;
 execute replace(definition,needle,'(p_kind=''cost'' and private.hub_next_approved_cost_in_scope_v1(p_row,p_date,p_amount,p_errors))');
 definition:=pg_get_functiondef('public.hub_next_completeness_review_v1(uuid,integer,text)'::regprocedure);
 needle:='case when r.status=''verified'' then ''included_unallocated'' else s.review_state end';
 if strpos(definition,needle)=0 then raise exception 'Unexpected NEXT completeness status';end if;
 execute replace(definition,needle,'case when r.status=''verified'' and s.review_state=''candidate_include_unallocated'' then ''included_unallocated'' else s.review_state end');
end $migration$;
