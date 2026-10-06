-- Mike's confirmed rules, effective from the current historical reporting baseline.
-- Run within a transaction as the authorized KPI administrator.
do $rules$
declare tenant uuid; project_id uuid; alias_result text; batch record;
begin
 select tenant_id into strict tenant from public.hub_tenant_members where user_id=auth.uid() and status='active';
 if not public.hub_has_permission(tenant,'kpi.manage') then raise exception 'KPI-administratör krävs';end if;
 select object_id into strict project_id from public.hub_identity_keys where tenant_id=tenant and object_type='Project' and identity_type='next_project_number' and identity_value='1081' and confidence=1;
 alias_result:=public.hub_identity_attach_alias_v1(tenant,project_id,'Project','next_project_number','1023',1);
 if alias_result='conflict' then raise exception 'Projektalias 1023 har en annan canonical identitet';end if;
 perform public.hub_kpi_match_save_v1(tenant,'[{"reference":"1023","reference_type":"project","source":"NEXT","kind":"cost"},{"reference":"1023","reference_type":"project","source":"Workify","kind":"revenue"}]','project','1081','2025-09-01',null,'Mike: Projekt 1023 ska gå på projekt 1081');
 perform public.hub_kpi_save_rule_v1(tenant,'article','{"reference":"3-28","name":"Tippavgift IFA-Betong","target_type":"project","project":"5100","category":"tipp_deponi","valid_from":"2025-09-01"}');
 insert into public.kpi_workify_article_rules(tenant_id,article_number,article_name,target_type,revenue_category,valid_from,enabled,source_hash,source_file,source_rows)
 values(tenant,'1-1-1','Antal Lass','vehicle','ignored','2025-09-01',true,md5('Mike 2026-10-06: 1-1-1 är Antal Lass utan belopp'),'User confirmed information article',jsonb_build_array(jsonb_build_object('confirmed_by',auth.uid(),'confirmed_at',now(),'rule','Ignore zero-value Antal Lass; nonzero values remain in review')));
 for batch in select id from public.kpi_import_batches where tenant_id=tenant and data_kind='revenue' and status in('completed','needs_review') loop
  perform public.hub_kpi_resolve_workify_import_v1(tenant,batch.id);
 end loop;
end $rules$;
