create function public.hub_next_reexport_status_v1(p_tenant_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare run record;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 select * into run from private.hub_next_reexport_activation where tenant_id=p_tenant_id order by verified_at desc nulls first,id limit 1;
 if not found then return jsonb_build_object('active',false,'rows',0,'amount','0','status','not_started');end if;
 return jsonb_build_object('active',run.status='verified','status',run.status,'rows',run.expected_rows,
 'amount',run.expected_removed::text,'difference',run.result->'difference','verifiedAt',run.verified_at);
end $$;
revoke all on function public.hub_next_reexport_status_v1(uuid) from public,anon;
grant execute on function public.hub_next_reexport_status_v1(uuid) to authenticated;

do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('private.hub_cost_review_rows_v1(uuid)'::regprocedure);
 needle:='else ''review_required'' end,';
 if strpos(definition,needle)=0 then raise exception 'Unexpected NEXT review classification';end if;
 definition:=replace(definition,needle,'when exists(select 1 from private.hub_next_reexport_audit a where a.row_id=id and a.tenant_id=p_tenant) then ''verified_duplicate'' else ''review_required'' end,');
 definition:=replace(definition,'when candidate<>id then ''possible_duplicate_without_source_line_id''',
 'when exists(select 1 from private.hub_next_reexport_audit a where a.row_id=id and a.tenant_id=p_tenant) then ''confirmed_reexport_overlap'' when candidate<>id then ''possible_duplicate_without_source_line_id''');
 definition:=replace(definition,'case when candidate<>id then candidate end,source_data',
 'coalesce((select a.canonical_row_id from private.hub_next_reexport_audit a where a.row_id=id and a.tenant_id=p_tenant),case when candidate<>id then candidate end),source_data');
 execute definition;
 definition:=pg_get_functiondef('public.hub_cost_review_v1(uuid,integer)'::regprocedure);
 needle:='''verifiedDuplicateRows'',0';
 if strpos(definition,needle)=0 then raise exception 'Unexpected NEXT review totals';end if;
 definition:=replace(definition,needle,'''verifiedDuplicateRows'',(select count(*)from facts where review_state=''verified_duplicate'')');
 definition:=replace(definition,'candidate_row_id is not null and review_state<>''invalid''','candidate_row_id is not null and review_state=''review_required''');
 definition:=replace(definition,'review_state in (''invalid'',''review_required'')','review_state in (''invalid'',''review_required'',''verified_duplicate'')');
 execute definition;
end $migration$;
