-- Mapping resolution must not clear an unresolved financial-source revision.
do $patch$
declare definition text; original text;
begin
 original:=pg_get_functiondef('public.hub_kpi_ingest_workify_file_v1(uuid,uuid,jsonb)'::regprocedure);
 definition:=replace(original,
  'status=case when inserted=valid then ''completed'' else ''needs_review'' end,',
  'status=result->>''status'', error_summary=coalesce(error_summary,''[]''::jsonb)||conflicts,');
 if definition=original then raise exception 'Workify review-status patch point missing';end if;
 execute definition;
 original:=pg_get_functiondef('public.hub_kpi_resolve_workify_import_v1(uuid,uuid)'::regprocedure);
 definition:=replace(original,
  'declare resolved integer; valid integer; invalid integer;',
  'declare resolved integer; valid integer; invalid integer; source_revision boolean;');
 definition:=replace(definition,
  'update public.kpi_import_batches set valid_row_count=valid,',
  'select coalesce((provenance#>>''{workify_import_result,changedRows}'')::integer,0)>0 into source_revision from public.kpi_import_batches where tenant_id=p_tenant_id and id=p_batch_id;
 update public.kpi_import_batches set valid_row_count=valid,');
 definition:=replace(definition,'case when invalid=0 then ''completed'' else ''needs_review'' end',
  'case when invalid=0 and not source_revision then ''completed'' else ''needs_review'' end');
 if definition=original or position('into source_revision' in definition)=0 then raise exception 'Workify resolver review-status patch point missing';end if;
 execute definition;
end $patch$;
notify pgrst,'reload schema';
